import Foundation
import CoreGraphics
import UIKit

final class TouchInjector {
    static let shared = TouchInjector()

    private(set) var method: String = "none"
    private(set) var lastError: String = ""
    private(set) var injectionCount: Int = 0
    private(set) var hidError: String = ""
    private(set) var gsError: String = ""
    private(set) var userdevError: String = ""
    private(set) var cgeventError: String = ""
    private(set) var kernelError: String = ""
    private(set) var hidSendFailures: Int = 0
    private(set) var hidDispatchErr: Int = 0
    private(set) var helperReady: Bool = false
    private(set) var helperError: String = ""
    private(set) var tweakConnected: Bool = false

    private init() {
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height
        userdev_set_screen_size(Float(w), Float(h))

        let helperErr = HelperExecutor.shared.prepare()
        helperReady = HelperExecutor.shared.isReady
        helperError = helperErr

        tweakConnected = TweakComm.shared.connect()

        let m = inject_method()
        switch m {
        case 0: method = "IOKit HID"
        case 1: method = "GraphicsServices"
        case 2: method = "IOKit UserDevice"
        case 3: method = "CGEvent"
        default: method = "none"
        }
        hidError = String(cString: hid_error())
        gsError = String(cString: gs_error())
        userdevError = String(cString: userdev_error())
        cgeventError = String(cString: cgevent_error())
        kernelError = String(cString: kernel_error())
        hidSendFailures = Int(hid_send_failures())
        hidDispatchErr = Int(hid_dispatch_err())

        if m < 0 && !helperReady {
            lastError = String(cString: inject_error())
            print("[TouchInjector] Init: \(lastError)")
        } else if helperReady {
            print("[TouchInjector] Helper binary ready")
        } else {
            print("[TouchInjector] Using \(method)")
        }
    }

    var canInject: Bool {
        let m = inject_method()
        let ok = m >= 0 || helperReady || tweakConnected
        if !ok { lastError = String(cString: inject_error()) }
        return ok
    }

    private func dispatchTouch(at point: CGPoint, fingerId: Int32 = 0, phase: Int) {
        // Kernel direct (IOKit user client) takes highest priority
        if kernel_ready() {
            if phase == 0 { kernel_touch_down(Float(point.x), Float(point.y)) }
            else if phase == 1 { kernel_touch_move(Float(point.x), Float(point.y)) }
            else { kernel_touch_up(Float(point.x), Float(point.y)) }
            return
        }
        // Tweak (SpringBoard injection) takes second priority
        if tweakConnected {
            if phase == 0 { _ = TweakComm.shared.touchDown(at: point) }
            else if phase == 1 { _ = TweakComm.shared.touchMove(to: point) }
            else { _ = TweakComm.shared.touchUp(at: point) }
            return
        }
        // Helper binary takes third priority
        if helperReady {
            let _ = HelperExecutor.shared.sendTouch(
                type: Int32(phase), x: Float(point.x), y: Float(point.y), fingerId: fingerId)
            return
        }
        let m = inject_method()
        switch m {
        case 4: // Kernel direct
            if phase == 0 { kernel_touch_down(Float(point.x), Float(point.y)) }
            else if phase == 2 { kernel_touch_up(Float(point.x), Float(point.y)) }
        case 1: // GraphicsServices (GSEvent via GSSendEvent)
            if phase == 0 { gs_touch_down(Float(point.x), Float(point.y)) }
            else if phase == 1 { gs_touch_move(Float(point.x), Float(point.y)) }
            else { gs_touch_up(Float(point.x), Float(point.y)) }
        case 0: // IOKit HID
            if phase == 0 { hid_touch_down(Float(point.x), Float(point.y), fingerId) }
            else if phase == 1 { hid_touch_move(Float(point.x), Float(point.y), fingerId) }
            else { hid_touch_up(Float(point.x), Float(point.y), fingerId) }
        case 2: // IOHIDUserDevice
            userdev_touch(Float(point.x), Float(point.y), fingerId, Int32(phase))
        case 3: // CGEvent
            if phase == 0 { cgevent_touch_down(Float(point.x), Float(point.y)) }
            else if phase == 1 { }
            else { cgevent_touch_up(Float(point.x), Float(point.y)) }
        default:
            break
        }
    }

    func touchDown(at point: CGPoint, fingerId: Int32 = 0) {
        guard canInject else { return }
        dispatchTouch(at: point, fingerId: fingerId, phase: 0)
        injectionCount += 1
    }

    func touchMove(to point: CGPoint, fingerId: Int32 = 0) {
        guard canInject else { return }
        if kernel_ready() {
            kernel_touch_move(Float(point.x), Float(point.y))
            injectionCount += 1; return
        }
        if tweakConnected {
            _ = TweakComm.shared.touchMove(to: point)
            injectionCount += 1; return
        }
        if helperReady {
            let _ = HelperExecutor.shared.sendTouch(
                type: 1, x: Float(point.x), y: Float(point.y), fingerId: fingerId)
            injectionCount += 1
            return
        }
        let m = inject_method()
        switch m {
        case 4: kernel_touch_move(Float(point.x), Float(point.y))
        case 1: gs_touch_move(Float(point.x), Float(point.y))
        case 0: hid_touch_move(Float(point.x), Float(point.y), fingerId)
        case 2: userdev_touch(Float(point.x), Float(point.y), fingerId, 1)
        case 3: cgevent_touch_down(Float(point.x), Float(point.y))
        default: break
        }
        injectionCount += 1
    }

    func touchUp(at point: CGPoint, fingerId: Int32 = 0) {
        guard canInject else { return }
        dispatchTouch(at: point, fingerId: fingerId, phase: 2)
        injectionCount += 1
    }

    func tap(at point: CGPoint) {
        print("[TouchInjector] tap(\(Int(point.x)), \(Int(point.y))) method=\(method)")
        guard canInject else { print("[TouchInjector] Cannot tap — \(lastError)"); return }
        touchDown(at: point)
        usleep(60000)
        touchUp(at: point)
    }

    func longPress(at point: CGPoint, duration: TimeInterval) {
        guard canInject else { print("[TouchInjector] Cannot longPress — \(lastError)"); return }
        print("[TouchInjector] longPress(\(Int(point.x)), \(Int(point.y)), \(duration))")
        touchDown(at: point)
        usleep(UInt32(duration * 1_000_000))
        touchUp(at: point)
    }

    func swipe(from start: CGPoint, to end: CGPoint, duration: TimeInterval = 0.3) {
        print("[TouchInjector] swipe(\(Int(start.x)),\(Int(start.y)) -> \(Int(end.x)),\(Int(end.y)), \(duration)) method=\(method)")
        guard canInject else { print("[TouchInjector] Cannot swipe — \(lastError)"); return }

        let steps = max(10, Int(duration * 120))
        let interval = duration / Double(steps)
        touchDown(at: start)
        for i in 1...steps {
            usleep(UInt32(interval * 1_000_000))
            let t = Double(i) / Double(steps)
            let cx = start.x + (end.x - start.x) * t
            let cy = start.y + (end.y - start.y) * t
            touchMove(to: CGPoint(x: cx, y: cy))
        }
        usleep(40000)
        touchUp(at: end)
    }
}

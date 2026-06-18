import Foundation
import CoreGraphics

final class TouchInjector {
    static let shared = TouchInjector()

    private(set) var method: String = "none"
    private(set) var lastError: String = ""
    private(set) var injectionCount: Int = 0
    private(set) var hidError: String = ""
    private(set) var gsError: String = ""

    private init() {
        let m = inject_method()
        switch m {
        case 0: method = "IOKit HID"
        case 1: method = "GraphicsServices"
        default: method = "none"
        }
        hidError = String(cString: hid_error())
        gsError = String(cString: gs_error())

        if m < 0 {
            lastError = String(cString: inject_error())
            print("[TouchInjector] Init: \(lastError)")
        } else {
            print("[TouchInjector] Using \(method)")
        }
    }

    var canInject: Bool {
        let m = inject_method()
        let ok = m >= 0
        if !ok {
            lastError = String(cString: inject_error())
        }
        return ok
    }

    func touchDown(at point: CGPoint, fingerId: Int32 = 0) {
        guard canInject else { return }
        switch inject_method() {
        case 0: hid_touch_down(Float(point.x), Float(point.y), fingerId)
        case 1: gs_touch_down(Float(point.x), Float(point.y))
        default: break
        }
        injectionCount += 1
    }

    func touchMove(to point: CGPoint, fingerId: Int32 = 0) {
        guard canInject else { return }
        switch inject_method() {
        case 0: hid_touch_move(Float(point.x), Float(point.y), fingerId)
        case 1: gs_touch_move(Float(point.x), Float(point.y))
        default: break
        }
        injectionCount += 1
    }

    func touchUp(at point: CGPoint, fingerId: Int32 = 0) {
        guard canInject else { return }
        switch inject_method() {
        case 0: hid_touch_up(Float(point.x), Float(point.y), fingerId)
        case 1: gs_touch_up(Float(point.x), Float(point.y))
        default: break
        }
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

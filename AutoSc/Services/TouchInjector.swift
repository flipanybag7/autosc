import Foundation
import CoreGraphics

final class TouchInjector {
    static let shared = TouchInjector()

    private(set) var method: String = "none"

    private init() {
        let m = inject_method()
        switch m {
        case 0: method = "IOKit HID"
        case 1: method = "GraphicsServices"
        default: method = "none"
        }
    }

    var canInject: Bool { inject_method() >= 0 }

    func touchDown(at point: CGPoint, fingerId: Int32 = 0) {
        switch inject_method() {
        case 0: hid_touch_down(Float(point.x), Float(point.y), fingerId)
        case 1: gs_touch_down(Float(point.x), Float(point.y))
        default: break
        }
    }

    func touchMove(to point: CGPoint, fingerId: Int32 = 0) {
        switch inject_method() {
        case 0: hid_touch_move(Float(point.x), Float(point.y), fingerId)
        case 1: gs_touch_move(Float(point.x), Float(point.y))
        default: break
        }
    }

    func touchUp(at point: CGPoint, fingerId: Int32 = 0) {
        switch inject_method() {
        case 0: hid_touch_up(Float(point.x), Float(point.y), fingerId)
        case 1: gs_touch_up(Float(point.x), Float(point.y))
        default: break
        }
    }

    func tap(at point: CGPoint) {
        touchDown(at: point)
        usleep(60000)
        touchUp(at: point)
    }

    func longPress(at point: CGPoint, duration: TimeInterval) {
        touchDown(at: point)
        usleep(UInt32(duration * 1_000_000))
        touchUp(at: point)
    }

    func swipe(from start: CGPoint, to end: CGPoint, duration: TimeInterval = 0.3) {
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

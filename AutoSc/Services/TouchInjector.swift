import Foundation
import UIKit

final class TouchInjector: ObservableObject {
    static let shared = TouchInjector()

    @Published var method: String = "none"
    @Published var isRoot: Bool = false
    @Published var statusDetail: String = ""

    private(set) var canInject: Bool = false

    private let helperPath = "/tmp/.autosc_th"

    private init() {
        setupHelper()
        hid_init()
        gs_init()
        updateMethod()
    }

    private func setupHelper() {
        guard !helperBinaryB64.isEmpty else {
            statusDetail = "Helper binary not embedded"
            return
        }
        guard let data = Data(base64Encoded: helperBinaryB64) else {
            statusDetail = "Base64 decode failed"
            return
        }
        do {
            try data.write(to: URL(fileURLWithPath: helperPath))
        } catch {
            statusDetail = "Write failed: \(error.localizedDescription)"
            return
        }
        chmod(helperPath, 0o4755)
        if helper_init(helperPath) {
            statusDetail = "Helper ready at \(helperPath)"
            if helper_is_root() {
                isRoot = true
                statusDetail += " (with sudo)"
            }
        } else {
            statusDetail = "Helper not executable"
        }
    }

    private func updateMethod() {
        let m = inject_method()
        switch m {
        case 0: method = isRoot ? "Helper (root/sudo)" : "Helper (no root)"
        case 1: method = "IOKit HID"
        case 2: method = "GraphicsServices"
        default: method = "none"
        }
        canInject = (m >= 0)
    }

    func touchDown(at point: CGPoint, fingerId: Int32 = 0) {
        let m = inject_method()
        switch m {
        case 0: helper_touch_down(Float(point.x), Float(point.y), fingerId)
        case 1: hid_touch_down(Float(point.x), Float(point.y), fingerId)
        case 2: gs_touch_down(Float(point.x), Float(point.y))
        default: break
        }
    }

    func touchMove(to point: CGPoint, fingerId: Int32 = 0) {
        let m = inject_method()
        switch m {
        case 0: helper_touch_move(Float(point.x), Float(point.y), fingerId)
        case 1: hid_touch_move(Float(point.x), Float(point.y), fingerId)
        case 2: gs_touch_move(Float(point.x), Float(point.y))
        default: break
        }
    }

    func touchUp(at point: CGPoint, fingerId: Int32 = 0) {
        let m = inject_method()
        switch m {
        case 0: helper_touch_up(Float(point.x), Float(point.y), fingerId)
        case 1: hid_touch_up(Float(point.x), Float(point.y), fingerId)
        case 2: gs_touch_up(Float(point.x), Float(point.y))
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
            touchMove(to: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
        }
        usleep(40000)
        touchUp(at: end)
    }
}

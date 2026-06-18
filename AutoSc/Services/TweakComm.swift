import Foundation

final class TweakComm {
    static let shared = TweakComm()
    private let portName = "com.autosc.tweak"
    private var port: CFMessagePort?
    private(set) var connected = false
    private(set) var lastError = ""

    private init() {}

    func connect() -> Bool {
        if connected { return true }
        port = CFMessagePortCreateRemote(kCFAllocatorDefault, portName as CFString)
        connected = port != nil
        if !connected { lastError = "CFMessagePortCreateRemote failed (tweak not loaded?)" }
        return connected
    }

    private struct TouchMessage {
        let magic: UInt32 = 0x41544F53
        let type: UInt32
        let x: Float
        let y: Float
        let x2: Float
        let y2: Float
        let duration: Float
    }

    private func send(type: UInt32, x: Float, y: Float, x2: Float = 0, y2: Float = 0, duration: Float = 0) -> Bool {
        guard let port = port else { lastError = "Not connected"; return false }
        var msg = TouchMessage(type: type, x: x, y: y, x2: x2, y2: y2, duration: duration)
        let data = Data(bytes: &msg, count: MemoryLayout<TouchMessage>.size)
        let cfdata = data as CFData

        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(port, 0, cfdata, 0.5, 0.0, CFRunLoopMode.defaultMode.rawValue, &reply)
        if status != 0 {
            lastError = "CFMessagePortSendRequest returned \(status)"
            connected = false
            port = nil
            return false
        }
        return true
    }

    func touchDown(at point: CGPoint) -> Bool {
        send(type: 1, x: Float(point.x), y: Float(point.y))
    }

    func touchMove(to point: CGPoint) -> Bool {
        send(type: 2, x: Float(point.x), y: Float(point.y))
    }

    func touchUp(at point: CGPoint) -> Bool {
        send(type: 3, x: Float(point.x), y: Float(point.y))
    }

    func tap(at point: CGPoint) -> Bool {
        send(type: 0, x: Float(point.x), y: Float(point.y))
    }

    func swipe(from start: CGPoint, to end: CGPoint, duration: TimeInterval) -> Bool {
        send(type: 4, x: Float(start.x), y: Float(start.y), x2: Float(end.x), y2: Float(end.y), duration: Float(duration))
    }
}

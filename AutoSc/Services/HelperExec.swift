import Foundation

final class HelperExecutor {
    static let shared = HelperExecutor()
    private var helperPath: String?

    private init() {}

    var isReady: Bool {
        helperPath != nil
    }

    func prepare() -> String {
        if let path = helperPath {
            if FileManager.default.fileExists(atPath: path) { return "" }
        }

        guard !helperBinaryB64.isEmpty else {
            return "Helper binary not embedded (CI-only feature)"
        }

        guard let data = Data(base64Encoded: helperBinaryB64) else {
            return "Failed to decode base64 helper"
        }

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("th_\(UUID().uuidString.prefix(8))")

        do {
            try data.write(to: tmp)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
            helperPath = tmp.path
            return ""
        } catch {
            return "Failed to write helper: \(error.localizedDescription)"
        }
    }

    func execute(args: [String]) -> String {
        if let err = prepare(), !err.isEmpty { return err }
        guard let path = helperPath else { return "Helper not ready" }

        var pid: pid_t = 0
        var argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]

        let ret = posix_spawn(&pid, path, nil, nil, &argv, environ)
        for ptr in argv { if let p = ptr { free(p) } }

        if ret != 0 {
            return String(cString: strerror(ret))
        }

        var status: Int32 = 0
        waitpid(pid, &status, 0)
        return ""
    }

    func sendTouch(type: Int32, x: Float, y: Float, fingerId: Int32 = 0) -> String {
        execute(args: ["th", "\(type)", "\(x)", "\(y)", "\(fingerId)"])
    }

    func tap(x: Float, y: Float) -> String {
        sendTouch(type: 0, x: x, y: y, fingerId: 0)
    }

    func swipe(x1: Float, y1: Float, x2: Float, y2: Float, duration: TimeInterval) -> String {
        let steps = max(10, Int(duration * 60))
        let interval = duration / Double(steps)
        var lastErr = ""

        lastErr = sendTouch(type: 0, x: x1, y: y1)
        for i in 1...steps {
            if !lastErr.isEmpty { break }
            usleep(UInt32(interval * 1_000_000))
            let t = Double(i) / Double(steps)
            let cx = x1 + (x2 - x1) * Float(t)
            let cy = y1 + (y2 - y1) * Float(t)
            lastErr = sendTouch(type: 1, x: cx, y: cy)
        }
        usleep(40000)
        if lastErr.isEmpty {
            lastErr = sendTouch(type: 2, x: x2, y: y2)
        }
        return lastErr
    }
}

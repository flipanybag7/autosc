import Foundation

final class HelperExecutor {
    static let shared = HelperExecutor()
    private var helperPath: String?

    private init() {}

    var isReady: Bool {
        if let p = helperPath { return FileManager.default.fileExists(atPath: p) }
        return false
    }

    func prepare() -> String {
        if isReady { return "" }
        guard !helperBinaryB64.isEmpty else { return "CI-only: helper not embedded" }
        guard let data = Data(base64Encoded: helperBinaryB64) else { return "base64 decode failed" }

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("th_\(UUID().uuidString.prefix(8))")
        do {
            try data.write(to: tmp)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
            helperPath = tmp.path
            return ""
        } catch {
            return "write failed: \(error.localizedDescription)"
        }
    }

    func sendTouch(type: Int32, x: Float, y: Float, fingerId: Int32 = 0) -> String {
        if !isReady { return "helper not ready" }
        guard let path = helperPath else { return "no path" }

        let args = [path, "\(type)", "\(x)", "\(y)", "\(fingerId)"]
        let argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        defer { for p in argv { if let p = p { free(p) } } }

        var pid: pid_t = 0
        let ret = posix_spawn(&pid, path, nil, nil, argv, nil)
        guard ret == 0 else { return "spawn err \(ret)" }

        var status: Int32 = 0
        waitpid(pid, &status, 0)
        return ""
    }

    func tap(x: Float, y: Float) -> String {
        var e = sendTouch(type: 0, x: x, y: y)
        if e.isEmpty { usleep(60000); e = sendTouch(type: 2, x: x, y: y) }
        return e
    }

    func swipe(x1: Float, y1: Float, x2: Float, y2: Float, duration: TimeInterval) -> String {
        let steps = max(10, Int(duration * 60))
        let interval = duration / Double(steps)
        var err = sendTouch(type: 0, x: x1, y: y1)
        if !err.isEmpty { return err }
        for i in 1...steps {
            usleep(UInt32(interval * 1_000_000))
            let t = Double(i) / Double(steps)
            let cx = x1 + (x2 - x1) * Float(t)
            let cy = y1 + (y2 - y1) * Float(t)
            err = sendTouch(type: 1, x: cx, y: cy)
            if !err.isEmpty { return err }
        }
        usleep(40000)
        return sendTouch(type: 2, x: x2, y: y2)
    }
}

import Foundation
import UIKit

final class LuaEngine: ObservableObject {
    static let shared = LuaEngine()

    @Published var isRunning = false
    @Published var output: String = ""
    @Published var currentLine: Int = 0

    private init() {}

    func execute(_ script: String) {
        isRunning = true
        output = ""

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            self?.runScript(script)
            DispatchQueue.main.async {
                self?.isRunning = false
            }
        }
    }

    func stop() {
        isRunning = false
    }

    private func runScript(_ raw: String) {
        var vars: [String: Double] = [:]
        let injector = TouchInjector.shared
        let lines = raw.components(separatedBy: .newlines)

        var i = 0
        while i < lines.count {
            guard isRunning else { return }

            let t = lines[i].trimmingCharacters(in: .whitespaces)
            defer { i += 1 }

            if t.isEmpty || t.hasPrefix("--") { continue }

            DispatchQueue.main.async { [weak self] in
                self?.currentLine = i + 1
            }

            if t.hasPrefix("local ") {
                if let (name, val) = parseAssignment(t, vars: vars) {
                    vars[name] = val
                }
                continue
            }

            if t.hasPrefix("usleep("), let num = extractParenNum(t) {
                Thread.sleep(forTimeInterval: num / 1_000_000)
                continue
            }

            if t.hasPrefix("sleep("), let num = extractParenNum(t) {
                Thread.sleep(forTimeInterval: num)
                continue
            }

            if let (fn, args) = parseCall(t) {
                let vals = args.map { evalExpr($0, vars: vars) }

                switch fn {
                case "touchDown":
                    if vals.count >= 3 {
                        injector.touchDown(at: CGPoint(x: vals[1], y: vals[2]), fingerId: Int32(vals[0]))
                    }
                case "touchMove":
                    if vals.count >= 3 {
                        injector.touchMove(to: CGPoint(x: vals[1], y: vals[2]), fingerId: Int32(vals[0]))
                    }
                case "touchUp":
                    if vals.count >= 3 {
                        injector.touchUp(at: CGPoint(x: vals[1], y: vals[2]), fingerId: Int32(vals[0]))
                    }
                case "tap":
                    if vals.count >= 2 {
                        injector.tap(at: CGPoint(x: vals[0], y: vals[1]))
                    }
                case "swipe":
                    if vals.count >= 4 {
                        let dur = vals.count >= 5 ? vals[4] : 0.3
                        injector.swipe(from: CGPoint(x: vals[0], y: vals[1]),
                                       to: CGPoint(x: vals[2], y: vals[3]),
                                       duration: dur)
                    }
                case "longPress":
                    if vals.count >= 3 {
                        injector.longPress(at: CGPoint(x: vals[0], y: vals[1]), duration: vals[2])
                    }
                default:
                    break
                }
                continue
            }

            if t.hasPrefix("for ") {
                let (iterVar, from, to, body, skip) = parseFor(t, remainingLines: Array(lines[(i + 1)...]))
                if let iv = iterVar {
                    for j in Int(from)...Int(to) {
                        guard isRunning else { return }
                        vars[iv] = Double(j)
                        runScript(body.joined(separator: "\n"))
                    }
                    i += skip
                }
                continue
            }

            if t.hasPrefix("function ") || t.hasPrefix("if ") {
                continue
            }
        }
    }

    private func parseAssignment(_ line: String, vars: [String: Double]) -> (String, Double)? {
        let cleaned = line.replacingOccurrences(of: "local ", with: "")
            .trimmingCharacters(in: .whitespaces)
        let parts = cleaned.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        let name = parts[0]
        let val = evalExpr(parts[1], vars: vars)
        return (name, val)
    }

    private func evalExpr(_ expr: String, vars: [String: Double]) -> Double {
        let e = expr.trimmingCharacters(in: .whitespaces)

        if e.hasPrefix("math.random("), e.hasSuffix(")") {
            let inner = String(e.dropFirst("math.random(".count).dropLast(1))
            let nums = inner.components(separatedBy: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if nums.count == 2 {
                return Double(Int.random(in: Int(nums[0])...Int(nums[1])))
            }
        }

        if e.contains("*") {
            let parts = e.components(separatedBy: "*")
            return parts.reduce(1.0) { $0 * (Double($1.trimmingCharacters(in: .whitespaces)) ?? vars[$1.trimmingCharacters(in: .whitespaces)] ?? 1) }
        }
        if e.contains("/"), !e.hasPrefix("/") {
            let parts = e.components(separatedBy: "/")
            if parts.count == 2 {
                let a = Double(parts[0].trimmingCharacters(in: .whitespaces)) ?? vars[parts[0].trimmingCharacters(in: .whitespaces)] ?? 0
                let b = Double(parts[1].trimmingCharacters(in: .whitespaces)) ?? vars[parts[1].trimmingCharacters(in: .whitespaces)] ?? 1
                return b != 0 ? a / b : 0
            }
        }
        if e.contains("+") {
            let parts = e.components(separatedBy: "+")
            return parts.reduce(0.0) { $0 + (Double($1.trimmingCharacters(in: .whitespaces)) ?? vars[$1.trimmingCharacters(in: .whitespaces)] ?? 0) }
        }
        if e.contains("-"), !e.hasPrefix("-") {
            let parts = e.components(separatedBy: "-")
            if parts.count == 2 {
                let a = Double(parts[0].trimmingCharacters(in: .whitespaces)) ?? vars[parts[0].trimmingCharacters(in: .whitespaces)] ?? 0
                let b = Double(parts[1].trimmingCharacters(in: .whitespaces)) ?? vars[parts[1].trimmingCharacters(in: .whitespaces)] ?? 0
                return a - b
            }
        }

        if let v = vars[e] { return v }
        return Double(e) ?? 0
    }

    private func extractParenNum(_ s: String) -> Double? {
        guard let start = s.firstIndex(of: "("), let end = s.lastIndex(of: ")"), start < end else { return nil }
        let inside = String(s[s.index(after: start)..<end]).trimmingCharacters(in: .whitespaces)
        return Double(inside)
    }

    private func parseCall(_ line: String) -> (String, [String])? {
        guard let paren = line.firstIndex(of: "("), line.hasSuffix(")") else { return nil }
        let fn = String(line[..<paren]).trimmingCharacters(in: .whitespaces)
        let argsRaw = String(line[line.index(after: paren)..<line.index(before: line.endIndex)])
        let args = argsRaw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return (fn, args)
    }

    private func parseFor(_ line: String, remainingLines: [String]) -> (String?, Double, Double, [String], Int) {
        let parts = line.components(separatedBy: "=")
        guard parts.count == 2 else { return (nil, 0, 0, [], 0) }

        let left = parts[0].replacingOccurrences(of: "for ", with: "").trimmingCharacters(in: .whitespaces)
        let iterVar = left

        let right = parts[1].trimmingCharacters(in: .whitespaces)
        let rangeParts = right.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard rangeParts.count >= 2 else { return (nil, 0, 0, [], 0) }

        let from = Double(rangeParts[0]) ?? 0
        var toStr = rangeParts[1]
        if toStr.hasSuffix(",") { toStr = String(toStr.dropLast()) }
        if toStr.hasSuffix(")") { toStr = String(toStr.dropLast()) }
        let to = Double(toStr) ?? 0

        var body: [String] = []
        var skip = 0
        var depth = 1
        for (idx, rline) in remainingLines.enumerated() {
            let rt = rline.trimmingCharacters(in: .whitespaces)
            if rt == "end" || rt.hasPrefix("end ") || rt.hasPrefix("end)") {
                depth -= 1
                if depth == 0 {
                    skip = idx + 1
                    break
                }
            }
            if rt.hasPrefix("for ") { depth += 1 }
            body.append(rline)
        }
        return (iterVar, from, to, body, skip)
    }

    static func generateTemplate() -> String {
        return """
        -- AutoSc Lua Script
        -- Available functions:
        --   touchDown(fingerId, x, y)
        --   touchMove(fingerId, x, y)
        --   touchUp(fingerId, x, y)
        --   tap(x, y)
        --   swipe(x1, y1, x2, y2, duration)
        --   longPress(x, y, duration)
        --   usleep(microseconds)
        --   sleep(seconds)
        --   math.random(a, b)

        local w = \(Int(UIScreen.main.bounds.width))
        local h = \(Int(UIScreen.main.bounds.height))

        function main()
            -- Example: tap center of screen
            tap(w / 2, h / 2)
            usleep(500000)

            -- Example: swipe up
            swipe(w / 2, h * 0.7, w / 2, h * 0.3, 0.4)
            usleep(300000)

            -- Example: loop 5 times
            -- for i = 1, 5 do
            --     tap(w / 2, h / 2)
            --     usleep(1000000)
            -- end
        end

        main()
        """
    }
}

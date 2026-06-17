import Foundation
import UIKit

struct MacroFile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var actions: [TouchAction]
    var createdAt: Date
    var modifiedAt: Date
    var repeatCount: Int
    var screenSize: CGSize

    var duration: TimeInterval {
        actions.reduce(0) { $0 + $1.delay + $1.duration }
    }

    init(
        id: UUID = UUID(),
        name: String,
        actions: [TouchAction] = [],
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        repeatCount: Int = 1,
        screenSize: CGSize = CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
    ) {
        self.id = id
        self.name = name
        self.actions = actions
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.repeatCount = repeatCount
        self.screenSize = screenSize
    }
}

enum MacroStore {
    static let macrosDirectory: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AutoScMacros")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }()

    static func save(_ macro: MacroFile) throws {
        var m = macro
        m.modifiedAt = Date()
        let data = try JSONEncoder().encode(m)
        let url = macrosDirectory.appendingPathComponent("\(m.id.uuidString).json")
        try data.write(to: url)
    }

    static func loadAll() -> [MacroFile] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: macrosDirectory, includingPropertiesForKeys: nil) else { return [] }
        return contents
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> MacroFile? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(MacroFile.self, from: data)
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    static func delete(_ macro: MacroFile) throws {
        let url = macrosDirectory.appendingPathComponent("\(macro.id.uuidString).json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func saveLua(_ name: String, _ script: String) throws {
        let dir = macrosDirectory.appendingPathComponent("lua_scripts")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let url = dir.appendingPathComponent("\(name).lua")
        try script.write(to: url, atomically: true, encoding: .utf8)
    }

    static func loadLua(named name: String) -> String? {
        let url = macrosDirectory.appendingPathComponent("lua_scripts/\(name).lua")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func listLuaScripts() -> [URL] {
        let dir = macrosDirectory.appendingPathComponent("lua_scripts")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }
        return contents.filter { $0.pathExtension == "lua" }
    }

    static func deleteLua(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

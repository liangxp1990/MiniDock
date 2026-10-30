import Foundation

/// 一键把分类文件夹固定到 Dock（best-effort）并写入弹窗个性化参数：
/// displayas（文件夹/堆叠）、showas（扇形/网格/列表）、arrangement（排序）、
/// preferreditemsize（网格图标大小）。校验失败时抛错，由 UI 回退为手动拖入引导。
enum DockPinner {
    enum PinError: LocalizedError {
        case notPinnedAfterRestart
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .notPinnedAfterRestart:
                return "Dock 重启后未检测到该分类，请改用手动拖入。"
            case .commandFailed(let command):
                return "命令执行失败：\(command)"
            }
        }
    }

    private static let dockPlist = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences/com.apple.dock.plist")

    static func pin(_ folder: URL, prefs: DockTilePrefs) async throws {
        try await Task.detached(priority: .userInitiated) {
            try pinSynchronously(folder, prefs: prefs)
        }.value
    }

    static func isPinned(_ folder: URL) -> Bool {
        guard let output = try? runCommand("/usr/bin/defaults", ["read", "com.apple.dock", "persistent-others"]) else {
            return false
        }
        return output.contains(folder.absoluteString) || output.contains(folder.path)
    }

    /// 修改已固定瓦片的弹窗参数；返回 false 表示该文件夹尚未固定到 Dock
    static func updateTilePrefs(for folder: URL, prefs: DockTilePrefs) async throws -> Bool {
        try await Task.detached(priority: .userInitiated) {
            try updateTilePrefsSynchronously(folder: folder, prefs: prefs)
        }.value
    }

    // MARK: - 实现

    private static func pinSynchronously(_ folder: URL, prefs: DockTilePrefs) throws {
        let entry = """
        <dict><key>tile-data</key><dict><key>displayas</key><integer>\(prefs.displayasValue)</integer><key>showas</key><integer>\(prefs.showasValue)</integer><key>arrangement</key><integer>\(prefs.arrangementValue)</integer><key>preferreditemsize</key><integer>\(prefs.preferreditemsizeValue)</integer><key>file-data</key><dict><key>_CFURLString</key><string>\(folder.absoluteString)</string><key>_CFURLStringType</key><integer>15</integer></dict></dict><key>tile-type</key><string>directory-tile</string></dict>
        """
        do {
            _ = try runCommand("/usr/bin/defaults", [
                "write", "com.apple.dock", "persistent-others", "-array-add", entry,
            ])
            forcePrefsOnLastTile(prefs)
            _ = try runCommand("/usr/bin/killall", ["Dock"])
        } catch {
            throw PinError.commandFailed("defaults/killall")
        }

        Thread.sleep(forTimeInterval: 3)
        if !isPinned(folder) {
            throw PinError.notPinnedAfterRestart
        }
    }

    private static func updateTilePrefsSynchronously(folder: URL, prefs: DockTilePrefs) throws -> Bool {
        guard let index = indexOfTile(for: folder) else {
            return false
        }
        let prefix = ":persistent-others:\(index):tile-data"
        for (key, value) in [
            ("displayas", prefs.displayasValue),
            ("showas", prefs.showasValue),
            ("arrangement", prefs.arrangementValue),
            ("preferreditemsize", prefs.preferreditemsizeValue),
        ] {
            _ = try? runCommand("/usr/libexec/PlistBuddy", [
                "-c", "Set \(prefix):\(key) \(value)", dockPlist.path,
            ])
        }
        _ = try runCommand("/usr/bin/killall", ["Dock"])
        return true
    }

    /// 在 persistent-others 中按文件夹 URL 匹配瓦片下标（不匹配则 nil）
    private static func indexOfTile(for folder: URL) -> Int? {
        guard let data = try? Data(contentsOf: dockPlist),
              let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let others = dict["persistent-others"] as? [[String: Any]]
        else { return nil }

        let target = normalizedPath(folder.absoluteString)
        for (index, tile) in others.enumerated() {
            guard let tileData = tile["tile-data"] as? [String: Any],
                  let fileData = tileData["file-data"] as? [String: Any],
                  let urlString = fileData["_CFURLString"] as? String
            else { continue }
            if normalizedPath(urlString) == target {
                return index
            }
        }
        return nil
    }

    /// 归一化 file URL 为路径：去百分号编码、去末尾斜杠
    private static func normalizedPath(_ urlString: String) -> String {
        var path = urlString.removingPercentEncoding ?? urlString
        if path.hasPrefix("file://") {
            path = String(path.dropFirst("file://".count))
        }
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    /// 保险起见，把刚追加瓦片的四个参数用 PlistBuddy 再确认一遍
    private static func forcePrefsOnLastTile(_ prefs: DockTilePrefs) {
        guard let data = try? Data(contentsOf: dockPlist),
              let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let others = dict["persistent-others"] as? [[String: Any]],
              let lastIndex = others.indices.last
        else { return }
        let prefix = ":persistent-others:\(lastIndex):tile-data"
        for (key, value) in [
            ("displayas", prefs.displayasValue),
            ("showas", prefs.showasValue),
            ("arrangement", prefs.arrangementValue),
            ("preferreditemsize", prefs.preferreditemsizeValue),
        ] {
            _ = try? runCommand("/usr/libexec/PlistBuddy", [
                "-c", "Set \(prefix):\(key) \(value)", dockPlist.path,
            ])
        }
    }

    @discardableResult
    private static func runCommand(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

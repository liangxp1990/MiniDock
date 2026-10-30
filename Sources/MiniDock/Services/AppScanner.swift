import Foundation

struct FoundApp: Identifiable, Hashable {
    /// bundle identifier（缺失时退化为路径），用于去重
    let id: String
    let name: String
    let path: String
}

/// 扫描系统中的已安装应用（纯文件系统操作，可在后台线程执行）
enum AppScanner {
    static var defaultSearchRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
        ]
    }

    static func scan(
        searchRoots: [URL] = defaultSearchRoots,
        excludingPaths: Set<String> = []
    ) -> [FoundApp] {
        let fm = FileManager.default
        var seen = Set<String>()
        var results: [FoundApp] = []

        for root in searchRoots where fm.fileExists(atPath: root.path) {
            guard let entries = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries where entry.hasDirectoryPath && entry.pathExtension == "app" {
                guard !excludingPaths.contains(entry.path) else { continue }
                if let app = appInfo(forBundleAt: entry, seen: &seen) {
                    results.append(app)
                }
            }
            // 二级目录中的 App（部分软件安装在子目录里）
            for entry in entries where entry.hasDirectoryPath && entry.pathExtension != "app" {
                guard let nested = try? fm.contentsOfDirectory(
                    at: entry,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for url in nested where url.hasDirectoryPath && url.pathExtension == "app" {
                    guard !excludingPaths.contains(url.path) else { continue }
                    if let app = appInfo(forBundleAt: url, seen: &seen) {
                        results.append(app)
                    }
                }
            }
        }
        return results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 读取单个 .app 的名称与 bundle id（不存在 Info.plist 时退化为文件名）
    static func appInfo(forBundleAt url: URL, seen: inout Set<String>) -> FoundApp? {
        let infoPlist = url.appendingPathComponent("Contents/Info.plist")
        var bundleID: String?
        var displayName: String?
        if let dict = NSDictionary(contentsOfFile: infoPlist.path) as? [String: Any] {
            bundleID = dict["CFBundleIdentifier"] as? String
            displayName = (dict["CFBundleDisplayName"] as? String) ?? (dict["CFBundleName"] as? String)
        }
        let name = (displayName?.isEmpty == false)
            ? displayName!
            : url.deletingPathExtension().lastPathComponent
        let id = (bundleID?.isEmpty == false) ? bundleID! : url.path
        guard seen.insert(id).inserted else { return nil }
        return FoundApp(id: id, name: name, path: url.path)
    }
}

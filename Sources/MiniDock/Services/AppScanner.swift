import Foundation

struct FoundApp: Identifiable, Hashable {
    /// bundle identifier（缺失时退化为路径），用于去重
    let id: String
    let name: String
    let path: String
}

/// 扫描系统中的已安装应用（可见范围对齐「应用中心」/ Launchpad）
enum AppScanner {
    static var defaultSearchRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
        ]
    }

    // MARK: - 全量扫描（应用中心数据源 ∪ 目录扫描兜底）

    /// 应用中心展示的应用来自 Spotlight（LaunchServices 登记来源）索引，
    /// 其中包含 /Library 等非标准安装位置（如 aTrust 实体）与 Cryptex 中的系统应用。
    /// Spotlight 被禁用或索引滞后的机器由目录扫描兜底补齐。
    static func scanAll(excludingPaths: Set<String> = []) async -> [FoundApp] {
        var seen = Set<String>()
        var results: [FoundApp] = []
        // 排序让 /Applications 入口先参与去重，与应用中心展示的路径保持一致
        let indexedPaths = await spotlightAppPaths().sorted()
        for path in indexedPaths where isEligiblePath(path) {
            guard !excludingPaths.contains(path) else { continue }
            if let app = appInfo(forBundleAt: URL(fileURLWithPath: path), seen: &seen) {
                results.append(app)
            }
        }
        let fallbackApps = await Task.detached(priority: .userInitiated) {
            scan(excludingPaths: excludingPaths)
        }.value
        for app in fallbackApps where seen.insert(app.id).inserted {
            results.append(app)
        }
        return results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 查询 Spotlight 索引中登记的全部应用 bundle。
    /// 走 mdfind 子进程直连 mds 服务，比进程内 NSMetadataQuery 更稳定（后者在部分运行上下文中拿不到结果）。
    static func spotlightAppPaths() async -> [String] {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            process.arguments = ["-0", "kMDItemContentType == 'com.apple.application-bundle'"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
            } catch {
                return []
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            return String(data: data, encoding: .utf8)?
                .split(separator: "\0", omittingEmptySubsequences: true)
                .map(String.init) ?? []
        }.value
    }

    /// 对齐应用中心的可见性：剔除系统内部组件、开发产物与失效挂载卷
    static func isEligiblePath(_ path: String) -> Bool {
        if path.contains(".app/Contents/") { return false }       // 内嵌 bundle（Finder/AirDrop 等）
        if path.contains("/Library/Developer/") { return false }  // Xcode 模拟器、构建产物
        let excludedPrefixes = [
            "/private/var/",
            "/Volumes/",
            "/System/Library/PrivateFrameworks/",
            "/System/Library/Frameworks/",
            "/Library/Caches/",
        ]
        if excludedPrefixes.contains(where: path.hasPrefix) { return false }
        // CoreServices 顶级多为系统组件（Installer、Finder、各 Agent），
        // 仅其 Applications 子目录内的应用（归档实用工具等）会在应用中心展示
        if path.hasPrefix("/System/Library/CoreServices/") {
            return path.hasPrefix("/System/Library/CoreServices/Applications/")
        }
        return true
    }

    // MARK: - 目录扫描（兜底）

    /// 逐目录扫描固定位置（纯文件系统操作，可在后台线程执行）
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
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries where entry.pathExtension == "app" && isReachableDirectory(entry, fm: fm) {
                guard !excludingPaths.contains(entry.path) else { continue }
                if let app = appInfo(forBundleAt: entry, seen: &seen) {
                    results.append(app)
                }
            }
            // 二级目录中的 App（部分软件安装在子目录里）
            for entry in entries where entry.pathExtension != "app" && isReachableDirectory(entry, fm: fm) {
                guard let nested = try? fm.contentsOfDirectory(
                    at: entry,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for url in nested where url.pathExtension == "app" && isReachableDirectory(url, fm: fm) {
                    guard !excludingPaths.contains(url.path) else { continue }
                    if let app = appInfo(forBundleAt: url, seen: &seen) {
                        results.append(app)
                    }
                }
            }
        }
        return results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 判断是否为可达的目录（跟随符号链接）。
    /// `hasDirectoryPath`/`isDirectoryKey` 对符号链接使用 lstat 语义、不跟随，
    /// 而企业软件（如 aTrust 实体在 /Library/sangfor/SDP）和 Safari（实体在系统 Cryptex 中）
    /// 常在 /Applications 放符号链接，会被误过滤；`fileExists(isDirectory:)` 跟随链接，可正确识别。
    static func isReachableDirectory(_ url: URL, fm: FileManager) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// 读取单个 .app 的名称与 bundle id（不存在 Info.plist 时退化为文件名）
    static func appInfo(forBundleAt url: URL, seen: inout Set<String>) -> FoundApp? {
        let infoPlist = url.appendingPathComponent("Contents/Info.plist")
        var bundleID: String?
        var displayName: String?
        var hiddenAgent = false
        if let dict = NSDictionary(contentsOfFile: infoPlist.path) as? [String: Any] {
            bundleID = dict["CFBundleIdentifier"] as? String
            displayName = (dict["CFBundleDisplayName"] as? String) ?? (dict["CFBundleName"] as? String)
            // 应用中心不展示的纯后台 agent
            let uiElement = (dict["LSUIElement"] as? Bool) == true || (dict["LSUIElement"] as? String) == "1"
            let backgroundOnly = (dict["LSBackgroundOnly"] as? Bool) == true || (dict["LSBackgroundOnly"] as? String) == "1"
            hiddenAgent = uiElement || backgroundOnly
        }
        guard !hiddenAgent else { return nil }
        let name = (displayName?.isEmpty == false)
            ? displayName!
            : url.deletingPathExtension().lastPathComponent
        let id = (bundleID?.isEmpty == false) ? bundleID! : url.path
        guard seen.insert(id).inserted else { return nil }
        return FoundApp(id: id, name: name, path: url.path)
    }
}

import AppKit
import Foundation

/// 将配置同步到磁盘：
///   ~/Applications/MiniDock/<分类名>/ 内为指向各 .app 的符号链接，文件夹带样式化封面图标。
/// 分类文件夹只包含由本引擎创建的符号链接，删除分类时也只删除这些链接，绝不触碰真实 App。
@MainActor
final class DockSyncEngine {
    struct State: Codable {
        /// categoryID.uuidString -> 当前磁盘文件夹名（用于检测重命名）
        var folderByCategoryID: [String: String] = [:]
        /// folderName -> 封面签名（成员、顺序或样式变化时重新生成图标）
        var iconSignatures: [String: String] = [:]
        /// folderName -> 链接顺序签名（「按我的排序」模式据此重建符号链接）
        var linkSignatures: [String: String] = [:]
    }

    enum SyncError: LocalizedError {
        case rootCreateFailed(URL)

        var errorDescription: String? {
            switch self {
            case .rootCreateFailed(let url):
                return "无法创建分类根目录：\(url.path)"
            }
        }
    }

    static let stateFileName = ".minidock-state.json"

    let root: URL
    private var state: State
    /// 非致命异常说明（如空配置保护触发时），供上层提示
    private(set) var skippedCleanupHint: String?
    private let stateURL: URL
    /// 图标写入器；测试中可注入计数实现
    var iconWriter: (NSImage, URL) -> Void = { image, folder in
        // 不用 NSWorkspace.setIcon：其 IconServices XPC 在应用进程内存在间歇
        // guard fault（全天 21 次崩溃实测），手工写资源分叉完全确定
        try? FolderIconWriter.apply(image, toFolder: folder.path)
    }
    /// 自定义封面图片加载器（按 CoverStyle.customImageName）；测试可注入
    var coverImageProvider: (String) -> NSImage? = { name in
        let url = ConfigStore.coversDirectory.appendingPathComponent(name)
        return NSImage(contentsOf: url)
    }

    init(root: URL? = nil) {
        let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/MiniDock", isDirectory: true)
        self.root = root ?? defaultRoot
        self.stateURL = self.root.appendingPathComponent(Self.stateFileName)
        if let data = try? Data(contentsOf: stateURL),
           let decoded = try? JSONDecoder().decode(State.self, from: data) {
            self.state = decoded
        } else {
            self.state = State()
        }
    }

    // MARK: - 对外查询

    func folderURL(for category: Category) -> URL {
        root.appendingPathComponent(category.folderName, isDirectory: true)
    }

    func revealRootInFinder() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }

    /// 目标 App 已被移动/删除的应用 id 集合（UI 标红提示修复）
    func brokenAppIDs(in config: AppConfig) -> Set<UUID> {
        let fm = FileManager.default
        var broken = Set<UUID>()
        for category in config.categories {
            for app in category.apps where !fm.fileExists(atPath: app.bundlePath) {
                broken.insert(app.id)
            }
        }
        return broken
    }

    // MARK: - 链接规划（纯函数，供引擎与测试共用）

    /// 由分类成员推导符号链接名与目标（重名自动加序号；名称用 App 显示名）
    nonisolated static func plannedLinks(for apps: [AppRef]) -> [(name: String, target: URL)] {
        var usedNames = Set<String>()
        var result: [(String, URL)] = []
        for app in apps {
            let base = FileSystemNameSanitizer.sanitize(app.displayName)
            var name = base
            var suffix = 2
            while usedNames.contains(name) {
                name = "\(base) \(suffix)"
                suffix += 1
            }
            usedNames.insert(name)
            result.append((name, app.bundleURL))
        }
        return result
    }

    // MARK: - 同步

    func apply(_ config: AppConfig) throws {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            throw SyncError.rootCreateFailed(root)
        }

        let defaultStyle = config.effectiveDefaultCoverStyle
        let defaultPrefs = config.effectiveDefaultTilePrefs

        var desiredFolderNames = Set<String>()
        for category in config.categories {
            desiredFolderNames.insert(category.folderName)
            let orderedRebuild = category.effectiveTilePrefs(defaults: defaultPrefs).sortBy == .mine
            try syncCategory(category, defaultStyle: defaultStyle, orderedRebuild: orderedRebuild)
        }

        // 清理已删除分类的文件夹：只删除本引擎记录在映射中的文件夹，
        // 绝不触碰目录中其他内容（内部只含符号链接，真实 App 不受影响）。
        // 保险丝：配置为空但映射里有文件夹时，视为配置加载异常（而非用户删光），
        // 跳过清理，避免一次读盘失败连锁清空所有分类。
        if config.categories.isEmpty && !state.folderByCategoryID.isEmpty {
            skippedCleanupHint = "配置为空但存在历史分类，已跳过清理以免误删"
        } else {
            for (key, name) in state.folderByCategoryID where !desiredFolderNames.contains(name) {
                try? fm.removeItem(at: root.appendingPathComponent(name, isDirectory: true))
                state.folderByCategoryID.removeValue(forKey: key)
            }
        }
        state.iconSignatures = state.iconSignatures.filter { desiredFolderNames.contains($0.key) }
        state.linkSignatures = state.linkSignatures.filter { desiredFolderNames.contains($0.key) }

        saveState()
    }

    private func syncCategory(
        _ category: Category,
        defaultStyle: CoverStyle,
        orderedRebuild: Bool
    ) throws {
        let fm = FileManager.default
        let folder = folderURL(for: category)
        let key = category.id.uuidString

        // 重命名检测：旧映射存在且磁盘上有旧文件夹、新文件夹尚不存在 -> 重命名
        if let oldName = state.folderByCategoryID[key],
           oldName != category.folderName {
            let oldURL = root.appendingPathComponent(oldName, isDirectory: true)
            let oldExists = fm.fileExists(atPath: oldURL.path)
            let newExists = fm.fileExists(atPath: folder.path)
            if oldExists && !newExists {
                try fm.moveItem(at: oldURL, to: folder)
                if let signature = state.iconSignatures.removeValue(forKey: oldName) {
                    state.iconSignatures[category.folderName] = signature
                }
                if let signature = state.linkSignatures.removeValue(forKey: oldName) {
                    state.linkSignatures[category.folderName] = signature
                }
            } else if newExists && oldExists {
                // 新旧同名冲突（理论上 AppState 已保证唯一），保守删除旧文件夹
                try? fm.removeItem(at: oldURL)
            }
        }

        if !fm.fileExists(atPath: folder.path) {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        state.folderByCategoryID[key] = category.folderName

        let desired = Self.plannedLinks(for: category.apps)
        let desiredNames = Set(desired.map(\.name))

        if orderedRebuild {
            // 「按我的排序」：以添加日期排序生效，成员或顺序变化时按配置顺序整组重建
            let orderSignature = category.linkOrderSignature
            if state.linkSignatures[category.folderName] != orderSignature {
                // 整组重建（不保留既有链接）：保证创建日期顺序 = 配置顺序
                removeAllManagedLinks(in: folder, keeping: [])
                for item in desired {
                    let linkURL = folder.appendingPathComponent(item.name)
                    try? fm.removeItem(at: linkURL)
                    try fm.createSymbolicLink(at: linkURL, withDestinationURL: item.target)
                }
                state.linkSignatures[category.folderName] = orderSignature
            }
        } else {
            // 常规差量同步
            if let children = try? fm.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: []
            ) {
                for child in children {
                    let name = child.lastPathComponent
                    // 保留自定义图标文件（"Icon\r"）与系统隐藏文件，避免误删分类封面
                    if name.hasPrefix(".") || name == "Icon\r" { continue }
                    if !desiredNames.contains(name) {
                        try? fm.removeItem(at: child)
                    }
                }
            }
            for item in desired {
                let linkURL = folder.appendingPathComponent(item.name)
                if fm.fileExists(atPath: linkURL.path) {
                    continue  // 名称一致即视为已同步
                }
                try? fm.removeItem(at: linkURL)
                try fm.createSymbolicLink(at: linkURL, withDestinationURL: item.target)
            }
        }

        // 封面签名变化时按样式重新生成
        let signature = category.coverSignature(defaultStyle: defaultStyle)
        if state.iconSignatures[category.folderName] != signature {
            let style = category.effectiveCoverStyle(defaults: defaultStyle)
            let customImage = style.customImageName.flatMap { coverImageProvider($0) }
            let image = MosaicIconGenerator.generate(
                forAppPaths: category.apps.map(\.bundlePath),
                style: style,
                customImage: customImage
            )
            iconWriter(image, folder)
            state.iconSignatures[category.folderName] = signature
        }
    }

    /// 删除文件夹内由本引擎管理的符号链接（保留图标文件与隐藏文件）
    private func removeAllManagedLinks(in folder: URL, keeping: Set<String>) {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: []
        ) else { return }
        for child in children {
            let name = child.lastPathComponent
            if name.hasPrefix(".") || name == "Icon\r" { continue }
            if keeping.contains(name) { continue }
            try? fm.removeItem(at: child)
        }
    }

    private func saveState() {
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }
}

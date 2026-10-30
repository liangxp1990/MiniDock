import AppKit
import Observation
import SwiftUI

/// 管理器界面个性化设置（UserDefaults 持久化）
@MainActor
@Observable
final class AppSettings {
    enum IconSize: String, CaseIterable, Codable {
        case small, medium, large

        var points: CGFloat {
            switch self {
            case .small: return 48
            case .medium: return 54
            case .large: return 64
            }
        }

        var label: String {
            switch self {
            case .small: return "小"
            case .medium: return "中"
            case .large: return "大"
            }
        }
    }

    var accentHex: String {
        didSet { UserDefaults.standard.set(accentHex, forKey: "MiniDock.accentHex") }
    }

    var iconSize: IconSize {
        didSet {
            if let data = try? JSONEncoder().encode(iconSize) {
                UserDefaults.standard.set(data, forKey: "MiniDock.iconSize")
            }
        }
    }

    var showSidebarBadge: Bool {
        didSet { UserDefaults.standard.set(showSidebarBadge, forKey: "MiniDock.showSidebarBadge") }
    }

    init() {
        let defaults = UserDefaults.standard
        self.accentHex = defaults.string(forKey: "MiniDock.accentHex") ?? "system"
        if let data = defaults.data(forKey: "MiniDock.iconSize"),
           let size = try? JSONDecoder().decode(IconSize.self, from: data) {
            self.iconSize = size
        } else {
            self.iconSize = .medium
        }
        if defaults.object(forKey: "MiniDock.showSidebarBadge") != nil {
            self.showSidebarBadge = defaults.bool(forKey: "MiniDock.showSidebarBadge")
        } else {
            self.showSidebarBadge = true
        }
    }
}

@MainActor
@Observable
final class AppState {
    enum PinOutcome: Identifiable {
        case success(categoryName: String)
        case failure(categoryName: String, reason: String)

        var id: String {
            switch self {
            case .success(let name): return "ok-\(name)"
            case .failure(let name, let reason): return "fail-\(name)-\(reason)"
            }
        }
    }

    enum TileApplyOutcome: Identifiable {
        case applied(categoryName: String)
        case savedForNextPin(categoryName: String)
        case failure(categoryName: String, reason: String)

        var id: String {
            switch self {
            case .applied(let n): return "applied-\(n)"
            case .savedForNextPin(let n): return "saved-\(n)"
            case .failure(let n, let r): return "fail-\(n)-\(r)"
            }
        }
    }

    private(set) var config: AppConfig
    var selectedCategoryID: UUID?
    private(set) var lastSyncError: String?
    private(set) var brokenAppIDs: Set<UUID> = []
    private(set) var pinningCategoryID: UUID?
    private(set) var pinOutcome: PinOutcome?
    private(set) var tileApplyOutcome: TileApplyOutcome?
    private(set) var applyingTileCategoryID: UUID?

    let settings = AppSettings()
    let syncEngine: DockSyncEngine
    private let configURL: URL
    private var mosaicCache: [String: NSImage] = [:]

    init(
        configURL: URL = ConfigStore.defaultURL,
        syncEngine: DockSyncEngine = DockSyncEngine()
    ) {
        self.configURL = configURL
        self.syncEngine = syncEngine
        self.config = ConfigStore.load(from: configURL)
        self.selectedCategoryID = config.categories.first?.id
        persistAndSync()
        refreshHealth()
    }

    var selectedCategory: Category? {
        config.categories.first { $0.id == selectedCategoryID }
    }

    var effectiveDefaultCoverStyle: CoverStyle { config.effectiveDefaultCoverStyle }
    var effectiveDefaultTilePrefs: DockTilePrefs { config.effectiveDefaultTilePrefs }

    // MARK: - 分类操作

    func addCategory(named name: String) {
        let folder = uniqueFolderName(
            FileSystemNameSanitizer.sanitize(name),
            excluding: config.categories.map(\.folderName)
        )
        let category = Category(name: name, folderName: folder)
        mutate { $0.categories.append(category) }
        selectedCategoryID = category.id
    }

    func renameCategory(_ id: UUID, to newName: String) {
        let others = config.categories.filter { $0.id != id }.map(\.folderName)
        let folder = uniqueFolderName(FileSystemNameSanitizer.sanitize(newName), excluding: others)
        mutate { config in
            guard let index = config.categories.firstIndex(where: { $0.id == id }) else { return }
            config.categories[index].name = newName
            config.categories[index].folderName = folder
        }
    }

    func deleteCategory(_ id: UUID) {
        mutate { $0.categories.removeAll { $0.id == id } }
        if selectedCategoryID == id {
            selectedCategoryID = config.categories.first?.id
        }
    }

    // MARK: - 应用操作

    func addApps(_ refs: [AppRef], to categoryID: UUID) {
        guard !refs.isEmpty else { return }
        mutate { config in
            guard let index = config.categories.firstIndex(where: { $0.id == categoryID }) else { return }
            let existing = Set(config.categories[index].apps.map(\.bundlePath))
            config.categories[index].apps.append(contentsOf: refs.filter { !existing.contains($0.bundlePath) })
        }
    }

    func removeApp(_ appID: UUID, from categoryID: UUID) {
        mutate { config in
            guard let index = config.categories.firstIndex(where: { $0.id == categoryID }) else { return }
            config.categories[index].apps.removeAll { $0.id == appID }
        }
    }

    /// 把拖动的应用移动到目标应用之前（targetID 为 nil 表示移到末尾）
    func moveApp(withID appID: UUID, before targetID: UUID?, in categoryID: UUID) {
        mutate { config in
            guard let index = config.categories.firstIndex(where: { $0.id == categoryID }),
                  let from = config.categories[index].apps.firstIndex(where: { $0.id == appID })
            else { return }
            let app = config.categories[index].apps.remove(at: from)
            if let targetID,
               let to = config.categories[index].apps.firstIndex(where: { $0.id == targetID }) {
                config.categories[index].apps.insert(app, at: to)
            } else {
                config.categories[index].apps.append(app)
            }
        }
    }

    /// 修复失效应用：指向新选择的 .app
    func repairApp(_ appID: UUID, in categoryID: UUID, newBundleURL: URL) {
        var seen = Set<String>()
        let name = AppScanner.appInfo(forBundleAt: newBundleURL, seen: &seen)?.name
            ?? newBundleURL.deletingPathExtension().lastPathComponent
        mutate { config in
            guard let index = config.categories.firstIndex(where: { $0.id == categoryID }),
                  let appIndex = config.categories[index].apps.firstIndex(where: { $0.id == appID })
            else { return }
            config.categories[index].apps[appIndex].bundlePath = newBundleURL.path
            config.categories[index].apps[appIndex].displayName = name
        }
    }

    // MARK: - 个性化

    /// nil = 恢复使用全局默认样式
    func setCoverStyle(_ style: CoverStyle?, for categoryID: UUID) {
        mutate { config in
            guard let index = config.categories.firstIndex(where: { $0.id == categoryID }) else { return }
            config.categories[index].coverStyle = style
        }
    }

    /// 保存自定义封面图片到 covers 目录，返回文件名
    @discardableResult
    func saveCoverImage(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return nil }
        let name = UUID().uuidString + ".png"
        do {
            try FileManager.default.createDirectory(at: ConfigStore.coversDirectory, withIntermediateDirectories: true)
            try png.write(to: ConfigStore.coversDirectory.appendingPathComponent(name))
            return name
        } catch {
            return nil
        }
    }

    func setTilePrefs(_ prefs: DockTilePrefs?, for categoryID: UUID) {
        mutate { config in
            guard let index = config.categories.firstIndex(where: { $0.id == categoryID }) else { return }
            config.categories[index].tilePrefs = prefs
        }
    }

    /// 把弹窗参数应用到 Dock（分类已固定时立即生效，否则保存待固定时使用）
    func applyTilePrefs(for category: Category) async {
        applyingTileCategoryID = category.id
        defer { applyingTileCategoryID = nil }
        let prefs = category.effectiveTilePrefs(defaults: effectiveDefaultTilePrefs)
        do {
            let applied = try await DockPinner.updateTilePrefs(
                for: syncEngine.folderURL(for: category), prefs: prefs
            )
            tileApplyOutcome = applied
                ? .applied(categoryName: category.name)
                : .savedForNextPin(categoryName: category.name)
        } catch {
            tileApplyOutcome = .failure(categoryName: category.name, reason: error.localizedDescription)
        }
    }

    func clearTileApplyOutcome() {
        tileApplyOutcome = nil
    }

    // MARK: - Dock

    func pinCategory(_ category: Category) async {
        pinningCategoryID = category.id
        defer { pinningCategoryID = nil }
        let prefs = category.effectiveTilePrefs(defaults: effectiveDefaultTilePrefs)
        do {
            try await DockPinner.pin(syncEngine.folderURL(for: category), prefs: prefs)
            pinOutcome = .success(categoryName: category.name)
        } catch {
            pinOutcome = .failure(categoryName: category.name, reason: error.localizedDescription)
        }
    }

    func clearPinOutcome() {
        pinOutcome = nil
    }

    func revealRoot() {
        syncEngine.revealRootInFinder()
    }

    // MARK: - 侧栏缩略图（样式感知）

    func mosaic(for category: Category) -> NSImage {
        let style = category.effectiveCoverStyle(defaults: effectiveDefaultCoverStyle)
        let key = category.id.uuidString + "|" + category.coverSignature(defaultStyle: effectiveDefaultCoverStyle)
        if let cached = mosaicCache[key] {
            return cached
        }
        let customImage = style.customImageName.flatMap { syncEngine.coverImageProvider($0) }
        let image = MosaicIconGenerator.generate(
            forAppPaths: category.apps.map(\.bundlePath),
            style: style,
            customImage: customImage,
            canvasSize: 128
        )
        mosaicCache[key] = image
        return image
    }

    // MARK: - 私有

    private func mutate(_ change: (inout AppConfig) -> Void) {
        change(&config)
        mosaicCache.removeAll()
        persistAndSync()
        refreshHealth()
    }

    private func persistAndSync() {
        lastSyncError = nil
        do {
            try ConfigStore.save(config, to: configURL)
        } catch {
            lastSyncError = "配置保存失败：\(error.localizedDescription)"
        }
        do {
            try syncEngine.apply(config)
        } catch {
            lastSyncError = "同步 Dock 文件夹失败：\(error.localizedDescription)"
        }
    }

    private func refreshHealth() {
        brokenAppIDs = syncEngine.brokenAppIDs(in: config)
    }

    private func uniqueFolderName(_ base: String, excluding existing: [String]) -> String {
        let taken = Set(existing)
        guard taken.contains(base) else { return base }
        var index = 2
        while taken.contains("\(base) \(index)") {
            index += 1
        }
        return "\(base) \(index)"
    }
}

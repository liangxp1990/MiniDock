import Foundation

// MARK: - 封面样式

/// 封面底板类型
enum CoverPlate: Codable, Hashable {
    case glassLight
    case glassDark
    case solid(colorHex: String)
    case gradient(topHex: String, bottomHex: String)
    case image
}

/// 分类封面样式（马赛克图标生成参数）
struct CoverStyle: Codable, Hashable {
    enum Layout: String, Codable, CaseIterable {
        case auto, two, three
    }

    enum CodingKeys: String, CodingKey {
        case plate, layout
        case cornerRadiusPercent, gapPercent, iconScalePercent
        case showCountBadge, customImageName, overlayMiniIcons
    }

    var plate: CoverPlate = .glassLight
    var layout: Layout = .auto
    /// 底板圆角（占画布宽百分比）
    var cornerRadiusPercent: Double = 21.9
    /// 图标间距（占底板宽百分比）
    var gapPercent: Double = 5
    /// 图标占格（占格子宽百分比）
    var iconScalePercent: Double = 76
    /// 右下角显示应用数量角标
    var showCountBadge: Bool = false
    /// 自定义封面图片文件名（存于 ~/Library/Application Support/MiniDock/covers/）
    var customImageName: String?
    /// 图片封面时叠加迷你应用图标
    var overlayMiniIcons: Bool = true

    init() {}

    init(
        plate: CoverPlate,
        layout: Layout = .auto,
        cornerRadiusPercent: Double = 21.9,
        gapPercent: Double = 5,
        iconScalePercent: Double = 76,
        showCountBadge: Bool = false,
        customImageName: String? = nil,
        overlayMiniIcons: Bool = true
    ) {
        self.plate = plate
        self.layout = layout
        self.cornerRadiusPercent = cornerRadiusPercent
        self.gapPercent = gapPercent
        self.iconScalePercent = iconScalePercent
        self.showCountBadge = showCountBadge
        self.customImageName = customImageName
        self.overlayMiniIcons = overlayMiniIcons
    }

    /// 跨启动稳定的编码（用于签名比较；hashValue 每次启动会变，不可用）。
    /// 显式 .sortedKeys：键序不随工具链/运行时而变，否则签名漂移会导致图标被反复重生成
    var stableEncoding: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)).map { $0.base64EncodedString() } ?? ""
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plate = try c.decodeIfPresent(CoverPlate.self, forKey: .plate) ?? .glassLight
        layout = try c.decodeIfPresent(Layout.self, forKey: .layout) ?? .auto
        cornerRadiusPercent = try c.decodeIfPresent(Double.self, forKey: .cornerRadiusPercent) ?? 21.9
        gapPercent = try c.decodeIfPresent(Double.self, forKey: .gapPercent) ?? 5
        iconScalePercent = try c.decodeIfPresent(Double.self, forKey: .iconScalePercent) ?? 76
        showCountBadge = try c.decodeIfPresent(Bool.self, forKey: .showCountBadge) ?? false
        customImageName = try c.decodeIfPresent(String.self, forKey: .customImageName)
        overlayMiniIcons = try c.decodeIfPresent(Bool.self, forKey: .overlayMiniIcons) ?? true
    }
}

// MARK: - Dock 弹窗参数（原生瓦片偏好）

struct DockTilePrefs: Codable, Hashable {
    enum PopupStyle: String, Codable, CaseIterable {
        case auto, fan, grid, list
    }

    enum Sort: String, Codable, CaseIterable {
        case name, mine, kind
    }

    enum CodingKeys: String, CodingKey {
        case displayAsFolder, popupStyle, sortBy, gridSize
    }

    /// true=显示为文件夹（渲染多应用封面）；false=堆叠（仅第一个应用图标）
    var displayAsFolder: Bool = true
    var popupStyle: PopupStyle = .grid
    var sortBy: Sort = .name
    /// 网格弹窗的图标点数（48–128）；nil = 跟随系统默认（实测 -1 → 最紧凑）
    var gridSize: Int?

    init() {}

    init(displayAsFolder: Bool = true, popupStyle: PopupStyle = .grid, sortBy: Sort = .name, gridSize: Int? = nil) {
        self.displayAsFolder = displayAsFolder
        self.popupStyle = popupStyle
        self.sortBy = sortBy
        self.gridSize = gridSize
    }

    /// 写入 Dock plist 的 preferreditemsize：nil → -1（系统默认）
    var preferreditemsizeValue: Int { gridSize ?? -1 }

    // MARK: Dock plist 键值映射（阶段二实证：键值经 Dock 重启存活）
    var displayasValue: Int { displayAsFolder ? 1 : 0 }
    var showasValue: Int {
        switch popupStyle {
        case .auto: return 0
        case .fan: return 1
        case .grid: return 2
        case .list: return 3
        }
    }
    /// 「按我的排序」= 按添加日期 + 引擎按配置顺序重建符号链接
    var arrangementValue: Int {
        switch sortBy {
        case .name: return 1
        case .mine: return 2
        case .kind: return 5
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayAsFolder = try c.decodeIfPresent(Bool.self, forKey: .displayAsFolder) ?? true
        popupStyle = try c.decodeIfPresent(PopupStyle.self, forKey: .popupStyle) ?? .grid
        sortBy = try c.decodeIfPresent(Sort.self, forKey: .sortBy) ?? .name
        // 旧版把默认 64 直接写入配置，无法与“用户主动选 64”区分；
        // 64 实测比系统默认（-1）明显更大，统一迁移为 nil（跟随系统）
        let stored = try c.decodeIfPresent(Int.self, forKey: .gridSize)
        gridSize = (stored == 64) ? nil : stored
    }
}

// MARK: - 数据模型

/// 分类中的一个应用（指向真实 .app 包的引用）
struct AppRef: Codable, Hashable, Identifiable {
    var id: UUID
    var bundlePath: String
    var displayName: String

    init(id: UUID = UUID(), bundlePath: String, displayName: String) {
        self.id = id
        self.bundlePath = bundlePath
        self.displayName = displayName
    }

    var bundleURL: URL { URL(fileURLWithPath: bundlePath) }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        bundlePath = try container.decode(String.self, forKey: .bundlePath)
        displayName = try container.decode(String.self, forKey: .displayName)
    }
}

/// 一个分类 = 磁盘上一个文件夹 + 内部若干 App 符号链接
struct Category: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    /// 磁盘上实际使用的文件夹名（由名称清洗而来，用于检测重命名）
    var folderName: String
    var apps: [AppRef]
    /// nil = 使用全局默认封面样式
    var coverStyle: CoverStyle?
    /// nil = 使用全局默认 Dock 弹窗参数
    var tilePrefs: DockTilePrefs?

    init(
        id: UUID = UUID(),
        name: String,
        folderName: String = "",
        apps: [AppRef] = [],
        coverStyle: CoverStyle? = nil,
        tilePrefs: DockTilePrefs? = nil
    ) {
        self.id = id
        self.name = name
        self.folderName = folderName.isEmpty ? FileSystemNameSanitizer.sanitize(name) : folderName
        self.apps = apps
        self.coverStyle = coverStyle
        self.tilePrefs = tilePrefs
    }

    func effectiveCoverStyle(defaults: CoverStyle) -> CoverStyle {
        coverStyle ?? defaults
    }

    func effectiveTilePrefs(defaults: DockTilePrefs) -> DockTilePrefs {
        tilePrefs ?? defaults
    }

    /// 图标封面签名：成员顺序 + 生效样式（变化时重新生成封面）
    /// 生成器几何版本：绘制算法变化时递增，使已生成的封面自动重建
    static let mosaicGeneratorVersion = "gen3"

    func coverSignature(defaultStyle: CoverStyle) -> String {
        apps.map(\.bundlePath).joined(separator: "\n")
            + "‖"
            + effectiveCoverStyle(defaults: defaultStyle).stableEncoding
            + "‖" + Self.mosaicGeneratorVersion
    }

    /// 链接顺序签名（「按我的排序」模式下据此重建符号链接）
    var linkOrderSignature: String {
        apps.map(\.bundlePath).joined(separator: "\n")
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        let storedFolder = try container.decodeIfPresent(String.self, forKey: .folderName)
        folderName = (storedFolder?.isEmpty == false) ? storedFolder! : FileSystemNameSanitizer.sanitize(name)
        apps = try container.decodeIfPresent([AppRef].self, forKey: .apps) ?? []
        coverStyle = try container.decodeIfPresent(CoverStyle.self, forKey: .coverStyle)
        tilePrefs = try container.decodeIfPresent(DockTilePrefs.self, forKey: .tilePrefs)
    }
}

struct AppConfig: Codable, Equatable {
    var version: Int = 1
    var categories: [Category] = []
    /// 全局默认封面样式（nil = 内置默认）
    var defaultCoverStyle: CoverStyle?
    /// 全局默认 Dock 弹窗参数（nil = 内置默认）
    var defaultTilePrefs: DockTilePrefs?

    init(version: Int = 1, categories: [Category] = [],
         defaultCoverStyle: CoverStyle? = nil, defaultTilePrefs: DockTilePrefs? = nil) {
        self.version = version
        self.categories = categories
        self.defaultCoverStyle = defaultCoverStyle
        self.defaultTilePrefs = defaultTilePrefs
    }

    var effectiveDefaultCoverStyle: CoverStyle { defaultCoverStyle ?? CoverStyle() }
    var effectiveDefaultTilePrefs: DockTilePrefs { defaultTilePrefs ?? DockTilePrefs() }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        categories = try container.decodeIfPresent([Category].self, forKey: .categories) ?? []
        defaultCoverStyle = try container.decodeIfPresent(CoverStyle.self, forKey: .defaultCoverStyle)
        defaultTilePrefs = try container.decodeIfPresent(DockTilePrefs.self, forKey: .defaultTilePrefs)
    }
}

/// 清洗不合法的文件/文件夹名
enum FileSystemNameSanitizer {
    static func sanitize(_ name: String) -> String {
        var cleaned = name
        for forbidden in ["/", ":", "\0"] {
            cleaned = cleaned.replacingOccurrences(of: forbidden, with: "-")
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") {
            cleaned.removeFirst()
        }
        return cleaned.isEmpty ? "未命名分类" : cleaned
    }
}

/// 配置持久化：~/Library/Application Support/MiniDock/config.json
enum ConfigStore {
    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("MiniDock/config.json")
    }

    /// 自定义封面图片目录
    static var coversDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("MiniDock/covers", isDirectory: true)
    }

    static func load(from url: URL) -> AppConfig {
        guard let data = try? Data(contentsOf: url) else { return AppConfig() }
        let decoder = JSONDecoder()
        return (try? decoder.decode(AppConfig.self, from: data)) ?? AppConfig()
    }

    static func save(_ config: AppConfig, to url: URL) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }
}

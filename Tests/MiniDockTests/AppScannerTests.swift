import XCTest
@testable import MiniDock

final class AppScannerTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("minidock-scan-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func makeBundle(_ folder: String, plist: [String: Any]? = nil, nested: Bool = false) throws -> URL {
        let url = nested
            ? root.appendingPathComponent("Suite/\(folder)", isDirectory: true)
            : root.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true
        )
        if let plist {
            let infoURL = url.appendingPathComponent("Contents/Info.plist")
            NSDictionary(dictionary: plist).write(to: infoURL, atomically: true)
        }
        return url
    }

    func testScanFindsAppsAndDedupes() throws {
        _ = try makeBundle("Fake.app", plist: [
            "CFBundleIdentifier": "com.fake.one",
            "CFBundleDisplayName": "假应用一",
        ])
        _ = try makeBundle("Second.app")
        // 嵌套目录中的重复 bundle id 应被去重
        _ = try makeBundle("FakeDup.app", plist: ["CFBundleIdentifier": "com.fake.one"], nested: true)

        let results = AppScanner.scan(searchRoots: [root])
        XCTAssertEqual(results.count, 2, "重复 bundle id 应被去重")
        let names = Set(results.map(\.name))
        XCTAssertTrue(names.contains("假应用一"), "优先使用 Info.plist 显示名")
        XCTAssertTrue(names.contains("Second"), "无 Info.plist 时回退到文件名")
    }

    func testScanFollowsSymlinkedApps() throws {
        // 模拟企业软件安装方式：实体在搜索根之外（如 /Library/sangfor/SDP），搜索根内只放符号链接
        let outsideRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("minidock-scan-out-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outsideRoot) }

        let realBundle = outsideRoot.appendingPathComponent("aTrust.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: realBundle.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true
        )
        NSDictionary(dictionary: ["CFBundleIdentifier": "com.electron.atrust", "CFBundleDisplayName": "aTrust"])
            .write(to: realBundle.appendingPathComponent("Contents/Info.plist"), atomically: true)

        let linkURL = root.appendingPathComponent("aTrust.app")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: realBundle)

        let results = AppScanner.scan(searchRoots: [root])
        guard let found = results.first(where: { $0.id == "com.electron.atrust" }) else {
            return XCTFail("符号链接指向的 .app 应能被扫描到")
        }
        XCTAssertEqual(found.name, "aTrust")
        // /var 与 /private/var 前缀在不同 API 下标准化结果不同，比较结尾路径即可
        XCTAssertTrue(found.path.hasSuffix("/aTrust.app"), "found.path=\(found.path)")
    }

    func testIsEligiblePathAlignsWithAppCenter() {
        // 正常应用位置放行
        XCTAssertTrue(AppScanner.isEligiblePath("/Applications/WeChat.app"))
        XCTAssertTrue(AppScanner.isEligiblePath("/Library/sangfor/SDP/aTrust.app"))
        XCTAssertTrue(AppScanner.isEligiblePath("/System/Library/CoreServices/Applications/Archive Utility.app"))
        // 系统内部组件 / 开发产物 / 内嵌 bundle / 挂载卷拒收
        XCTAssertFalse(AppScanner.isEligiblePath("/System/Library/CoreServices/Finder.app"))
        XCTAssertFalse(AppScanner.isEligiblePath("/System/Library/CoreServices/ScreenSaverEngine.app"))
        XCTAssertFalse(AppScanner.isEligiblePath("/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app"))
        XCTAssertFalse(AppScanner.isEligiblePath("/System/Library/PrivateFrameworks/PlatformSSO.framework/Support/PlatformSSOUIAgent.app"))
        XCTAssertFalse(AppScanner.isEligiblePath("/Users/dev/Library/Developer/CoreSimulator/Devices/x/data/Containers/Bundle/app/Fake.app"))
        XCTAssertFalse(AppScanner.isEligiblePath("/private/var/folders/ab/Trash.app"))
        XCTAssertFalse(AppScanner.isEligiblePath("/Volumes/InstallESD/i4Tools.app"))
    }

    func testAppInfoSkipsHiddenAgents() throws {
        _ = try makeBundle("Agent.app", plist: [
            "CFBundleIdentifier": "com.fake.agent",
            "LSUIElement": true,
        ])
        _ = try makeBundle("Normal.app", plist: ["CFBundleIdentifier": "com.fake.normal"])

        let results = AppScanner.scan(searchRoots: [root])
        XCTAssertFalse(results.contains { $0.id == "com.fake.agent" }, "LSUIElement 后台 agent 不应出现")
        XCTAssertTrue(results.contains { $0.id == "com.fake.normal" })
    }

    func testScanExcludesPaths() throws {
        let app = try makeBundle("Excluded.app")
        let results = AppScanner.scan(searchRoots: [root], excludingPaths: [app.path])
        XCTAssertFalse(results.contains { $0.path == app.path })
    }

    func testAppInfoForBundle() throws {
        let url = try makeBundle("Named.app", plist: ["CFBundleIdentifier": "com.named"])
        var seen = Set<String>()
        let info = AppScanner.appInfo(forBundleAt: url, seen: &seen)
        XCTAssertEqual(info?.name, "Named")
        XCTAssertEqual(info?.id, "com.named")
    }
}

@MainActor
final class MosaicIconTests: XCTestCase {
    func testGeneratedImageSize() {
        let styles: [CoverStyle] = [
            CoverStyle(),
            CoverStyle(plate: .glassDark),
            CoverStyle(plate: .solid(colorHex: "#0a84ff")),
            CoverStyle(plate: .gradient(topHex: "#8e5cf6", bottomHex: "#5a7bff"), showCountBadge: true),
            CoverStyle(plate: .image, overlayMiniIcons: true),
        ]
        for count in [0, 3, 9, 12] {
            let paths = (0..<count).map { "/Applications/Fake\($0).app" }
            for style in styles {
                let image = MosaicIconGenerator.generate(forAppPaths: paths, style: style)
                XCTAssertEqual(image.size.width, 1024, "count=\(count)")
                XCTAssertEqual(image.size.height, 1024)
                XCTAssertEqual(image.representations.first?.pixelsWide ?? 0, 1024)
            }
        }
    }

    func testColorHexParsing() {
        XCTAssertEqual(NSColor.fromHex("#0a84ff").redComponent, 10 / 255, accuracy: 0.002)
        XCTAssertEqual(NSColor.fromHex("34c759").greenComponent, 199 / 255, accuracy: 0.002)
        XCTAssertEqual(NSColor.fromHex("f00").redComponent, 1, accuracy: 0.002)
    }
}

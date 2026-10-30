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

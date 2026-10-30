import XCTest
@testable import MiniDock

final class ConfigTests: XCTestCase {
    func testSanitize() {
        XCTAssertEqual(FileSystemNameSanitizer.sanitize("效率/办公:工具"), "效率-办公-工具")
        XCTAssertEqual(FileSystemNameSanitizer.sanitize("  .隐藏 "), "隐藏")
        XCTAssertEqual(FileSystemNameSanitizer.sanitize("   "), "未命名分类")
        XCTAssertEqual(FileSystemNameSanitizer.sanitize("正常名字"), "正常名字")
    }

    func testCodableRoundTrip() throws {
        let config = AppConfig(categories: [
            Category(
                name: "效率办公",
                apps: [AppRef(bundlePath: "/Applications/WeChat.app", displayName: "微信")],
                coverStyle: CoverStyle(plate: .solid(colorHex: "#0a84ff"), showCountBadge: true),
                tilePrefs: DockTilePrefs(popupStyle: .fan, sortBy: .mine, gridSize: 96)
            ),
        ])
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    func testSaveAndLoad() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("config.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let config = AppConfig(categories: [Category(name: "开发工具")])
        try ConfigStore.save(config, to: url)
        XCTAssertEqual(ConfigStore.load(from: url), config)
    }

    func testCoverSignatureReflectsOrderAndStyle() {
        let a = AppRef(bundlePath: "/a.app", displayName: "A")
        let b = AppRef(bundlePath: "/b.app", displayName: "B")
        let defaults = CoverStyle()
        let first = Category(name: "x", apps: [a, b])
        let second = Category(name: "x", apps: [b, a])
        XCTAssertNotEqual(
            first.coverSignature(defaultStyle: defaults),
            second.coverSignature(defaultStyle: defaults)
        )
        // 样式变化也要触发封面重建
        let styled = Category(name: "x", apps: [a, b], coverStyle: CoverStyle(plate: .glassDark))
        XCTAssertNotEqual(
            first.coverSignature(defaultStyle: defaults),
            styled.coverSignature(defaultStyle: defaults)
        )
    }

    /// v1.0 旧配置（无 style / tilePrefs 字段）可正常解码
    func testDecodeLegacyConfigWithoutStyleFields() throws {
        let json = """
        {
          "categories": [
            {
              "apps": [{"bundlePath": "/Applications/A.app", "displayName": "A", "id": "11111111-1111-1111-1111-111111111111"}],
              "folderName": "旧分类",
              "id": "22222222-2222-2222-2222-222222222222",
              "name": "旧分类"
            }
          ],
          "version": 1
        }
        """
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.categories.count, 1)
        XCTAssertNil(config.categories[0].coverStyle)
        XCTAssertNil(config.categories[0].tilePrefs)
        XCTAssertEqual(config.categories[0].effectiveCoverStyle(defaults: CoverStyle()).plate, .glassLight)
        XCTAssertEqual(config.categories[0].effectiveTilePrefs(defaults: DockTilePrefs()).sortBy, .name)
    }

    func testCoverStyleStableEncoding() {
        let style = CoverStyle(plate: .gradient(topHex: "#8e5cf6", bottomHex: "#5a7bff"))
        // 跨「实例」稳定（hashValue 做不到这一点）
        XCTAssertEqual(style.stableEncoding, CoverStyle(
            plate: .gradient(topHex: "#8e5cf6", bottomHex: "#5a7bff")
        ).stableEncoding)
        XCTAssertNotEqual(style.stableEncoding, CoverStyle().stableEncoding)
    }

    func testTilePrefsPlistMapping() {
        XCTAssertEqual(DockTilePrefs(popupStyle: .auto).showasValue, 0)
        XCTAssertEqual(DockTilePrefs(popupStyle: .fan).showasValue, 1)
        XCTAssertEqual(DockTilePrefs(popupStyle: .grid).showasValue, 2)
        XCTAssertEqual(DockTilePrefs(popupStyle: .list).showasValue, 3)
        XCTAssertEqual(DockTilePrefs(sortBy: .name).arrangementValue, 1)
        XCTAssertEqual(DockTilePrefs(sortBy: .mine).arrangementValue, 2)
        XCTAssertEqual(DockTilePrefs(sortBy: .kind).arrangementValue, 5)
        XCTAssertEqual(DockTilePrefs(displayAsFolder: true).displayasValue, 1)
        XCTAssertEqual(DockTilePrefs(displayAsFolder: false).displayasValue, 0)
    }
}

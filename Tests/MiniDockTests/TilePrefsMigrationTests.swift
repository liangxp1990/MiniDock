import Foundation
import Testing
@testable import MiniDock

/// preferreditemsize 语义（2026-10 实测，macOS 26 内置屏 2x）：
/// -1 = 系统默认（约 65pt，最紧凑）；56 ≈ 95pt；更大值 → 一行仅 2 个的巨大弹窗。
/// 产品决策：默认跟随系统（nil → -1），旧配置里未自定义的 64 迁移为 nil。
@Suite struct TilePrefsMigrationTests {
    @Test func nilMapsToSystemDefault() {
        #expect(DockTilePrefs().preferreditemsizeValue == -1)
        #expect(DockTilePrefs(gridSize: nil).preferreditemsizeValue == -1)
    }

    @Test func explicitValuePassesThrough() {
        #expect(DockTilePrefs(gridSize: 56).preferreditemsizeValue == 56)
    }

    @Test func legacyDefault64MigratesToNil() throws {
        let json = #"{"displayAsFolder":true,"popupStyle":"grid","sortBy":"name","gridSize":64}"#
        let prefs = try JSONDecoder().decode(DockTilePrefs.self, from: Data(json.utf8))
        #expect(prefs.gridSize == nil)
        #expect(prefs.preferreditemsizeValue == -1)
    }

    @Test func legacyCustomizedValueSurvives() throws {
        let json = #"{"displayAsFolder":true,"popupStyle":"grid","sortBy":"name","gridSize":56}"#
        let prefs = try JSONDecoder().decode(DockTilePrefs.self, from: Data(json.utf8))
        #expect(prefs.gridSize == 56)
    }

    @Test func roundtripKeepsExplicitSize() throws {
        let prefs = DockTilePrefs(popupStyle: .list, sortBy: .kind, gridSize: 88)
        let data = try JSONEncoder().encode(prefs)
        let back = try JSONDecoder().decode(DockTilePrefs.self, from: data)
        #expect(back.gridSize == 88)
        #expect(back.popupStyle == .list)
    }

    @Test func roundtripKeepsSystemDefaultAsNil() throws {
        let prefs = DockTilePrefs()
        let data = try JSONEncoder().encode(prefs)
        let back = try JSONDecoder().decode(DockTilePrefs.self, from: data)
        #expect(back.gridSize == nil)
        #expect(back.preferreditemsizeValue == -1)
    }
}

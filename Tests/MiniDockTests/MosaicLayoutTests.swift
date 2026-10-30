import Testing
@testable import MiniDock

/// 马赛克布局推导：核心约束是任何布局下绘制数不得超过列数平方，
/// 否则多出的行会溢出底板（强制 2×2 + 5 应用的回归用例）。
@Suite struct MosaicLayoutTests {
    @Test func forcedTwoWithFiveAppsClampsToFour() {
        let layout = MosaicIconGenerator.layout(for: 5, style: CoverStyle(plate: .glassLight, layout: .two))
        #expect(layout.columns == 2)
        #expect(layout.rows == 2)
        #expect(layout.shown == 4)
    }

    @Test func forcedThreeClampsToNine() {
        let layout = MosaicIconGenerator.layout(for: 12, style: CoverStyle(plate: .glassLight, layout: .three))
        #expect(layout == MosaicLayout(columns: 3, rows: 3, shown: 9))
    }

    @Test func autoUsesTwoColumnsUpToFourApps() {
        #expect(MosaicIconGenerator.layout(for: 1, style: CoverStyle(plate: .glassLight)) == MosaicLayout(columns: 2, rows: 1, shown: 1))
        #expect(MosaicIconGenerator.layout(for: 4, style: CoverStyle(plate: .glassLight)) == MosaicLayout(columns: 2, rows: 2, shown: 4))
    }

    @Test func autoUsesThreeColumnsFromFiveApps() {
        #expect(MosaicIconGenerator.layout(for: 5, style: CoverStyle(plate: .glassLight)) == MosaicLayout(columns: 3, rows: 2, shown: 5))
        #expect(MosaicIconGenerator.layout(for: 6, style: CoverStyle(plate: .glassLight)) == MosaicLayout(columns: 3, rows: 2, shown: 6))
        #expect(MosaicIconGenerator.layout(for: 9, style: CoverStyle(plate: .glassLight)) == MosaicLayout(columns: 3, rows: 3, shown: 9))
        #expect(MosaicIconGenerator.layout(for: 15, style: CoverStyle(plate: .glassLight)) == MosaicLayout(columns: 3, rows: 3, shown: 9))
    }

    @Test func emptyCategoryYieldsZeroRows() {
        let layout = MosaicIconGenerator.layout(for: 0, style: CoverStyle(plate: .glassLight))
        #expect(layout == MosaicLayout(columns: 2, rows: 0, shown: 0))
    }
}

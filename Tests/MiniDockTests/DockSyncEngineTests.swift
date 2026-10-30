import XCTest
@testable import MiniDock

@MainActor
final class DockSyncEngineTests: XCTestCase {
    private var workspace: URL!
    private var engine: DockSyncEngine!
    private var iconWriteCount = 0

    override func setUp() async throws {
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("minidock-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        engine = DockSyncEngine(root: workspace)
        iconWriteCount = 0
        engine.iconWriter = { [weak self] _, _ in
            self?.iconWriteCount += 1
        }
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: workspace)
    }

    /// 在工作区里造一个假 .app（空目录即可，引擎只检查存在性）
    private func makeFakeApp(_ name: String) -> URL {
        let url = workspace.appendingPathComponent("apps/\(name).app", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fileExists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func testApplyCreatesFolderAndSymlinks() throws {
        let app = makeFakeApp("WeChat")
        let config = AppConfig(categories: [
            Category(name: "效率办公", apps: [
                AppRef(bundlePath: app.path, displayName: "微信"),
            ]),
        ])

        try engine.apply(config)

        let folder = workspace.appendingPathComponent("效率办公", isDirectory: true)
        XCTAssertTrue(fileExists(folder.path), "分类文件夹应被创建")

        let link = folder.appendingPathComponent("微信")
        XCTAssertTrue(fileExists(link.path), "符号链接应被创建")
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        XCTAssertEqual(destination, app.path, "符号链接应指向真实 App")
        XCTAssertEqual(iconWriteCount, 1, "首次应生成一次图标")
    }

    func testRenameMovesFolder() throws {
        let id = UUID()
        let app = makeFakeApp("Mail")
        var config = AppConfig(categories: [
            Category(id: id, name: "旧名字", apps: [AppRef(bundlePath: app.path, displayName: "邮件")]),
        ])
        try engine.apply(config)

        config.categories[0].name = "新名字"
        config.categories[0].folderName = "新名字"
        try engine.apply(config)

        XCTAssertTrue(fileExists(workspace.appendingPathComponent("新名字").path))
        XCTAssertFalse(fileExists(workspace.appendingPathComponent("旧名字").path))
        XCTAssertTrue(fileExists(
            workspace.appendingPathComponent("新名字/邮件").path
        ), "重命名后符号链接应保留")
    }

    func testDeleteCategoryRemovesFolderButKeepsApps() throws {
        let appA = makeFakeApp("A")
        let appB = makeFakeApp("B")
        var config = AppConfig(categories: [
            Category(name: "分类一", apps: [AppRef(bundlePath: appA.path, displayName: "A")]),
            Category(name: "分类二", apps: [AppRef(bundlePath: appB.path, displayName: "B")]),
        ])
        try engine.apply(config)

        config.categories.removeFirst()
        try engine.apply(config)

        XCTAssertFalse(fileExists(workspace.appendingPathComponent("分类一").path), "被删除分类的文件夹应移除")
        XCTAssertTrue(fileExists(workspace.appendingPathComponent("分类二").path))
        XCTAssertTrue(fileExists(appA.path), "真实 App 绝不能被删除")
    }

    func testMembershipChangeUpdatesSymlinksAndIcon() throws {
        let appA = makeFakeApp("A")
        let appB = makeFakeApp("B")
        var config = AppConfig(categories: [
            Category(name: "效率", apps: [AppRef(bundlePath: appA.path, displayName: "A")]),
        ])
        try engine.apply(config)
        XCTAssertEqual(iconWriteCount, 1)

        // 相同配置重复应用：不应重复生成图标
        try engine.apply(config)
        XCTAssertEqual(iconWriteCount, 1)

        // 成员变化：重建链接并重新生成图标
        config.categories[0].apps.append(AppRef(bundlePath: appB.path, displayName: "B"))
        try engine.apply(config)
        XCTAssertEqual(iconWriteCount, 2)
        XCTAssertTrue(fileExists(workspace.appendingPathComponent("效率/B").path))

        // 移除成员：链接同步移除，并再次生成图标
        config.categories[0].apps.removeAll { $0.displayName == "B" }
        try engine.apply(config)
        XCTAssertFalse(fileExists(workspace.appendingPathComponent("效率/B").path))
        XCTAssertEqual(iconWriteCount, 3)
    }

    func testCustomIconFileSurvivesResync() throws {
        let app = makeFakeApp("A")
        let config = AppConfig(categories: [
            Category(name: "效率", apps: [AppRef(bundlePath: app.path, displayName: "A")]),
        ])
        try engine.apply(config)

        // 模拟 NSWorkspace.setIcon 写入的自定义图标文件与系统隐藏文件
        let folder = workspace.appendingPathComponent("效率", isDirectory: true)
        let iconFile = folder.appendingPathComponent("Icon\r")
        try Data([0x00]).write(to: iconFile)
        try Data([0x00]).write(to: folder.appendingPathComponent(".DS_Store"))

        try engine.apply(config)  // 相同配置重复应用不应清除图标
        XCTAssertTrue(fileExists(iconFile.path), "自定义图标文件必须保留")
        XCTAssertTrue(fileExists(folder.appendingPathComponent(".DS_Store").path))

        // 成员变化后图标文件同样保留（图标会随后重新生成）
        let appB = makeFakeApp("B")
        var changed = config
        changed.categories[0].apps.append(AppRef(bundlePath: appB.path, displayName: "B"))
        try engine.apply(changed)
        XCTAssertTrue(fileExists(iconFile.path), "成员变化后图标文件也必须保留")
    }

    /// 保险丝：配置为空（如读盘失败）但映射中已有分类时，不得清理用户文件夹
    func testEmptyConfigDoesNotWipeTrackedFolders() throws {
        let app = makeFakeApp("Keynote")
        let config = AppConfig(categories: [
            Category(name: "演示", apps: [AppRef(bundlePath: app.path, displayName: "Keynote")]),
        ])
        try engine.apply(config)
        let folder = workspace.appendingPathComponent("演示", isDirectory: true)
        XCTAssertTrue(fileExists(folder.path))

        try engine.apply(AppConfig(categories: []))

        XCTAssertTrue(fileExists(folder.path), "空配置时映射中的文件夹必须保留")
        XCTAssertNotNil(engine.skippedCleanupHint, "应给出跳过清理的说明")
    }

    func testBrokenAppDetection() throws {
        let missing = workspace.appendingPathComponent("不存在.app", isDirectory: true)
        let config = AppConfig(categories: [
            Category(name: "x", apps: [AppRef(bundlePath: missing.path, displayName: "Ghost")]),
        ])
        try engine.apply(config)
        let broken = engine.brokenAppIDs(in: config)
        XCTAssertEqual(broken.count, 1)
    }
}

final class PlannedLinksTests: XCTestCase {
    func testPlannedLinksOrderAndDedupe() {
        let apps = [
            AppRef(bundlePath: "/Applications/B.app", displayName: "微信"),
            AppRef(bundlePath: "/Applications/A.app", displayName: "微信"),
            AppRef(bundlePath: "/Applications/C.app", displayName: "邮件"),
        ]
        let links = DockSyncEngine.plannedLinks(for: apps)
        XCTAssertEqual(links.map(\.name), ["微信", "微信 2", "邮件"])
        XCTAssertEqual(links.map(\.target.path), ["/Applications/B.app", "/Applications/A.app", "/Applications/C.app"])
    }
}

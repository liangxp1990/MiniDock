import SwiftUI

/// 跨层持有 openWindow 动作：AppDelegate 处理 Dock 重开时新建主窗口
@MainActor
final class MainWindowOpener {
    static let shared = MainWindowOpener()
    var openWindow: OpenWindowAction?
}

@main
struct MiniDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup("MiniDock", id: "main") {
            ContentView()
                .environment(appState)
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}

/// 关闭窗口后点击 Dock 图标重新打开主窗口。
/// SwiftUI 默认不处理 reopen：窗口关闭后 App 仍在运行，但点 Dock 图标
/// 不会重建窗口（实测 windows 列表已空，无窗可恢复），必须主动新建。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(
        _ application: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard !flag else { return true }
        // 先尝试恢复现存窗口（设置窗口等），否则新建主窗口
        let candidates = application.windows.filter(\.canBecomeMain)
        if let main = candidates.first(where: {
            !($0.identifier?.rawValue.lowercased().contains("settings") ?? false)
        }) ?? candidates.first {
            main.makeKeyAndOrderFront(nil)
        } else {
            Task { @MainActor in
                MainWindowOpener.shared.openWindow?(id: "main")
            }
        }
        return true
    }
}

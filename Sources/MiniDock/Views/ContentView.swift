import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @State private var showGuide = UserDefaults.standard.object(forKey: "MiniDock.hasSeenGuide") == nil
    @State private var showNewCategorySheet = false
    @State private var showAddAppsSheet = false
    @State private var showConfigSheet = false
    @State private var categoryToRename: Category?
    @State private var categoryToDelete: Category?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            // 标题/副标题/工具栏挂在 detail 列：侧栏得以通到窗口顶部，
            // 其右边框与标题栏下边框不再交叉错位
            detail
                .navigationTitle(appState.selectedCategory?.name ?? "MiniDock")
                .toolbar {
                    // 复刻访达式工具栏项：图标在 Liquid Glass 胶囊内 + 小字标签在底部
                    // （SwiftUI 无公开 API 让系统工具栏显示底部标签，见 docs/pitfalls.md）
                    ToolbarItem(placement: .primaryAction) {
                        pinButton
                    }
                    if #available(macOS 26.0, *) {
                        ToolbarSpacer(.fixed, placement: .primaryAction)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        if appState.selectedCategory != nil {
                            toolbarButton("设置", systemImage: "dock.rectangle",
                                          help: "封面与弹窗样式，实时预览") {
                                showConfigSheet = true
                            }
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        if appState.selectedCategory != nil {
                            toolbarButton("添加 App", systemImage: "plus") {
                                showAddAppsSheet = true
                            }
                        }
                    }
                }
        }
        .tint(accentColor)
        .onAppear { MainWindowOpener.shared.openWindow = openWindow }
        // 工具栏背景隐藏：其材质会在侧栏区留下 2pt 内缩边缘（红侧栏染色实验定位），
        // 造成侧栏顶部与 header 交汇处错位；隐藏后侧栏材质从窗口顶贯通到底
        .toolbarBackground(.hidden, for: .windowToolbar)
        .frame(minWidth: 760, minHeight: 520)
        .background(TitlebarSeparatorRemover())
        .sheet(isPresented: $showGuide) {
            GuideSheet()
        }
        .sheet(isPresented: $showNewCategorySheet) {
            CategoryNameSheet(mode: .create) { appState.addCategory(named: $0) }
        }
        .sheet(item: $categoryToRename) { category in
            CategoryNameSheet(mode: .rename(currentName: category.name)) {
                appState.renameCategory(category.id, to: $0)
            }
        }
        .sheet(isPresented: $showAddAppsSheet) {
            if let category = appState.selectedCategory {
                AppPickerSheet(category: category)
            }
        }
        .sheet(isPresented: $showConfigSheet) {
            if let category = appState.selectedCategory {
                CategoryConfigSheet(
                    category: category,
                    defaultStyle: appState.effectiveDefaultCoverStyle,
                    defaultPrefs: appState.effectiveDefaultTilePrefs
                )
            }
        }
        .confirmationDialog(
            "删除分类",
            isPresented: Binding(
                get: { categoryToDelete != nil },
                set: { if !$0 { categoryToDelete = nil } }
            ),
            presenting: categoryToDelete
        ) { category in
            Button("删除「\(category.name)」", role: .destructive) {
                appState.deleteCategory(category.id)
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("仅删除 Dock 分类文件夹及其中的链接，不会卸载或删除任何真实 App。")
        }
        .alert(
            "固定到 Dock",
            isPresented: Binding(
                get: { appState.pinOutcome != nil },
                set: { if !$0 { appState.clearPinOutcome() } }
            ),
            presenting: appState.pinOutcome
        ) { outcome in
            switch outcome {
            case .success:
                Button("好") {}
            case .failure:
                Button("打开文件夹手动拖入") { appState.revealRoot() }
                Button("好", role: .cancel) {}
            }
        } message: { outcome in
            switch outcome {
            case .success(let name):
                Text("「\(name)」已固定到 Dock，请点击 Dock 中的分类图标试用。\n若图标只显示单个应用，请右键该图标 → 显示为 → 文件夹。")
            case .failure(let name, let reason):
                Text("「\(name)」固定失败：\(reason)\n可打开 MiniDock 文件夹，把分类文件夹拖到 Dock 分隔线右侧（拖入后右键图标 → 显示为 → 文件夹）。")
            }
        }
    }

    /// "system" = 跟随系统强调色
    private var accentColor: Color? {
        appState.settings.accentHex == "system"
            ? nil
            : Color(nsColor: .fromHex(appState.settings.accentHex))
    }

    private var pinButton: some View {
        Button {
            if let category = appState.selectedCategory {
                Task { await appState.pinCategory(category) }
            }
        } label: {
            VStack(spacing: 3) {
                Group {
                    if appState.pinningCategoryID != nil {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "pin")
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .frame(width: 30, height: 30)
                .glassIconCapsule()
                Text("固定到 Dock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(appState.selectedCategory == nil || appState.pinningCategoryID != nil)
        .help(Text("把当前分类文件夹固定到 Dock 栏（会重启 Dock）"))
    }

    /// 访达式工具栏按钮：图标玻璃胶囊 + 底部小字标签
    private func toolbarButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        help: LocalizedStringKey? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 30)
                    .glassIconCapsule()
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help(help.map { Text($0) } ?? Text(title))
    }

    private var sidebar: some View {
        @Bindable var state = appState
        return List(selection: $state.selectedCategoryID) {
            ForEach(appState.config.categories) { category in
                HStack(spacing: 9) {
                    Image(nsImage: appState.mosaic(for: category))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 24, height: 24)
                    Text(category.name)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if appState.settings.showSidebarBadge {
                        Text("\(category.apps.count)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
                .padding(.vertical, 2)
                .tag(category.id)
                .contextMenu {
                    Button("重命名…") { categoryToRename = category }
                    Divider()
                    Button("删除…", role: .destructive) { categoryToDelete = category }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .safeAreaInset(edge: .bottom, alignment: .leading) {
            Button {
                showNewCategorySheet = true
            } label: {
                Label("新建分类", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let category = appState.selectedCategory {
            CategoryDetailView(category: category)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text(appState.config.categories.isEmpty ? "先新建一个分类" : "在左侧选择一个分类")
                    .foregroundStyle(.secondary)
                if appState.config.categories.isEmpty {
                    Button("新建分类") {
                        showNewCategorySheet = true
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}


/// 关闭系统标题栏下缘分隔线（macOS 26 该线会横穿侧栏顶部）。
/// 染色实验确诊：标题栏区域属于工具栏而非侧栏，系统无法在此画出
/// 正确的 T 型结构；干脆全部去线，靠材质差区分区域（同系统设置）。
struct TitlebarSeparatorRemover: NSViewRepresentable {
    final class RemoverView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.titlebarSeparatorStyle = .none
        }
    }
    func makeNSView(context: Context) -> NSView { RemoverView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

import AppKit
import SwiftUI

/// 封面与弹窗合并配置面板（v1.2 设计稿）：
/// 左侧实时预览舞台（Dock 瓦片 + 弹窗），右侧系统设置式表单。
struct CategoryConfigSheet: View {
    let category: Category
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var draftStyle: CoverStyle
    @State private var draftPrefs: DockTilePrefs
    @State private var pendingImage: NSImage?
    @State private var useGlobalDefault: Bool

    init(category: Category, defaultStyle: CoverStyle, defaultPrefs: DockTilePrefs) {
        self.category = category
        _draftStyle = State(initialValue: category.effectiveCoverStyle(defaults: defaultStyle))
        _draftPrefs = State(initialValue: category.effectiveTilePrefs(defaults: defaultPrefs))
        _useGlobalDefault = State(initialValue: category.coverStyle == nil)
    }

    private let palette = ["#8e5cf6", "#0a84ff", "#ff375f", "#ff9f0a", "#30d158", "#64648c"]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 14) {
                previewStage
                form
            }
            .padding(14)
            Divider()
            footer
        }
        .frame(width: 800, height: 640)
        .alert(
            "应用设置",
            isPresented: Binding(
                get: { appState.tileApplyOutcome != nil },
                set: { if !$0 { appState.clearTileApplyOutcome() } }
            ),
            presenting: appState.tileApplyOutcome
        ) { _ in
            Button("好") {
                appState.clearTileApplyOutcome()
                dismiss()
            }
        } message: { outcome in
            switch outcome {
            case .applied(let name):
                Text("「\(name)」的设置已应用，请点击 Dock 中的分类图标查看效果。")
            case .savedForNextPin(let name):
                Text("「\(name)」尚未固定到 Dock，设置已保存，下次固定时自动生效。")
            case .failure(let name, let reason):
                Text("「\(name)」应用失败：\(reason)")
            }
        }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("封面与弹窗 · \(category.name)").font(.headline)
                Text("瓦片外观与点击瓦片后的弹窗，一处配置、实时预览")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help(Text("关闭"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - 左侧：实时预览舞台

    private var previewStage: some View {
        VStack(spacing: 6) {
            PreviewStage(
                category: category,
                style: draftStyle,
                prefs: draftPrefs,
                customImage: pendingImage
            )
            .frame(width: 268, height: 470)
            Text("瓦片外观 = 封面设置 · 弹窗外观 = 弹窗设置")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 右侧：表单

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("封面样式 · 瓦片外观")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
                coverCard

                Text("Dock 弹窗 · 点击瓦片后")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
                    .padding(.top, 10)
                popupCard

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
        }
    }

    // MARK: 封面卡片

    private var coverCard: some View {
        SettingsCard {
            plateTiles
            colorRows
            layoutTiles
            parameterSlider("圆角", value: $draftStyle.cornerRadiusPercent, range: 8...30, format: "%.0f%%") {
                useGlobalDefault = false
            }
            parameterSlider("图标间距", value: $draftStyle.gapPercent, range: 2...12, format: "%.0f%%") {
                useGlobalDefault = false
            }
            parameterSlider("图标占格", value: $draftStyle.iconScalePercent, range: 55...92, format: "%.0f%%") {
                useGlobalDefault = false
            }
            if case .image = draftStyle.plate {
                imageRow
            }
            SettingsRow(title: "显示应用数量角标", subtitle: "右下角显示应用总数") {
                Toggle("", isOn: $draftStyle.showCountBadge)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: draftStyle.showCountBadge) { _, _ in useGlobalDefault = false }
            }
            .divided()
        }
    }

    private var plateTiles: some View {
        HStack(spacing: 12) {
            plateTile(.glassLight, title: "玻璃白") {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(0.8))
            }
            plateTile(.glassDark, title: "玻璃深") {
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .fromHex("#3c3c46")),
                                Color(nsColor: .fromHex("#26262e")),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }
            plateTile(.solid(colorHex: solidHex), title: "纯色") {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .fromHex(solidHex)))
            }
            plateTile(.gradient(topHex: gradientTop, bottomHex: gradientBottom), title: "渐变") {
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .fromHex(gradientTop)),
                                Color(nsColor: .fromHex(gradientBottom)),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }
            plateTile(.image, title: "图片") {
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .fromHex("#ffd0a8")),
                                Color(nsColor: .fromHex("#a8d8ff")),
                                Color(nsColor: .fromHex("#c9b6ff")),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func plateTile<Face: View>(
        _ plate: CoverPlate,
        title: LocalizedStringKey,
        @ViewBuilder face: () -> Face
    ) -> some View {
        Button {
            if case .image = plate, pendingImage == nil {
                draftStyle.plate = .image
                chooseImage()
            } else {
                draftStyle.plate = plate
            }
            useGlobalDefault = false
        } label: {
            VStack(spacing: 5) {
                face()
                    .frame(width: 50, height: 36)
                Text(title).font(.caption2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .glassTile(selected: isPlateSelected(plate))
        }
        .buttonStyle(.plain)
    }

    private var solidHex: String {
        if case .solid(let hex) = draftStyle.plate { return hex }
        return "#5e5ce6"
    }
    private var gradientTop: String {
        if case .gradient(let top, _) = draftStyle.plate { return top }
        return "#8e5cf6"
    }
    private var gradientBottom: String {
        if case .gradient(_, let bottom) = draftStyle.plate { return bottom }
        return "#5a7bff"
    }

    private func isPlateSelected(_ plate: CoverPlate) -> Bool {
        switch (draftStyle.plate, plate) {
        case (.glassLight, .glassLight), (.glassDark, .glassDark),
             (.solid, .solid), (.gradient, .gradient), (.image, .image):
            return true
        default:
            return false
        }
    }

    private var colorInfo: (show: Bool, isGradient: Bool) {
        switch draftStyle.plate {
        case .solid: return (true, false)
        case .gradient: return (true, true)
        default: return (false, false)
        }
    }

    @ViewBuilder
    private var colorRows: some View {
        let info = colorInfo
        if info.show {
            VStack(spacing: 8) {
                if info.isGradient {
                    dotRow(title: "渐变 · 顶部") { hex in
                        draftStyle.plate = .gradient(topHex: hex, bottomHex: gradientBottom)
                        useGlobalDefault = false
                    } selected: { hex in
                        if case .gradient(let top, _) = draftStyle.plate { return top == hex }
                        return false
                    }
                    dotRow(title: "渐变 · 底部") { hex in
                        draftStyle.plate = .gradient(topHex: gradientTop, bottomHex: hex)
                        useGlobalDefault = false
                    } selected: { hex in
                        if case .gradient(_, let bottom) = draftStyle.plate { return bottom == hex }
                        return false
                    }
                } else {
                    dotRow(title: "纯色 · 点选颜色") { hex in
                        draftStyle.plate = .solid(colorHex: hex)
                        useGlobalDefault = false
                    } selected: { hex in
                        if case .solid(let current) = draftStyle.plate { return current == hex }
                        return false
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .divided()
        }
    }

    private func dotRow(
        title: LocalizedStringKey,
        apply: @escaping (String) -> Void,
        selected: @escaping (String) -> Bool
    ) -> some View {
        HStack(spacing: 11) {
            ForEach(palette, id: \.self) { hex in
                AccentDot(hex: hex, isSelected: selected(hex)) {
                    apply(hex)
                }
            }
            Spacer()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var layoutTiles: some View {
        HStack(spacing: 12) {
            layoutTile(.auto, title: "自动", cols: 3, rows: 2, sparse: true)
            layoutTile(.two, title: "2×2", cols: 2, rows: 2)
            layoutTile(.three, title: "3×3", cols: 3, rows: 3)
            Spacer()
            Text("图标布局").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .divided()
    }

    private func layoutTile(_ layout: CoverStyle.Layout, title: LocalizedStringKey, cols: Int, rows: Int, sparse: Bool = false) -> some View {
        Button {
            draftStyle.layout = layout
            useGlobalDefault = false
        } label: {
            VStack(spacing: 5) {
                Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                    ForEach(0..<rows, id: \.self) { _ in
                        GridRow {
                            ForEach(0..<cols, id: \.self) { c in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(
                                        (sparse && (c == 1))
                                            ? Color.accentColor.opacity(0.45)
                                            : Color.accentColor.opacity(0.85)
                                    )
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                }
                .frame(width: cols == 2 ? 22 : 30, height: rows == 2 ? 22 : 30)
                Text(title).font(.caption2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .glassTile(selected: draftStyle.layout == layout)
        }
        .buttonStyle(.plain)
    }

    private func parameterSlider(
        _ title: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String,
        onChange: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.caption.monospacedDigit())
            }
            Slider(value: Binding(
                get: { value.wrappedValue },
                set: { newValue in
                    value.wrappedValue = newValue
                    onChange()
                }
            ), in: range)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .divided()
    }

    private var imageRow: some View {
        SettingsRow(title: pendingImage == nil ? "选择封面图片…" : "已载入预览", subtitle: "拖入图片自动圆角裁切") {
            HStack(spacing: 10) {
                Toggle("", isOn: $draftStyle.overlayMiniIcons)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help(Text("图片上叠加应用小图标"))
                Button("选择图片…") { chooseImage() }
                    .controlSize(.small)
            }
        }
        .divided()
    }

    // MARK: 弹窗卡片

    private var popupCard: some View {
        SettingsCard {
            SettingsRow(title: "瓦片显示为", subtitle: nil) {
                Picker("", selection: $draftPrefs.displayAsFolder) {
                    Text("文件夹").tag(true)
                    Text("堆叠").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .labelsHidden()
            }
            .divided()

            popStyleTiles

            sortRow(.name, title: "按名称", caption: "系统默认，字母 / 拼音排序").divided()
            sortRow(.mine, title: "按我的排序", caption: "使用管理器中的拖动顺序，应用后自动重建").divided()
            sortRow(.kind, title: "按种类", caption: "系统按文件类型分组排序").divided()

            SettingsRow(title: "跟随系统默认大小", subtitle: "由 macOS 决定弹窗尺寸，实测最紧凑（推荐）") {
                Toggle("", isOn: Binding(
                    get: { draftPrefs.gridSize == nil },
                    set: { draftPrefs.gridSize = $0 ? nil : 64 }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            .divided()

            if let size = draftPrefs.gridSize {
                VStack(spacing: 4) {
                    HStack {
                        Text("网格图标大小").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(size) px").font(.caption.monospacedDigit())
                    }
                    Slider(value: Binding(
                        get: { Double(size) },
                        set: { draftPrefs.gridSize = Int($0) }
                    ), in: 48...128, step: 8)
                    Text("数值越大弹窗越大，调小更紧凑")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
    }

    private var popStyleTiles: some View {
        HStack(spacing: 12) {
            popTile(.auto, title: "自动", style: .grid, sparse: true)
            popTile(.fan, title: "扇形", style: .fan)
            popTile(.grid, title: "网格", style: .grid)
            popTile(.list, title: "列表", style: .list)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .divided()
    }

    private func popTile(
        _ option: DockTilePrefs.PopupStyle,
        title: LocalizedStringKey,
        style: DockTilePrefs.PopupStyle,
        sparse: Bool = false
    ) -> some View {
        Button {
            draftPrefs.popupStyle = option
        } label: {
            VStack(spacing: 5) {
                PopStyleDemo(style: style, sparse: sparse)
                    .frame(width: 56, height: 38)
                Text(title).font(.caption2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .glassTile(selected: draftPrefs.popupStyle == option)
        }
        .buttonStyle(.plain)
    }

    private func sortRow(_ sort: DockTilePrefs.Sort, title: LocalizedStringKey, caption: LocalizedStringKey) -> some View {
        Button {
            draftPrefs.sortBy = sort
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Circle()
                    .strokeBorder(draftPrefs.sortBy == sort ? Color.accentColor : .secondary, lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                    .overlay {
                        if draftPrefs.sortBy == sort {
                            Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                        }
                    }
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout)
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassTile(selected: draftPrefs.sortBy == sort, cornerRadius: 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 底部

    private var footer: some View {
        HStack {
            Text("「应用」会更新封面图标并写入 Dock 参数（重启 Dock 约 1 秒）")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("恢复默认") {
                draftStyle = CoverStyle()
                draftPrefs = DockTilePrefs()
                pendingImage = nil
                useGlobalDefault = true
            }
            .buttonStyle(.plain)
            .glassCapsule()
            Button("取消") { dismiss() }
                .buttonStyle(.plain)
                .glassCapsule()
            Button {
                apply()
            } label: {
                if appState.applyingTileCategoryID == category.id {
                    ProgressView().controlSize(.small)
                } else {
                    Text("应用")
                }
            }
            .buttonStyle(.plain)
            .glassCapsule(prominent: true)
            .disabled(appState.applyingTileCategoryID != nil)
        }
        .padding(12)
    }

    // MARK: - 动作

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.message = "选择分类封面图片"
        if panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) {
            pendingImage = image
            draftStyle.plate = .image
            useGlobalDefault = false
        }
    }

    private func apply() {
        // 封面样式
        if useGlobalDefault {
            appState.setCoverStyle(nil, for: category.id)
        } else {
            var style = draftStyle
            if case .image = style.plate, let image = pendingImage,
               let name = appState.saveCoverImage(image) {
                style.customImageName = name
            }
            appState.setCoverStyle(style, for: category.id)
        }
        // Dock 弹窗参数
        appState.setTilePrefs(draftPrefs, for: category.id)
        if let updated = appState.config.categories.first(where: { $0.id == category.id }) {
            Task {
                await appState.applyTilePrefs(for: updated)
            }
        } else {
            dismiss()
        }
    }
}

// MARK: - 行分隔辅助

private extension View {
    func divided() -> some View {
        overlay(alignment: .bottom) {
            Divider().opacity(0.8)
        }
    }
}

// MARK: - 弹窗样式小示意

private struct PopStyleDemo: View {
    let style: DockTilePrefs.PopupStyle
    var sparse = false
    private let accent = Color.accentColor

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
            switch style {
            case .fan:
                HStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(accent.opacity(0.85))
                            .frame(width: 8, height: 8)
                            .offset(y: CGFloat(abs(i - 2) * 3) - 4)
                    }
                }
            case .grid, .auto:
                Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                    ForEach(0..<2, id: \.self) { r in
                        GridRow {
                            ForEach(0..<3, id: \.self) { c in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(
                                        (sparse && r == 1 && c == 2)
                                            ? accent.opacity(0.3)
                                            : accent.opacity(0.85)
                                    )
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                }
            case .list:
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(accent.opacity(0.85))
                                .frame(width: 7, height: 7)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(accent.opacity(0.3))
                                .frame(height: 4)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
        }
    }
}

// MARK: - 实时预览舞台

/// 迷你桌面：壁纸 + 弹窗预览 + Dock 条（含瓦片预览）
struct PreviewStage: View {
    let category: Category
    let style: CoverStyle
    let prefs: DockTilePrefs
    let customImage: NSImage?

    /// 预览中的图标缩放（弹窗图标 px → 舞台 pt）
    private let previewScale: CGFloat = 0.56

    private var sortedApps: [AppRef] {
        switch prefs.sortBy {
        case .name:
            category.apps.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
        case .mine:
            category.apps
        case .kind:
            category.apps.sorted { $0.bundlePath < $1.bundlePath }
        }
    }

    private var sortLabel: String {
        switch prefs.sortBy {
        case .name: "按名称"
        case .mine: "按我的排序"
        case .kind: "按种类"
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            wallpaper
            // 弹窗紧贴 Dock 条上方，还原真实点击瓦片后的位置
            VStack(spacing: 8) {
                popupPreview
                dockStrip
            }
            .padding(.bottom, 10)
            .padding(.top, 44)
        }
        .overlay(alignment: .top) {
            tags
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var wallpaper: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .fromHex("#6f5df0")),
                    Color(nsColor: .fromHex("#4a86f5")),
                    Color(nsColor: .fromHex("#ff9d8a")),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.white.opacity(0.35), .clear],
                center: .topTrailing,
                startRadius: 10, endRadius: 200
            )
        }
    }

    private var tags: some View {
        HStack {
            stageTag("实时预览")
            Spacer()
            stageTag("排序 · \(sortLabel)")
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }

    private func stageTag(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 9))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.black.opacity(0.25)))
    }

    // MARK: 弹窗预览

    @ViewBuilder
    private var popupPreview: some View {
        let resolved: DockTilePrefs.PopupStyle = prefs.popupStyle == .auto ? .grid : prefs.popupStyle
        let iconPx = CGFloat(prefs.gridSize ?? 48) * previewScale
        switch resolved {
        case .fan:
            FanPopupPreview(apps: sortedApps, iconSize: iconPx)
        case .list:
            glassPopup(labelHidden: false) {
                VStack(spacing: 2) {
                    ForEach(sortedApps) { app in
                        HStack(spacing: 8) {
                            AppIconView(path: app.bundlePath, size: 18)
                            Text(app.displayName).font(.system(size: 10))
                            Spacer(minLength: 0)
                        }
                        .frame(width: 170)
                        .padding(.vertical, 1)
                    }
                }
                .padding(.vertical, 4)
            }
        default:
            glassPopup(labelHidden: false) {
                LazyVGrid(columns: [GridItem(.fixed(iconPx + 26), spacing: 10), GridItem(.fixed(iconPx + 26), spacing: 10), GridItem(.fixed(iconPx + 26), spacing: 10)], alignment: .center, spacing: 8) {
                    ForEach(sortedApps) { app in
                        VStack(spacing: 3) {
                            AppIconView(path: app.bundlePath, size: iconPx)
                            Text(app.displayName)
                                .font(.system(size: 9))
                                .lineLimit(1)
                                .frame(maxWidth: iconPx + 22)
                        }
                    }
                }
            }
        }
    }

    private func glassPopup<Content: View>(labelHidden: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 6) {
            Text(category.name)
                .font(.system(size: 10, weight: .semibold))
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: 330, alignment: .bottom)
        .clipped()
        .glassPanel(cornerRadius: 14)
    }

    // MARK: Dock 条

    private var dockStrip: some View {
        HStack(spacing: 8) {
            tilePreview
                .frame(width: 30, height: 30)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .fromHex("#4aa3f0")))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "safari")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                )
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white.opacity(0.4))
                .frame(width: 1, height: 24)
            Image(systemName: "trash")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .glassPanel(cornerRadius: 14)
    }

    /// 瓦片预览：文件夹 = 生成器实时渲染；堆叠 = 第一个应用图标
    @ViewBuilder
    private var tilePreview: some View {
        if prefs.displayAsFolder {
            let image = MosaicIconGenerator.generate(
                forAppPaths: category.apps.map(\.bundlePath),
                style: style,
                customImage: customImage,
                canvasSize: 128
            )
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
        } else if let first = category.apps.first {
            AppIconView(path: first.bundlePath, size: 28)
        } else {
            RoundedRectangle(cornerRadius: 7).fill(.quaternary)
        }
    }
}

/// 扇形弹窗预览：沿弧线排布
private struct FanPopupPreview: View {
    let apps: [AppRef]
    let iconSize: CGFloat

    var body: some View {
        ZStack {
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                AppIconView(path: app.bundlePath, size: iconSize)
                    .position(position(index: index, count: apps.count))
            }
        }
        .frame(width: 220, height: iconSize + 66)
    }

    private func position(index: Int, count: Int) -> CGPoint {
        let t = count <= 1 ? 0.5 : CGFloat(index) / CGFloat(count - 1)
        let angle = (t - 0.5) * .pi
        return CGPoint(
            x: 110 + sin(angle) * 82,
            y: 20 + (1 - cos(angle)) * 56
        )
    }
}

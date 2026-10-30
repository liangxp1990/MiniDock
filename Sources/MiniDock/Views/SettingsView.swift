import SwiftUI

/// 设置窗口：外观（强调色/图标大小/侧栏徽章，系统设置式表单）+ Pro 状态
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var pane = "appearance"

    private var palette: [(hex: String, name: String)] {
        [
            ("#0a84ff", "蓝"), ("#7d5af0", "紫"), ("#ff375f", "粉红"), ("#ff9f0a", "橙"),
            ("#ffd60a", "黄"), ("#30d158", "绿"), ("#8e8e93", "石墨"),
        ]
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                paneButton("appearance", title: "外观", icon: "palette")
                Spacer()
            }
            .padding(10)
            .frame(width: 130, alignment: .leading)
            .background(.quaternary.opacity(0.25))

            Divider()

            ScrollView {
                Group {
                    appearancePane
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 480, height: 380)
    }

    private func paneButton(_ key: String, title: String, icon: String) -> some View {
        Button {
            pane = key
        } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(pane == key ? Color.accentColor : Color.clear)
        )
        .foregroundStyle(pane == key ? Color.white : Color.primary)
    }

    // MARK: - 外观（系统设置式）

    private var appearancePane: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("强调色").font(.caption).foregroundStyle(.secondary)
            SettingsCard {
                HStack(spacing: 12) {
                    AccentDot(hex: nil, isSelected: appState.settings.accentHex == "system") {
                        appState.settings.accentHex = "system"
                    }
                    .help(Text("多彩 · 跟随系统"))
                    ForEach(palette, id: \.hex) { item in
                        AccentDot(
                            hex: item.hex,
                            isSelected: appState.settings.accentHex.lowercased() == item.hex.lowercased()
                        ) {
                            appState.settings.accentHex = item.hex
                        }
                        .help(item.name)
                    }
                    Spacer()
                    Text("应用于按钮与选中态")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            Text("管理器界面").font(.caption).foregroundStyle(.secondary).padding(.top, 10)
            SettingsCard {
                SettingsRow(title: "应用图标大小", subtitle: nil) {
                    Picker("", selection: Binding(
                        get: { appState.settings.iconSize },
                        set: { appState.settings.iconSize = $0 }
                    )) {
                        ForEach(AppSettings.IconSize.allCases, id: \.self) { size in
                            Text(size.label).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    .labelsHidden()
                }
                .divided()
                SettingsRow(title: "侧栏显示数量徽章", subtitle: "分类名右侧显示应用个数") {
                    Toggle("", isOn: Binding(
                        get: { appState.settings.showSidebarBadge },
                        set: { appState.settings.showSidebarBadge = $0 }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }

            Spacer()
        }
    }
}

private extension View {
    func divided() -> some View {
        overlay(alignment: .bottom) {
            Divider().opacity(0.8)
        }
    }
}

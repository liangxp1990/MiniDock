import SwiftUI

struct GuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text("欢迎使用 MiniDock")
                    .font(.title2.bold())
                Text("三步，把常用 App 按分类装进 Dock")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                GuideStepView(
                    symbol: "folder.badge.plus",
                    title: "1 · 建立分类",
                    subtitle: "新建分类并命名\n从列表勾选常用 App"
                )
                GuideStepView(
                    symbol: "pin",
                    title: "2 · 放进 Dock",
                    subtitle: "一键固定到 Dock\n或拖入 Dock 分隔线右侧"
                )
                GuideStepView(
                    symbol: "hand.tap",
                    title: "3 · 点击使用",
                    subtitle: "点分类图标弹出网格\n再点任意图标即刻启动"
                )
            }

            HStack {
                Button("跳过") {
                    finish()
                }
                .buttonStyle(.link)
                Spacer()
                Button("开始使用") {
                    finish()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "MiniDock.hasSeenGuide")
        dismiss()
    }
}

private struct GuideStepView: View {
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
            Text(title)
                .font(.body.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary.opacity(0.35))
        )
    }
}

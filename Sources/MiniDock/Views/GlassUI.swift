import SwiftUI

// MARK: - Liquid Glass 组件（macOS 26 原生，旧系统回退材质）

/// Liquid Glass 胶囊外观。macOS 26 用原生 glassEffect，低版本回退 ultraThinMaterial。
struct GlassCapsuleModifier: ViewModifier {
    var horizontalPadding: CGFloat = 12
    var height: CGFloat? = 32
    /// 强调色玻璃（主要动作）：与其他胶囊同几何，仅色调突出
    var prominent = false

    func body(content: Content) -> some View {
        Group {
            if #available(macOS 26.0, *) {
                let glass = prominent
                    ? Glass.regular.tint(Color.accentColor).interactive()
                    : Glass.regular.interactive()
                content
                    .padding(.horizontal, horizontalPadding)
                    .frame(height: height)
                    .glassEffect(glass, in: .capsule)
            } else {
                content
                    .padding(.horizontal, horizontalPadding)
                    .frame(height: height)
                    .background(
                        prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.ultraThinMaterial),
                        in: .capsule
                    )
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            }
        }
        .foregroundStyle(prominent ? Color.white : Color.primary)
    }
}

extension View {
    /// 把按钮 label 变成 Liquid Glass 胶囊（配合 .buttonStyle(.plain) 使用）
    func glassCapsule(horizontalPadding: CGFloat = 12, height: CGFloat? = 32, prominent: Bool = false) -> some View {
        modifier(GlassCapsuleModifier(
            horizontalPadding: horizontalPadding, height: height, prominent: prominent
        ))
    }
}

/// 玻璃圆角面板（预览舞台等非按钮表面）
struct GlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        Group {
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            } else {
                content
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            }
        }
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 14) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius))
    }
}

/// 多个玻璃元素共存时的容器（macOS 26 GlassEffectContainer，旧系统原样返回）
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

/// 系统设置「外观」式的强调色圆点
struct AccentDot: View {
    let hex: String?
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let hex {
                    Circle().fill(Color(nsColor: .fromHex(hex)))
                } else {
                    // 多彩：随系统强调色
                    Circle().fill(
                        AngularGradient(
                            colors: [
                                Color(nsColor: .fromHex("#ff5f57")),
                                Color(nsColor: .fromHex("#ff9f0a")),
                                Color(nsColor: .fromHex("#30d158")),
                                Color(nsColor: .fromHex("#0a84ff")),
                                Color(nsColor: .fromHex("#7d5af0")),
                                Color(nsColor: .fromHex("#ff5f57")),
                            ],
                            center: .center
                        )
                    )
                }
            }
            .frame(width: 22, height: 22)
            .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
            .overlay(
                Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(3)
                    .opacity(isSelected ? 1 : 0)
            )
            .padding(1)
        }
        .buttonStyle(.plain)
    }
}

/// 系统设置式分组卡片行
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            )
    }
}

/// 卡片内一行：左侧标签（可带副标题），右侧控件
struct SettingsRow<Trailing: View>: View {
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}


/// 仅图标的 Liquid Glass 胶囊（工具栏项用：图标在胶囊内，标签在胶囊外下方）
struct GlassIconCapsuleModifier: ViewModifier {
    var size: CGFloat = 30

    func body(content: Content) -> some View {
        Group {
            if #available(macOS 26.0, *) {
                content
                    .frame(width: size, height: size)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: size * 0.3))
            } else {
                content
                    .frame(width: size, height: size)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: size * 0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.3)
                            .strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            }
        }
    }
}

extension View {
    func glassIconCapsule(size: CGFloat = 30) -> some View {
        modifier(GlassIconCapsuleModifier(size: size))
    }
}


/// 选项瓦片容器：Liquid Glass 底 + 选中态强调环（设置面板的底板/布局/弹窗样式瓦片用）
struct GlassTileModifier: ViewModifier {
    var selected: Bool
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        Group {
            if #available(macOS 26.0, *) {
                content
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                content
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
                    )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
        )
    }
}

extension View {
    func glassTile(selected: Bool, cornerRadius: CGFloat = 10) -> some View {
        modifier(GlassTileModifier(selected: selected, cornerRadius: cornerRadius))
    }

    /// 主要动作按钮：macOS 26 玻璃突出样式，低版本回退
    func glassProminentButton() -> some View {
        Group {
            if #available(macOS 26.0, *) {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.borderedProminent)
            }
        }
    }
}

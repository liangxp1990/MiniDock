# MiniDock 踩坑记录

## 2026-10-28 · 侧栏顶部与 header 交汇处错位（macOS 26）

**现象**：侧栏右边界在标题栏（header）段比内容段内缩约 2pt，交汇处形成肉眼可见的台阶/错位。原生最小 NavigationSplitView 样例无此问题，但 MiniDock 一直有。

**定位方法（染色实验）**：
1. 侧栏染半透明红（`.scrollContentBackground(.hidden)` + `.background(Color.red.opacity(0.55))`）
2. 逐行测量红区右缘 → 发现 header 段 x=412px、内容段 x=416px，**2pt 台阶**精确暴露
3. 红色本身从窗口顶到底完全均匀（说明侧栏背景一直画到顶部，之前"背景进不了标题栏"的判断是错的）

**核心原因**：macOS 26 中挂在 detail 列上的 `.toolbar` 会让系统在窗口顶部绘制一层**横贯全宽的工具栏背景材质**——它盖在侧栏列上方，且这层材质在侧栏区的边缘比真实分隔线**内缩约 2pt**。侧栏自己的背景虽然完整贯通，但被这层带内缩边缘的材质叠压切割，视觉上就出现台阶。样例 demo 的极简工具栏不触发该材质层，所以看不出；我们的多按钮工具栏触发了。

**修复**（一行）：

```swift
.toolbarBackground(.hidden, for: .windowToolbar)
```

隐藏工具栏背景材质后，侧栏列与详情列各自从窗口顶贯通到底，与原生样例一致。

**教训**：
- macOS 26 的"侧栏顶部"在渲染上属于工具栏层，排查此类问题不要信视觉模型对截图的描述，用染色 + 逐像素测边界
- `NSView.draw(_:)` 与自造 `NSColor.cgColor` 在现代分层合成窗口的 themeFrame 覆盖层上不可靠（system 系颜色可靠）——曾为此绕了一晚上
- 半透明工具栏背景实验（toolbarBackground 染色）也是快速定位区域归属的好办法

## 2026-10-28 · SwiftUI 工具栏无法显示"标签在图标底部"

**现象**：macOS 26 原生应用（访达等）工具栏项为"图标在玻璃胶囊内 + 小字标签在底部"；SwiftUI 的 `ToolbarItem` 中无论 `Label` 还是 `.labelStyle(.titleAndIcon)`，系统工具栏一律渲染成纯图标（无公开 API 控制）。

**解法**：自绘复刻——`Button(plain)` + `VStack { 图标.glassEffect(胶囊); Text(.caption2) }`，配合 `ToolbarSpacer(.fixed)` 做分组（见 ContentView.toolbarButton）。

## 2026-10-28 · 关窗后点 Dock 图标无法重开窗口

**现象**：关闭主窗口后 App 仍在运行，点 Dock 图标不重建窗口，只能退出重开。

**根因**：SwiftUI 不处理 `applicationShouldHandleReopen`。实测关闭窗口后 `NSApp.windows` 里主窗口已彻底销毁（列表为空），无窗可 `makeKeyAndOrderFront` 恢复——必须主动新建。

**修复**：`NSApplicationDelegateAdaptor` 接管 reopen；主窗口 `WindowGroup(id: "main")`；ContentView 把 `@Environment(\.openWindow)` 存入共享持有者 `MainWindowOpener`，AppDelegate 在无窗可恢复时 `openWindow(id: "main")` 新建（见 MiniDockApp.swift）。

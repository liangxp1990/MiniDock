import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CategoryDetailView: View {
    @Environment(AppState.self) private var appState
    let category: Category

    @State private var droppingApp = false

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 140), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                brokenBanner
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(category.apps) { app in
                        AppTileView(
                            app: app,
                            broken: appState.brokenAppIDs.contains(app.id),
                            iconSize: appState.settings.iconSize.points,
                            onRemove: { appState.removeApp(app.id, from: category.id) },
                            onRepair: { repair(app) }
                        )
                        .draggable(app.id.uuidString)
                        .dropDestination(for: String.self) { items, _ in
                            guard let first = items.first,
                                  let draggedID = UUID(uuidString: first),
                                  draggedID != app.id
                            else { return false }
                            appState.moveApp(withID: draggedID, before: app.id, in: category.id)
                            return true
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .dropDestination(for: URL.self) { urls, _ in
            let refs = urls
                .filter { $0.pathExtension == "app" }
                .map { AppRef(bundlePath: $0.path, displayName: $0.deletingPathExtension().lastPathComponent) }
            guard !refs.isEmpty else { return false }
            appState.addApps(refs, to: category.id)
            return true
        } isTargeted: { droppingApp = $0 }
        .overlay {
            if droppingApp {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(12)
                    .overlay {
                        Label("松手添加到「\(category.name)」", systemImage: "plus.app")
                            .padding(8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .allowsHitTesting(false)
            }
        }
    }

    private var brokenBanner: some View {
        let brokenCount = category.apps.filter { appState.brokenAppIDs.contains($0.id) }.count
        return Group {
            if brokenCount > 0 {
                Label("\(brokenCount) 个应用未找到，点击红色图标修复", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func repair(_ app: AppRef) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.message = "选择「\(app.displayName)」的新位置"
        if panel.runModal() == .OK, let url = panel.url {
            appState.repairApp(app.id, in: category.id, newBundleURL: url)
        }
    }
}

struct AppTileView: View {
    let app: AppRef
    let broken: Bool
    var iconSize: CGFloat = 54
    let onRemove: () -> Void
    let onRepair: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                AppIconView(path: app.bundlePath, size: iconSize)
                    .opacity(broken ? 0.55 : 1)
                    .overlay {
                        if broken {
                            RoundedRectangle(cornerRadius: iconSize * 0.24)
                                .strokeBorder(Color.red, lineWidth: 2)
                                .frame(width: iconSize, height: iconSize)
                        }
                    }
                if broken {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red, .white)
                        .font(.system(size: 13))
                        .offset(x: 5, y: -5)
                        .shadow(radius: 1)
                }
            }
            Text(app.displayName)
                .font(.caption)
                .lineLimit(1)
                .help(app.bundlePath)
            if broken {
                Text("未找到 · 点击修复")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(8)
        .contentShape(.rect)
        .onTapGesture {
            if broken {
                onRepair()
            }
        }
        .contextMenu {
            Button("在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([app.bundleURL])
            }
            Divider()
            Button("移除", role: .destructive) {
                onRemove()
            }
        }
    }
}

struct AppIconView: View {
    let path: String
    var size: CGFloat = 54

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

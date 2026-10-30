import SwiftUI

struct AppPickerSheet: View {
    let category: Category
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var apps: [FoundApp] = []
    @State private var loading = true
    @State private var query = ""
    @State private var selected: Set<String> = []

    private var existingPaths: Set<String> {
        Set(category.apps.map(\.bundlePath))
    }

    private var filtered: [FoundApp] {
        let keyword = query.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(keyword) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("添加应用到「\(category.name)」")
                        .font(.headline)
                    Text(loading ? "正在扫描已安装应用…" : "共 \(apps.count) 个已安装应用")
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
            .padding(16)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索应用名称…", text: $query)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Divider()

            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                    Text("没有匹配的应用")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filtered) { app in
                        row(app)
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                Text("已选 \(selected.count) 个应用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") {
                    dismiss()
                }
                Button("添加") {
                    confirm()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 480, height: 520)
        .task {
            await load()
        }
    }

    private func row(_ app: FoundApp) -> some View {
        let added = existingPaths.contains(app.path)
        return HStack(spacing: 10) {
            if added {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Toggle("", isOn: Binding(
                    get: { selected.contains(app.id) },
                    set: { if $0 { selected.insert(app.id) } else { selected.remove(app.id) } }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            }
            AppIconView(path: app.path, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                Text(app.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if added {
                Text("已添加")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private func load() async {
        let bundlePath = Bundle.main.bundleURL.path
        let excluding: Set<String> = bundlePath.hasSuffix(".app") ? [bundlePath] : []
        let result = await Task.detached(priority: .userInitiated) {
            AppScanner.scan(excludingPaths: excluding)
        }.value
        apps = result
        loading = false
    }

    private func confirm() {
        let refs = apps
            .filter { selected.contains($0.id) }
            .map { AppRef(bundlePath: $0.path, displayName: $0.name) }
        appState.addApps(refs, to: category.id)
        dismiss()
    }
}

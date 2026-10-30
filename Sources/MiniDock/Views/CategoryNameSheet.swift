import SwiftUI

struct CategoryNameSheet: View {
    enum Mode {
        case create
        case rename(currentName: String)
    }

    let mode: Mode
    let onConfirm: (String) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(mode: Mode, onConfirm: @escaping (String) -> Void) {
        self.mode = mode
        self.onConfirm = onConfirm
        if case .rename(let current) = mode {
            _name = State(initialValue: current)
        } else {
            _name = State(initialValue: "")
        }
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isRenameUnchanged: Bool {
        if case .rename(let current) = mode { return trimmed == current }
        return false
    }

    private var validationError: String? {
        guard !trimmed.isEmpty, !isRenameUnchanged else { return nil }
        let duplicated = appState.config.categories.contains { $0.name == trimmed }
        return duplicated ? "已存在同名分类" : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isCreating ? "新建分类" : "重命名分类")
                .font(.headline)
            TextField("分类名称（例如：效率办公）", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(confirm)
            if let error = validationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                Button(isCreating ? "创建" : "重命名") {
                    confirm()
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmed.isEmpty || validationError != nil)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private var isCreating: Bool {
        if case .create = mode { return true }
        return false
    }

    private func confirm() {
        guard !trimmed.isEmpty, validationError == nil else { return }
        onConfirm(trimmed)
        dismiss()
    }
}

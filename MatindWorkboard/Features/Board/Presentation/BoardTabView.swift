import SwiftUI

/// 一次「添加插件」请求。用新的标识区分重复点击，而不是用开关来回拨。
struct PluginAddRequest: Equatable {
    let id: UUID
}

struct BoardContentView: View {
    let boardId: String
    let access: BoardSurfaceAccess
    let editing: BoardEditing
    let pluginAddRequest: PluginAddRequest?
    @State private var layoutVM = BoardLayoutViewModel()
    @StateObject private var registry = PluginRegistry.shared

    var body: some View {
        ZStack {
            BoardGridView(
                layoutVM: layoutVM,
                boardId: boardId,
                plugins: registry.plugins,
                arrangement: BoardArrangement.resolve(access: access, editing: editing)
            )
            if layoutVM.isLoading {
                ProgressView("加载布局…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background.opacity(0.6))
            }
        }
        .task {
            registry.loadBuiltinPlugins()
        }
        .task(id: boardId) {
            await layoutVM.load(boardId: boardId)
        }
        .onChange(of: pluginAddRequest) { _, request in
            if request != nil {
                layoutVM.showPluginPicker = true
            }
        }
    }
}

/// 改名和删除都从这里进入。删除必须重新输入完整名称。
struct BoardManageSheet: View {
    let board: Board
    let onRename: (String, UUID) async throws -> Void
    let onDelete: (String?, UUID) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var confirmation = ""
    @State private var reason = ""
    @State private var renameKey = UUID()
    @State private var deleteKey = UUID()
    @State private var action: ManageAction = .idle
    @State private var message: String?

    init(
        board: Board,
        onRename: @escaping (String, UUID) async throws -> Void,
        onDelete: @escaping (String?, UUID) async throws -> Void
    ) {
        self.board = board
        self.onRename = onRename
        self.onDelete = onDelete
        _name = State(initialValue: board.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("管理页面")
                .font(.headline)
            TextField("名称", text: $name)
                .textFieldStyle(.roundedBorder)
            Button("保存名称") { Task { await rename() } }
                .disabled(name == board.name || action != .idle)

            Divider()

            Text("删除页面")
                .font(.headline)
            Text("输入「\(board.name)」以确认删除")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("页面名称", text: $confirmation)
                .textFieldStyle(.roundedBorder)
            TextField("原因（可选）", text: $reason)
                .textFieldStyle(.roundedBorder)
            Button("删除", role: .destructive) { Task { await remove() } }
                .disabled(confirmation != board.name || action != .idle)

            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func rename() async {
        action = .renaming
        message = nil
        do {
            try await onRename(name, renameKey)
            dismiss()
        } catch {
            message = PresentedFailure.message(for: error)
            action = .idle
        }
    }

    private func remove() async {
        action = .deleting
        message = nil
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await onDelete(trimmed.isEmpty ? nil : trimmed, deleteKey)
            dismiss()
        } catch {
            message = PresentedFailure.message(for: error)
            action = .idle
        }
    }
}

private enum ManageAction: Equatable {
    case idle
    case renaming
    case deleting
}

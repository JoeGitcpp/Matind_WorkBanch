import SwiftUI

struct BoardTabView: View {
    let selectedBoardId: String?
    let boards: [Board]
    let workspaceId: String
    let onSelect: (String) -> Void
    let onDelete: (String) async -> Void

    var body: some View {
        if boards.isEmpty {
            ContentUnavailableView(
                "暂无工作板",
                systemImage: "rectangle.stack",
                description: Text("点击 + 添加工作板")
            )
        } else {
            VStack(spacing: 0) {
                // 顶部 Tab 栏
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(boards) { board in
                            BoardTabItem(
                                board: board,
                                isSelected: selectedBoardId == board.id,
                                onSelect: { onSelect(board.id) },
                                onDelete: {
                                    Task { await onDelete(board.id) }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(height: 40)
                .background(.bar)

                Divider()

                // 内容区
                if let selectedBoardId {
                    BoardContentView(boardId: selectedBoardId)
                } else {
                    ContentUnavailableView("选择工作板", systemImage: "rectangle.stack")
                }
            }
        }
    }
}

struct BoardTabItem: View {
    let board: Board
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Text(board.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                if board.isDefault == true {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : .clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("删除工作板", systemImage: "trash")
            }
        }
    }
}

struct BoardContentView: View {
    let boardId: String

    var body: some View {
        VStack {
            Text("工作板内容")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Board ID: \(boardId)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

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
    @StateObject private var registry = PluginRegistry.shared

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                ForEach(registry.plugins) { plugin in
                    PluginCard(plugin: plugin)
                        .frame(height: 200)
                }
            }
            .padding()
        }
        .task {
            registry.loadBuiltinPlugins()
        }
        .overlay {
            if registry.plugins.isEmpty {
                ContentUnavailableView("暂无插件", systemImage: "puzzlepiece")
            }
        }
    }
}

struct PluginCard: View {
    let plugin: PluginManifest

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Image(systemName: pluginIcon(for: plugin.category))
                    .foregroundStyle(.blue)
                Text(plugin.name)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            // 内容区：WebView
            if let pluginDir = Bundle.main.url(
                forResource: plugin.id,
                withExtension: nil,
                subdirectory: "Plugins"
            ) {
                WebViewPluginHost(
                    pluginId: plugin.id,
                    pluginDirectory: pluginDir,
                    apiToken: nil
                )
            } else {
                Color.gray.opacity(0.1)
                    .overlay {
                        Text("插件资源未找到")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    private func pluginIcon(for category: String) -> String {
        switch category {
        case "data": return "chart.bar"
        case "tools": return "wrench.and.screwdriver"
        case "monitoring": return "gauge"
        default: return "puzzlepiece"
        }
    }
}

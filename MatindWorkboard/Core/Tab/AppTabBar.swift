import SwiftUI

/// 统一标签栏
/// 显示所有打开的标签页（工作板 + 设置 + 自动化等）
struct AppTabBar: View {
    let tabs: [AppTab]
    let selectedTabId: String?
    let onSelect: (String) -> Void
    let onClose: (String) -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        AppTabItem(
                            tab: tab,
                            isSelected: selectedTabId == tab.id,
                            onSelect: { onSelect(tab.id) },
                            onClose: { onClose(tab.id) }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()

            // + 按钮（添加工作板）
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .help("新建工作板")
        }
        .frame(height: 40)
        .background(.bar)
    }
}

/// 单个标签项
struct AppTabItem: View {
    let tab: AppTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Text(tab.title)
                    .font(.system(size: 13))
                    .lineLimit(1)

                // 关闭按钮（悬停或选中时显示）
                if isHovering || isSelected {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : isHovering ? Color.primary.opacity(0.05) : .clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button(action: onClose) {
                Label("关闭标签", systemImage: "xmark")
            }

            if tab.isBoard {
                Divider()
                Button(role: .destructive, action: {}) {
                    Label("删除工作板", systemImage: "trash")
                }
            }
        }
    }
}

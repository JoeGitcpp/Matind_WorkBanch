import SwiftUI

/// 统一标签栏。关闭只收起页签，删除放在管理菜单里。
struct AppTabBar: View {
    let tabs: [AppTab]
    let boards: [Board]
    let selectedTabId: String?
    let canCreate: Bool
    let createHelp: String
    let onSelect: (String) -> Void
    let onClose: (String) -> Void
    let onCreate: () -> Void
    let onReopen: (String) -> Void
    let onManage: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        AppTabItem(
                            tab: tab,
                            isSelected: selectedTabId == tab.id,
                            onSelect: { onSelect(tab.id) },
                            onClose: { onClose(tab.id) },
                            onManage: manageAction(for: tab)
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()

            pageMenu
            createButton
        }
        .frame(height: 40)
        .background(.bar)
    }

    private var pageMenu: some View {
        Menu {
            if boards.isEmpty {
                Text("还没有页面")
            } else {
                ForEach(boards) { board in
                    Button(board.name) { onReopen(board.id) }
                }
            }
        } label: {
            Image(systemName: "list.bullet")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 4)
        .help("所有页面")
    }

    private var createButton: some View {
        Button(action: onCreate) {
            Image(systemName: "plus")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .disabled(!canCreate)
        .help(createHelp)
    }

    private func manageAction(for tab: AppTab) -> (() -> Void)? {
        guard case .board(let id, _) = tab,
              boards.first(where: { $0.id == id })?.settingsCapability.permitsManagement == true else {
            return nil
        }
        return { onManage(id) }
    }
}

struct AppTabItem: View {
    let tab: AppTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onManage: (() -> Void)?

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

                if isHovering || isSelected {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("关闭标签")
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
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            onManage?()
        })
        .contextMenu {
            Button(action: onClose) {
                Label("关闭标签", systemImage: "xmark")
            }
            if let onManage {
                Button(action: onManage) {
                    Label("管理", systemImage: "slider.horizontal.3")
                }
            }
        }
    }
}

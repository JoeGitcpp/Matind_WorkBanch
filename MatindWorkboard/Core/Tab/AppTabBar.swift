import SwiftUI

/// 统一标签栏。工作板页签上的叉是删除页面，不再另开一份页面列表。
struct AppTabBar: View {
    let tabs: [AppTab]
    let boards: [Board]
    let selectedTabId: String?
    let canCreate: Bool
    let createHelp: String
    let onSelect: (String) -> Void
    let onClose: (String) -> Void
    let onCreate: () -> Void
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
                            onClose: closeAction(for: tab),
                            closeTitle: tab.isBoard ? "删除页面" : "关闭标签",
                            onManage: manageAction(for: tab)
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()

            createButton
        }
        .frame(height: 40)
        .background(.bar)
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

    /// 工作板页签只有具备管理权限时才出现删除；设置和自动化页签只是关掉自己。
    private func closeAction(for tab: AppTab) -> (() -> Void)? {
        switch tab {
        case .board(let id, _):
            guard boards.first(where: { $0.id == id })?.settingsCapability.permitsManagement == true else {
                return nil
            }
            return { onClose(tab.id) }
        case .settings, .automation:
            return { onClose(tab.id) }
        }
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
    let onClose: (() -> Void)?
    let closeTitle: String
    let onManage: (() -> Void)?

    @State private var isHovering = false

    private var showsCloseButton: Bool {
        onClose != nil && (isHovering || isSelected)
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                HStack(spacing: 6) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? .primary : .secondary)

                    Text(tab.title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                }
                .padding(.leading, 12)
                .padding(.vertical, 8)
                .padding(.trailing, showsCloseButton ? 0 : 12)
            }
            .buttonStyle(.plain)

            if showsCloseButton, let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .help(closeTitle)
            }
        }
        .background(isSelected ? Color.accentColor.opacity(0.15) : isHovering ? Color.primary.opacity(0.05) : .clear)
        .cornerRadius(6)
        .onHover { hovering in
            isHovering = hovering
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            onManage?()
        })
        .contextMenu {
            if let onClose {
                Button(role: tab.isBoard ? .destructive : nil, action: onClose) {
                    Label(closeTitle, systemImage: tab.isBoard ? "trash" : "xmark")
                }
            }
            if let onManage {
                Button(action: onManage) {
                    Label("管理", systemImage: "slider.horizontal.3")
                }
            }
        }
    }
}

import SwiftUI

struct NotificationCenterView: View {
    @Bindable var viewModel: NotificationViewModel
    var onNavigateToBoard: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Text("通知")
                    .font(.headline)
                Spacer()
                if viewModel.unreadCount > 0 {
                    Button("全部已读") {
                        Task { await viewModel.markAllAsRead() }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // 通知列表
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if viewModel.notifications.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("暂无通知")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.notifications) { notification in
                            NotificationRowView(notification: notification) {
                                if let boardId = notification.boardId {
                                    onNavigateToBoard?(boardId)
                                }
                            }
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .frame(width: 320, height: 400)
        .task {
            await viewModel.loadNotifications()
        }
    }
}

struct NotificationRowView: View {
    let notification: AppNotification
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                // 类型图标
                Image(systemName: notificationIcon(for: notification.type))
                    .font(.system(size: 16))
                    .foregroundStyle(notificationColor(for: notification.type))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(notification.title)
                        .font(.system(size: 13, weight: notification.isRead ? .regular : .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(notification.content)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if !notification.isRead {
                    Circle()
                        .fill(.blue)
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(notification.isRead ? Color.clear : Color.blue.opacity(0.04))
        }
        .buttonStyle(.plain)
    }

    private func notificationIcon(for type: NotificationType) -> String {
        switch type {
        case .system: return "info.circle"
        case .approval: return "checkmark.circle"
        case .invite: return "person.badge.plus"
        case .message: return "message"
        }
    }

    private func notificationColor(for type: NotificationType) -> Color {
        switch type {
        case .system: return .blue
        case .approval: return .green
        case .invite: return .purple
        case .message: return .orange
        }
    }
}

// Badge 视图
struct NotificationBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.red)
                .clipShape(Capsule())
        }
    }
}

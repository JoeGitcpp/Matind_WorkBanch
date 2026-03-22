import Foundation
import Observation

@Observable
@MainActor
final class NotificationViewModel {
    private(set) var notifications: [AppNotification] = []
    private(set) var unreadCount: Int = 0
    private(set) var isLoading = false
    private(set) var error: String?

    private let repository: any NotificationRepositoryProtocol
    private let notificationService = NotificationService.shared

    init(repository: any NotificationRepositoryProtocol = NotificationRepository()) {
        self.repository = repository
    }

    func loadUnreadCount() async {
        do {
            unreadCount = try await repository.fetchUnreadCount()
        } catch {
            // 未读数失败不显示错误（非关键路径）
            print("[NotificationViewModel] Failed to fetch unread count: \(error)")
        }
    }

    func loadNotifications() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            notifications = try await repository.fetchNotifications(page: 1)
            unreadCount = notifications.filter { !$0.isRead }.count
        } catch {
            self.error = error.localizedDescription
        }
    }

    func markAllAsRead() async {
        do {
            try await repository.markAllAsRead()
            unreadCount = 0
            notifications = notifications.map { notification in
                // 创建标记已读的副本（不可变原则）
                AppNotification(
                    id: notification.id,
                    type: notification.type,
                    title: notification.title,
                    content: notification.content,
                    isRead: true,
                    createdAt: notification.createdAt,
                    boardId: notification.boardId
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func requestNotificationPermission() async {
        let granted = await notificationService.requestPermission()
        print("[NotificationViewModel] Notification permission: \(granted)")
    }
}

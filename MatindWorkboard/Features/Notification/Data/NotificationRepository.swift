import Foundation

protocol NotificationRepositoryProtocol: Sendable {
    func fetchNotifications(page: Int) async throws -> [AppNotification]
    func fetchUnreadCount() async throws -> Int
    func markAllAsRead() async throws
}

struct NotificationRepository: NotificationRepositoryProtocol {
    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func fetchNotifications(page: Int) async throws -> [AppNotification] {
        let response: NotificationListResponse = try await client.post(
            "/notification/list",
            body: ["page": page, "pageSize": 20]
        )
        return response.notifications
    }

    func fetchUnreadCount() async throws -> Int {
        let response: UnreadCountResponse = try await client.get("/notification/unReadTotal")
        return response.unreadCount
    }

    func markAllAsRead() async throws {
        struct MarkReadResponse: Codable { let success: Bool? }
        let _: MarkReadResponse = try await client.post("/notification/updateIsRead", body: ["all": true])
    }
}

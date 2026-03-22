import Foundation

struct AppNotification: Codable, Identifiable, Sendable {
    let id: String
    let type: NotificationType
    let title: String
    let content: String
    let isRead: Bool
    let createdAt: String?
    let boardId: String?

    enum CodingKeys: String, CodingKey {
        case id, type, title, content
        case isRead = "is_read"
        case createdAt = "created_at"
        case boardId = "board_id"
    }
}

enum NotificationType: String, Codable, Sendable {
    case system
    case approval
    case invite
    case message
}

struct NotificationListResponse: Codable, Sendable {
    let data: [AppNotification]?
    let list: [AppNotification]?
    let total: Int?

    var notifications: [AppNotification] {
        data ?? list ?? []
    }
}

struct UnreadCountResponse: Codable, Sendable {
    let count: Int?
    let total: Int?

    var unreadCount: Int {
        count ?? total ?? 0
    }
}

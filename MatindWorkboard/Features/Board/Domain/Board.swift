import Foundation

struct Board: Codable, Identifiable, Sendable {
    let id: String
    let workspaceId: String?
    let name: String
    let isDefault: Bool?
    let config: BoardConfig?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, config
        case workspaceId = "workspace_id"
        case isDefault = "is_default"
        case createdAt = "created_at"
    }
}

struct BoardConfig: Codable, Sendable {
    let layout: String?
}

struct BoardListResponse: Codable, Sendable {
    let data: [Board]?
    let list: [Board]?

    var boards: [Board] {
        data ?? list ?? []
    }
}

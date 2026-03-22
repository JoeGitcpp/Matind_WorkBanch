import Foundation

struct Workspace: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case createdAt = "created_at"
    }
}

struct WorkspaceListResponse: Codable, Sendable {
    let data: [Workspace]?
    let list: [Workspace]?

    // 兼容两种后端格式
    var workspaces: [Workspace] {
        data ?? list ?? []
    }
}

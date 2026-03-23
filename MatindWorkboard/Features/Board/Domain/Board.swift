import Foundation

struct Board: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let workbenchId: String?
    let name: String
    let isDefault: Bool?
    let config: BoardConfig?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, config, workbenchId
        case isDefault = "is_default"
        case createdAt = "created_at"
    }
}

struct BoardConfig: Codable, Sendable, Equatable {
    let layout: String?
}

struct BoardListResponse: Codable, Sendable {
    let data: [Board]?
    let list: [Board]?

    var boards: [Board] {
        data ?? list ?? []
    }
}

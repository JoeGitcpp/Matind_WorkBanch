import Foundation

struct Workbench: Identifiable, Sendable {
    let id: String   // 内部用 String，后台传 Int64
    let name: String
    let description: String?
    let isOwner: Bool?
    let role: String?
}

extension Workbench: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, description, role
        case isOwner
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 后台返回 Int64，转成 String
        if let intId = try? c.decode(Int64.self, forKey: .id) {
            id = String(intId)
        } else {
            id = try c.decode(String.self, forKey: .id)
        }
        name = try c.decode(String.self, forKey: .name)
        description = try? c.decode(String.self, forKey: .description)
        isOwner = try? c.decode(Bool.self, forKey: .isOwner)
        role = try? c.decode(String.self, forKey: .role)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(isOwner, forKey: .isOwner)
        try c.encodeIfPresent(role, forKey: .role)
    }
}

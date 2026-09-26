import Foundation

struct User: Codable, Identifiable, Sendable {
    let id: Int64
    let email: String?
    let name: String?
    let account: String?

    // 展示用
    var displayName: String {
        name ?? account ?? email ?? "用户"
    }
}

struct ApiResponse<T: Codable & Sendable>: Codable, Sendable {
    let code: Int
    let msg: String
    let data: T?
}

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

struct LoginRequest: Codable, Sendable {
    let account: String
    let password: String
}

// 后台返回格式：data 层平铺用户信息 + token
struct LoginResponse: Codable, Sendable {
    let token: String
    let id: Int64
    let email: String?
    let name: String?
    let account: String?

    var user: User {
        User(id: id, email: email, name: name, account: account)
    }
}

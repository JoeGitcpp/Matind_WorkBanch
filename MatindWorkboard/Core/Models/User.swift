import Foundation

struct User: Codable, Identifiable, Sendable {
    let id: String
    let email: String
    let name: String?
}

struct LoginRequest: Codable, Sendable {
    let email: String
    let password: String
}

struct LoginResponse: Codable, Sendable {
    let token: String
    let user: User
}

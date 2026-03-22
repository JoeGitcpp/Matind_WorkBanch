import Foundation
import Observation

@Observable
@MainActor
final class AuthState {
    private(set) var isAuthenticated = false
    private(set) var currentUser: User?

    private let authService = AuthService()

    init() {
        // 启动时检查 Keychain 中是否有 token
        if let token = authService.loadToken() {
            Task {
                await APIClient.shared.setToken(token)
                self.isAuthenticated = true
            }
        }

        // 监听未授权响应
        NotificationCenter.default.addObserver(
            forName: .unauthorizedResponse,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.logout()
            }
        }
    }

    func login(token: String, user: User? = nil) {
        try? authService.saveToken(token)
        Task {
            await APIClient.shared.setToken(token)
        }
        self.currentUser = user
        self.isAuthenticated = true
    }

    func logout() {
        authService.clearToken()
        Task {
            await APIClient.shared.setToken(nil)
        }
        self.currentUser = nil
        self.isAuthenticated = false
    }
}

struct User: Codable, Identifiable {
    let id: String
    let email: String
    let name: String?
}

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
            isAuthenticated = true  // 同步设置，消除闪烁
            Task {
                await APIClient.shared.setToken(token)
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
        do {
            try authService.saveToken(token)
            Task {
                await APIClient.shared.setToken(token)
            }
            self.currentUser = user
            self.isAuthenticated = true
        } catch {
            // Keychain 写入失败，不标记为已登录
            print("[AuthState] Failed to save token: \(error)")
        }
    }

    func loginWithCredentials(email: String, password: String) async throws {
        let response: LoginResponse = try await APIClient.shared.post(
            "/auth/login",
            body: LoginRequest(email: email, password: password)
        )
        login(token: response.token, user: response.user)
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

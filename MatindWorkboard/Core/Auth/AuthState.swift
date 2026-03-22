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
                // TODO(M3): 调用 /auth/me 验证 token 并填充 currentUser
                // let user: User = try? await APIClient.shared.get("/auth/me")
                // self.currentUser = user
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
        } catch {
            print("[AuthState] Failed to save token to Keychain: \(error)")
            return
        }
        // 先等 APIClient 设置好 token，再标记登录状态
        Task {
            await APIClient.shared.setToken(token)
            self.currentUser = user
            self.isAuthenticated = true
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
            self.currentUser = nil
            self.isAuthenticated = false
        }
    }
}

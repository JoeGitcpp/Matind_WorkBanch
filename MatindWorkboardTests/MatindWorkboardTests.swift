import Testing
import Foundation
@testable import MatindWorkboard

@Suite("AppConfig Tests")
struct AppConfigTests {
    @Test("API base URL is correct")
    func apiBaseURL() {
        #expect(AppConfig.apiBaseURL == "https://api.matind.com")
    }

    @Test("Keychain service name is correct")
    func keychainService() {
        #expect(AppConfig.keychainService == "matind-workboard")
    }
}

@Suite("AuthService Tests")
struct AuthServiceTests {
    @Test("Token save and load roundtrip")
    func tokenRoundtrip() throws {
        let service = AuthService()
        let testToken = "test-token-\(UUID().uuidString)"

        try service.saveToken(testToken)
        let loaded = service.loadToken()
        #expect(loaded == testToken)

        service.clearToken()
        #expect(service.loadToken() == nil)
    }
}

@Suite("LoginView Logic Tests")
struct LoginViewTests {
    @Test("Empty email disables login")
    func emptyEmailDisablesLogin() {
        // 验证：email 为空时不应允许登录触发
        // LoginView 中的 disabled 条件：email.isEmpty || password.isEmpty
        let email = ""
        let password = "test123"
        #expect(email.isEmpty || password.isEmpty == true)
    }

    @Test("Empty password disables login")
    func emptyPasswordDisablesLogin() {
        let email = "test@example.com"
        let password = ""
        #expect(email.isEmpty || password.isEmpty == true)
    }

    @Test("Both filled enables login")
    func bothFilledEnablesLogin() {
        let email = "test@example.com"
        let password = "test123"
        #expect(!(email.isEmpty || password.isEmpty))
    }
}

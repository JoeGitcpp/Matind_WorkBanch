import Foundation

enum AppConfig {
    #if DEBUG
    static let apiBaseURL = "http://localhost:8800"
    #else
    static let apiBaseURL = "https://api.matind.com"
    #endif
    static let keychainService = "matind-workboard"
    static let keychainAccount = "auth_token"
    static let lastVisitedKey = "matind:lastVisited"
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
}

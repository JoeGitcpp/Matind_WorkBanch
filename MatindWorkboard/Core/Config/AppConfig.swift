import Foundation

enum AppConfig {
    static let apiBaseURL = "https://api.matind.com"
    static let keychainService = "matind-workboard"
    static let keychainAccount = "auth_token"
    static let lastVisitedKey = "matind:lastVisited"
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
}

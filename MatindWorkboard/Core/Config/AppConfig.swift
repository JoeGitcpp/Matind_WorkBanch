import Foundation

/// 构建配置只含公开地址，按方案（本机 / 线上）写入 Info.plist；客户端不含任何密钥。
enum AppConfig {
    // The direct execution edition and development preview have their own identities.
    // Existing sandbox installations retain their original service name.
    static let keychainService = configuredText("MATIND_DISTRIBUTION") == "direct"
        ? (Bundle.main.bundleIdentifier ?? "com.matrixindustry.matind-workboard.operations")
        : "matind-workboard"
    static let keychainAccount = "auth_token"
    static let sessionAccount = "session"
    /// 设备签名私钥。和登录令牌不是同一条钥匙串记录。
    static let deviceKeyAccount = "device_signing_key"
    static let privateServerLedgerKey = "matind.privateServer.ledger"
    static let serviceCatalogKey = "matind.privateServer.serviceCatalog"
    static let lastVisitedKey = "matind:lastVisited"
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

    /// 当前方案名称：本机或线上。由构建配置写入，不跟随编译是否为调试。
    static var configName: String {
        configuredText("APP_CONFIG_NAME") ?? "未命名配置"
    }

    static var apiBaseURL: String {
        configuredText("API_BASE_URL") ?? ""
    }

    /// 网页地址：浏览器授权登录与注册都在网页完成。
    static var webBaseURL: String {
        configuredText("WEB_BASE_URL") ?? ""
    }

    static var apiBase: URL? {
        absoluteURL(apiBaseURL)
    }

    static var webBase: URL? {
        absoluteURL(webBaseURL)
    }

    private static func absoluteURL(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme != nil, url.host != nil else {
            return nil
        }
        return url
    }

    private static func configuredText(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

import CryptoKit
import Foundation

public struct SessionTokens: Equatable, Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

public enum SessionPolicy {
    /// 过期前 60 秒就开始刷新，避免请求打到一半才失效。
    public static func shouldRefresh(_ session: SessionTokens, now: Date) -> Bool {
        session.expiresAt.timeIntervalSince(now) < 60
    }
}

public struct IdentityGrant: Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

/// 不带填充的 base64url 随机串。系统随机数在 Apple 平台上是密码学安全的。
public enum RandomToken {
    public static func make(bytes count: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Base64URL.encode(Data(bytes))
    }
}

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// RFC 7636 的校验值对：verifier 只留在本机，challenge 交给浏览器。
public struct PKCEPair: Equatable, Sendable {
    public let verifier: String
    public let challenge: String

    public init(verifier: String) {
        self.verifier = verifier
        self.challenge = Base64URL.encode(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    public static func random() -> PKCEPair {
        PKCEPair(verifier: RandomToken.make(bytes: 32))
    }
}

/// 回环地址收到的一次请求的判定结果。
public enum AuthorizationCallback: Equatable, Sendable {
    case granted(code: String)
    case denied
    /// 路径不对或 state 不匹配：不是这次授权的回跳，忽略并继续等待。
    case unrelated
}

/// 一次浏览器授权：PKCE、防串线的 state 与本机回环回跳地址。
public struct BrowserAuthorization: Equatable, Sendable {
    public let pkce: PKCEPair
    public let state: String
    public let redirectURI: URL

    public init(redirectURI: URL, pkce: PKCEPair = .random(), state: String = RandomToken.make(bytes: 24)) {
        self.redirectURI = redirectURI
        self.pkce = pkce
        self.state = state
    }

    /// 网页授权页地址；语言前缀交给网页按用户偏好补齐。
    public func authorizeURL(webBase: URL) throws -> URL {
        guard var components = URLComponents(url: webBase, resolvingAgainstBaseURL: false) else {
            throw ControlPlaneFailure.undecodable
        }
        let root = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = root + "/desktop/authorize"
        components.queryItems = [
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "state", value: state)
        ]
        guard let url = components.url else {
            throw ControlPlaneFailure.undecodable
        }
        return url
    }

    /// 判定 HTTP 请求目标（形如 `/callback?code=..&state=..`）。
    public func outcome(of requestTarget: String) -> AuthorizationCallback {
        guard let components = URLComponents(string: requestTarget),
              components.path == redirectURI.path else {
            return .unrelated
        }
        let items = components.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        guard value("state") == state else {
            return .unrelated
        }
        if let code = value("code"), !code.isEmpty {
            return .granted(code: code)
        }
        return value("error") == nil ? .unrelated : .denied
    }
}

/// 向后端兑换或续期桌面会话。客户端不持有任何身份服务密钥。
public enum DesktopSessionRequest {
    static let path = "/api/v1/desktop-auth/token"

    public static func exchange(
        apiBase: URL,
        code: String,
        authorization: BrowserAuthorization,
        requestID: String
    ) throws -> PreparedRequest {
        try prepare(apiBase: apiBase, requestID: requestID, body: [
            "grantType": "authorization_code",
            "code": code,
            "codeVerifier": authorization.pkce.verifier,
            "redirectUri": authorization.redirectURI.absoluteString
        ])
    }

    public static func refresh(apiBase: URL, refreshToken: String, requestID: String) throws -> PreparedRequest {
        try prepare(apiBase: apiBase, requestID: requestID, body: [
            "grantType": "refresh_token",
            "refreshToken": refreshToken
        ])
    }

    private static func prepare(apiBase: URL, requestID: String, body: [String: String]) throws -> PreparedRequest {
        try ControlPlaneRequest.prepare(
            baseURL: apiBase,
            method: .post,
            path: path,
            body: try JSONSerialization.data(withJSONObject: body),
            token: nil,
            requestID: requestID
        )
    }
}

public enum DesktopSessionParser {
    public static func parse(_ data: Data, now: Date) throws -> IdentityGrant {
        let document = try ResponseInterpreter.envelope(data, as: SessionDocument.self)
        return IdentityGrant(
            accessToken: document.accessToken,
            refreshToken: document.refreshToken,
            expiresAt: now.addingTimeInterval(TimeInterval(document.expiresIn))
        )
    }
}

private struct SessionDocument: Decodable {
    var accessToken: String
    var refreshToken: String
    var expiresIn: Int
}

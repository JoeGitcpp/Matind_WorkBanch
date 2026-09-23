import AppKit
import Foundation
import MatindCore
import Observation

enum SessionPhase: Equatable {
    case restoring
    case signedOut
    case unavailable
    case signedIn
}

/// 浏览器授权登录进度。
enum BrowserSignIn: Equatable {
    case idle
    case waiting
    case failed(String)
}

@Observable
@MainActor
final class AuthState {
    private(set) var phase: SessionPhase = .restoring
    private(set) var currentUser: User?
    private(set) var notice: String?
    private(set) var signIn: BrowserSignIn = .idle

    var isAuthenticated: Bool {
        phase == .signedIn
    }

    /// 用户在浏览器里完成授权的最长等待时间。
    private static let signInTimeout: TimeInterval = 300

    private let sessions = SessionCredentialStore()
    private let legacyTokens = AuthService()
    private let transport = ControlPlaneTransport.shared
    private let receiver = BrowserSignInReceiver()
    private var signInTask: Task<Void, Never>?
    private var refreshing = false

    init() {
        NotificationCenter.default.addObserver(
            forName: .unauthorizedResponse,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.recoverFromUnauthorized()
            }
        }
        Task { await restore() }
    }

    /// 打开系统浏览器授权；网页确认后回跳本机，再向后端兑换会话。
    func signInWithBrowser() {
        guard signIn != .waiting else { return }
        guard let webBase = AppConfig.webBase, let apiBase = AppConfig.apiBase else {
            signIn = .failed("构建配置缺少网页或接口地址")
            return
        }
        notice = nil
        signIn = .waiting
        signInTask = Task { await runBrowserSignIn(webBase: webBase, apiBase: apiBase) }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        receiver.stop()
        signIn = .idle
    }

    /// 注册在网页完成，客户端不收集密码。
    func openRegistration() {
        guard let webBase = AppConfig.webBase,
              let url = URL(string: "login?mode=register", relativeTo: webBase) else { return }
        NSWorkspace.shared.open(url)
    }

    func retry() async {
        phase = .restoring
        notice = nil
        await restore()
    }

    func logout() {
        sessions.clear()
        legacyTokens.clearToken()
        currentUser = nil
        notice = nil
        phase = .signedOut
        Task { await APIClient.shared.setToken(nil) }
    }

    private func runBrowserSignIn(webBase: URL, apiBase: URL) async {
        defer { receiver.stop() }
        do {
            let redirect = try await receiver.start()
            let authorization = BrowserAuthorization(redirectURI: redirect)
            let page = try authorization.authorizeURL(webBase: webBase)
            let code = try await receiver.awaitCode(for: authorization, timeout: Self.signInTimeout) {
                DispatchQueue.main.async { NSWorkspace.shared.open(page) }
            }
            let request = try DesktopSessionRequest.exchange(
                apiBase: apiBase,
                code: code,
                authorization: authorization,
                requestID: UUID().uuidString
            )
            try await adopt(try await transport.desktopSession(for: request))
            signIn = .idle
        } catch is CancellationError {
            signIn = .idle
        } catch {
            signIn = .failed(Self.signInMessage(error))
        }
    }

    private static func signInMessage(_ error: Error) -> String {
        switch error {
        case BrowserSignInFailure.denied:
            return "已在网页上取消授权"
        case BrowserSignInFailure.timedOut:
            return "等待浏览器授权超时，请重试"
        case BrowserSignInFailure.unbound:
            return "无法在本机开启登录回调端口"
        case ControlPlaneFailure.unauthenticated:
            return "授权已失效，请重新登录"
        case let failure as ControlPlaneFailure:
            return failure.message
        default:
            return "登录失败：\(error.localizedDescription)"
        }
    }

    private func restore() async {
        legacyTokens.clearToken()
        guard let stored = sessions.load() else {
            phase = .signedOut
            return
        }
        do {
            let session = try await refreshed(stored)
            try await enter(session)
        } catch ControlPlaneFailure.unreachable {
            notice = ControlPlaneFailure.unreachable.message
            phase = .unavailable
        } catch {
            sessions.clear()
            notice = (error as? ControlPlaneFailure)?.message
            phase = .signedOut
        }
    }

    private func adopt(_ grant: IdentityGrant) async throws {
        let session = SessionTokens(
            accessToken: grant.accessToken,
            refreshToken: grant.refreshToken,
            expiresAt: grant.expiresAt
        )
        try sessions.save(session)
        try await enter(session)
    }

    private func enter(_ session: SessionTokens) async throws {
        await APIClient.shared.setToken(session.accessToken)
        let profile: User = try await transport.envelope(
            .get,
            path: "/api/v1/users/me",
            token: session.accessToken,
            as: User.self
        )
        currentUser = profile
        notice = nil
        phase = .signedIn
    }

    private func refreshed(_ session: SessionTokens) async throws -> SessionTokens {
        guard SessionPolicy.shouldRefresh(session, now: Date()) else { return session }
        let grant = try await renew(session.refreshToken)
        let updated = SessionTokens(
            accessToken: grant.accessToken,
            refreshToken: grant.refreshToken,
            expiresAt: grant.expiresAt
        )
        try sessions.save(updated)
        return updated
    }

    private func renew(_ refreshToken: String) async throws -> IdentityGrant {
        guard let apiBase = AppConfig.apiBase else {
            throw ControlPlaneFailure.undecodable
        }
        let request = try DesktopSessionRequest.refresh(
            apiBase: apiBase,
            refreshToken: refreshToken,
            requestID: UUID().uuidString
        )
        return try await transport.desktopSession(for: request)
    }

    private func recoverFromUnauthorized() async {
        guard phase == .signedIn, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        guard let stored = sessions.load() else {
            logout()
            notice = "登录已过期"
            return
        }
        do {
            try await adopt(try await renew(stored.refreshToken))
        } catch {
            logout()
            notice = "登录已过期"
        }
    }
}

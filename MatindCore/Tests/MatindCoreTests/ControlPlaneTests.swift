import Foundation
import Testing
@testable import MatindCore

@Suite("会话")
struct SessionPolicyTests {
    @Test("到期前一分钟内需要刷新")
    func refreshesInsideTheSkew() {
        let now = Date(timeIntervalSince1970: 1_000)
        let fresh = SessionTokens(
            accessToken: "a",
            refreshToken: "r",
            expiresAt: now.addingTimeInterval(120)
        )
        let expiring = SessionTokens(
            accessToken: "a",
            refreshToken: "r",
            expiresAt: now.addingTimeInterval(30)
        )
        #expect(SessionPolicy.shouldRefresh(fresh, now: now) == false)
        #expect(SessionPolicy.shouldRefresh(expiring, now: now))
    }

    @Test("会话响应从包装里取令牌并按有效期算到期时间")
    func parsesDesktopSession() throws {
        let json = #"{"code":0,"msg":"ok","data":{"accessToken":"access","refreshToken":"refresh","expiresIn":3600,"tokenType":"bearer"}}"#
        let grant = try DesktopSessionParser.parse(Data(json.utf8), now: Date(timeIntervalSince1970: 1))
        #expect(grant == IdentityGrant(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date(timeIntervalSince1970: 3601)
        ))
    }
}

@Suite("浏览器授权")
struct BrowserAuthorizationTests {
    private let redirect = URL(string: "http://127.0.0.1:53682/callback")!

    private func authorization() -> BrowserAuthorization {
        BrowserAuthorization(
            redirectURI: redirect,
            pkce: PKCEPair(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            state: "state-1234567890abcdef"
        )
    }

    @Test("S256 校验值符合 RFC 7636 标准向量")
    func challengeMatchesRFCVector() {
        #expect(authorization().pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("随机校验值与 state 足够长且每次不同")
    func randomValuesAreFresh() {
        let first = PKCEPair.random()
        let second = PKCEPair.random()
        #expect(first.verifier.count == 43)
        #expect(first.verifier != second.verifier)
        #expect(RandomToken.make(bytes: 24).count == 32)
    }

    @Test("授权页地址只带公开参数")
    func authorizeURL() throws {
        let url = try authorization().authorizeURL(webBase: URL(string: "http://localhost:3000")!)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(components?.path == "/desktop/authorize")
        #expect(items == [
            "code_challenge": "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
            "code_challenge_method": "S256",
            "redirect_uri": "http://127.0.0.1:53682/callback",
            "state": "state-1234567890abcdef"
        ])
    }

    @Test("回跳判定：同 state 才接受，其它请求忽略")
    func callbackOutcome() {
        let auth = authorization()
        #expect(auth.outcome(of: "/callback?code=c1&state=state-1234567890abcdef") == .granted(code: "c1"))
        #expect(auth.outcome(of: "/callback?error=access_denied&state=state-1234567890abcdef") == .denied)
        #expect(auth.outcome(of: "/callback?code=c1&state=forged") == .unrelated)
        #expect(auth.outcome(of: "/favicon.ico") == .unrelated)
        #expect(auth.outcome(of: "/callback?state=state-1234567890abcdef") == .unrelated)
    }

    @Test("兑换请求不带登录令牌，携带 verifier 与回跳地址")
    func exchangeRequest() throws {
        let request = try DesktopSessionRequest.exchange(
            apiBase: URL(string: "http://127.0.0.1:8800")!,
            code: "c1",
            authorization: authorization(),
            requestID: "req"
        )
        #expect(request.method == .post)
        #expect(request.url.absoluteString == "http://127.0.0.1:8800/api/v1/desktop-auth/token")
        #expect(request.headers["Authorization"] == nil)
        let body = try JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: String]
        #expect(body == [
            "grantType": "authorization_code",
            "code": "c1",
            "codeVerifier": "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
            "redirectUri": "http://127.0.0.1:53682/callback"
        ])
    }

    @Test("续期请求走后端代理")
    func refreshRequest() throws {
        let request = try DesktopSessionRequest.refresh(
            apiBase: URL(string: "https://api.matind.com")!,
            refreshToken: "r1",
            requestID: "req"
        )
        #expect(request.url.absoluteString == "https://api.matind.com/api/v1/desktop-auth/token")
        let body = try JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: String]
        #expect(body == ["grantType": "refresh_token", "refreshToken": "r1"])
    }
}

@Suite("控制面响应")
struct ResponseInterpretationTests {
    @Test("请求带编号，删除可以带正文")
    func preparesDelete() throws {
        let request = try ControlPlaneRequest.prepare(
            baseURL: URL(string: "http://localhost:8800")!,
            method: .delete,
            path: "/api/v1/workbenches/7/boards/9",
            body: Data("{}".utf8),
            token: "token",
            requestID: "req-1"
        )
        #expect(request.method == .delete)
        #expect(request.headers["x-request-id"] == "req-1")
        #expect(request.headers["Authorization"] == "Bearer token")
        #expect(request.body == Data("{}".utf8))
    }

    @Test("412 映射为版本冲突")
    func conflict() throws {
        let body = #"{"code":"BOARD_PRECONDITION_FAILED","message":"stale","requestId":"r","fieldErrors":{},"precondition":"access_revision","currentRevision":"4"}"#
        let failure = ResponseInterpreter.failure(
            statusCode: 412,
            headers: ["x-request-id": "r"],
            body: Data(body.utf8)
        )
        #expect(failure == .conflict(precondition: "access_revision", currentRevision: "4"))
    }

    @Test("处理中的 503 带操作编号")
    func pending() throws {
        let body = #"{"schemaVersion":"1","outcome":"pending","operationId":"op-9"}"#
        let failure = ResponseInterpreter.failure(
            statusCode: 503,
            headers: [:],
            body: Data(body.utf8)
        )
        #expect(failure == .pending(operationId: "op-9"))
    }

    @Test("包装响应取出 data")
    func envelope() throws {
        let body = #"{"code":0,"msg":"ok","data":{"id":7,"name":"工作室"}}"#
        let item = try ResponseInterpreter.envelope(Data(body.utf8), as: NamedItem.self)
        #expect(item == NamedItem(id: 7, name: "工作室"))
    }

    @Test("加载状态用空和失败区分")
    func loadPhase() {
        let empty = LoadPhase<[Int]>.resolve([Int]())
        let loaded = LoadPhase<[Int]>.resolve([1])
        #expect(empty == .empty)
        #expect(loaded == .loaded([1]))
    }
}

private struct NamedItem: Decodable, Equatable {
    let id: Int
    let name: String
}

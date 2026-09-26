import Foundation
import Testing
@testable import MatindCore

@Suite("多维表嵌入")
struct HyperTableEmbedTests {
    @Test("嵌入会话不能导航到同主机的其它端口或其它来源")
    func navigationRequiresTheExactOrigin() throws {
        let page = try #require(URL(string: "http://localhost:3000/zh/embed/hyper-table"))
        #expect(HyperTableLocation.hasSameOrigin(URL(string: "http://localhost:3000/other")!, as: page))
        #expect(!HyperTableLocation.hasSameOrigin(URL(string: "http://localhost:3001/other")!, as: page))
        #expect(!HyperTableLocation.hasSameOrigin(URL(string: "https://localhost:3000/other")!, as: page))
        #expect(!HyperTableLocation.hasSameOrigin(URL(string: "http://other.local:3000/other")!, as: page))
        #expect(!HyperTableLocation.hasSameOrigin(URL(string: "about:blank")!, as: page))
        #expect(!HyperTableLocation.hasSameOrigin(URL(string: "file:///tmp/page.html")!, as: page))
    }

    @Test("默认端口与显式标准端口是同一来源，凭据地址被拒绝")
    func canonicalOriginPorts() throws {
        let page = try #require(URL(string: "https://matind.com/zh/embed/hyper-table"))
        #expect(HyperTableLocation.hasSameOrigin(URL(string: "https://matind.com:443/other")!, as: page))
        #expect(!HyperTableLocation.hasSameOrigin(URL(string: "https://matind.com:444/other")!, as: page))
        #expect(!HyperTableLocation.hasSameOrigin(URL(string: "https://user@matind.com/other")!, as: page))
        #expect(!HyperTableLocation.hasSameOrigin(URL(string: "about:blank")!, as: URL(string: "about:blank")!))
    }

    @Test("嵌入页使用网页端种类名，并带上已绑定的表")
    func locationUsesTheWebKind() throws {
        let base = try #require(URL(string: "http://localhost:3000"))
        let bound = try #require(HyperTableLocation.page(webBase: base, datasetId: "ds 1"))
        let parts = try #require(URLComponents(url: bound, resolvingAgainstBaseURL: false))
        #expect(parts.path == "/zh/embed/hyper-table")
        #expect(parts.queryItems == [URLQueryItem(name: "datasetId", value: "ds 1")])

        let unbound = try #require(HyperTableLocation.page(webBase: base, datasetId: ""))
        let unboundParts = try #require(URLComponents(url: unbound, resolvingAgainstBaseURL: false))
        #expect(unboundParts.queryItems == nil)
        #expect(BoardWidgetKind.hyperTable.rawValue == "HyperTable")
    }

    @Test("访问令牌只取出主体和过期时间")
    func claimsIgnoreTheSignature() throws {
        let payload: [String: Any] = ["sub": "user-1", "exp": 2_000_000_000]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let encoded = body.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let snapshot = try #require(AccessTokenClaims.snapshot(of: "e30.\(encoded).sig"))
        #expect(snapshot.subject == "user-1")
        #expect(snapshot.expiresAt == Date(timeIntervalSince1970: 2_000_000_000))
        #expect(AccessTokenClaims.snapshot(of: "not-a-token") == nil)
    }
}

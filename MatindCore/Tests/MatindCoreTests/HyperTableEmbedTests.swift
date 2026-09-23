import Foundation
import Testing
@testable import MatindCore

@Suite("多维表嵌入")
struct HyperTableEmbedTests {
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

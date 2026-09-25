import CryptoKit
import Foundation
import Testing
@testable import MatindCore

@Suite("本机浏览器人工登录请求")
struct LocalProfileCommandTests {
    @Test("固定字段的规范字节可跨语言验签，完整body均被签名")
    func canonicalSignature() throws {
        let device = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let connection = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let nonce = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
        let command = try LocalProfileCommand(deviceId: device, workspaceId: 300_000_000_000_000_001, connectionId: connection, url: URL(string: "https://example.com/")!, nonce: nonce, signedAt: "2026-09-26T00:00:00Z")
        let expected = #"{"body":{"connectionId":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","url":"https://example.com/","workspaceId":"300000000000000001"},"contractVersion":"external-action-v1","deviceId":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","method":"POST","nonce":"cccccccc-cccc-cccc-cccc-cccccccccccc","path":"/browser/open-profile","signedAt":"2026-09-26T00:00:00Z"}"#
        #expect(String(data: command.canonicalPayload, encoding: .utf8) == expected)
        let key = Curve25519.Signing.PrivateKey()
        let envelope = try JSONSerialization.jsonObject(with: command.signed(privateKey: key.rawRepresentation)) as! [String: Any]
        let signature = (envelope["signature"] as! String).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        #expect(key.publicKey.isValidSignature(Data(base64Encoded: signature + "==")!, for: command.canonicalPayload))
    }
}

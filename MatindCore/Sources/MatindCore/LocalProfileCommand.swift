import CryptoKit
import Foundation

/// A deliberately restricted JCS schema: ASCII keys/values, decimal identifiers as strings.
/// No arbitrary JSON is accepted; the known canonical byte vector is tested cross-language.
public struct LocalProfileCommand: Sendable {
    public let canonicalPayload: Data

    public init(deviceId: UUID, workspaceId: Int64, connectionId: UUID, url: URL,
                nonce: UUID = UUID(), signedAt: String = ISO8601DateFormatter().string(from: Date())) throws {
        let absolute = url.absoluteString
        guard workspaceId > 0,
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              absolute.utf8.allSatisfy({ $0 >= 32 && $0 < 127 }),
              signedAt.utf8.allSatisfy({ $0 >= 32 && $0 < 127 }) else { throw BrowserPolicyError.invalidScope }
        let payload: [String: Any] = [
            "contractVersion": "external-action-v1", "deviceId": deviceId.uuidString.lowercased(),
            "method": "POST", "path": "/browser/open-profile", "nonce": nonce.uuidString.lowercased(),
            "signedAt": signedAt, "body": ["workspaceId": String(workspaceId),
                "connectionId": connectionId.uuidString.lowercased(), "url": absolute]
        ]
        canonicalPayload = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    public func signed(privateKey: Data) throws -> Data {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKey)
        let signature = try key.signature(for: canonicalPayload).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return try JSONSerialization.data(withJSONObject: [
            "payload": JSONSerialization.jsonObject(with: canonicalPayload), "signature": signature
        ], options: [.sortedKeys, .withoutEscapingSlashes])
    }
}

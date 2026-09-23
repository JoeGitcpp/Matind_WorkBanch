import Foundation

/// 从访问令牌里取出嵌入页需要的主体和过期时间。不校验签名，签名由签发方负责。
public enum AccessTokenClaims {
    public struct Snapshot: Equatable, Sendable {
        public var subject: String
        public var expiresAt: Date

        public init(subject: String, expiresAt: Date) {
            self.subject = subject
            self.expiresAt = expiresAt
        }
    }

    public static func snapshot(of token: String) -> Snapshot? {
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let data = Base64URL.decode(String(parts[1])),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = object["sub"] as? String,
              !subject.isEmpty,
              let exp = object["exp"] as? NSNumber
        else {
            return nil
        }
        return Snapshot(
            subject: subject,
            expiresAt: Date(timeIntervalSince1970: exp.doubleValue)
        )
    }
}

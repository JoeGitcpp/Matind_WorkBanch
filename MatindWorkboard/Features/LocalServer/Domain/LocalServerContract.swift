import Foundation
import CryptoKit

/// 本机服务器和网页控制面共用的契约常量。
enum LocalServerContract {
    static let version = "local-server-v1"
    static let pendingStatus = "pending"
    static let publicKeyAlgorithm = "ed25519"
    static let maxGrantTTLSeconds = 900
    static let maxWorkspaceId: Int64 = 9_007_199_254_740_991

    static func validWorkspace(_ id: Int64) -> Bool {
        id > 0 && id <= maxWorkspaceId
    }

    static func acceptsGrantTTL(_ seconds: Int) -> Bool {
        (1...maxGrantTTLSeconds).contains(seconds)
    }
}

/// 服务器可以授给工作区的能力。工作区权限 `local.device.manage` 不在这里，它只能收窄或解除。
enum LocalCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case blueprintRun = "local.blueprint.run"
    case healthRead = "local.health.read"
    case auditRead = "local.audit.read"
    case deviceRevoke = "local.device.revoke"
    case browserObserve = "local.browser.observe"
    case browserNavigate = "local.browser.navigate"
    case browserFill = "local.browser.fill"
    case browserClick = "local.browser.click"

    var title: String {
        switch self {
        case .blueprintRun: "运行蓝图"
        case .healthRead: "读取健康状态"
        case .auditRead: "读取审计"
        case .deviceRevoke: "解除设备"
        case .browserObserve: "读取浏览器页面"
        case .browserNavigate: "打开授权网站"
        case .browserFill: "填写网页字段（需操作审批）"
        case .browserClick: "点击网页控件（需操作审批）"
        }
    }
}

enum DeviceKeyText {
    /// Ed25519 公钥的无填充 base64url，长度固定 43。
    static func encode(_ raw: Data) -> String? {
        guard raw.count == 32 else { return nil }
        let text = raw.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard isPublicKey(text) else { return nil }
        return text
    }

    static func isPublicKey(_ text: String) -> Bool {
        text.count == 43 && text.allSatisfy(isKeyCharacter)
    }

    private static func isKeyCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || character == "_" || character == "-")
    }
}

enum ServerHostLabel {
    static func current() -> String {
        sanitize(ProcessInfo.processInfo.hostName)
    }

    static func sanitize(_ raw: String) -> String {
        let scalars = raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let trimmed = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Matind" }
        return String(trimmed.prefix(80))
    }

    static func clientVersion(from raw: String) -> String {
        isSemver(raw) ? raw : "1.0.0"
    }

    static func isSemver(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy(\.isNumber)
        }
    }
}

struct DevicePublicKeyDocument: Codable, Equatable, Sendable {
    var algorithm: String
    var publicKey: String
}

/// 登记文档。没有工作区字段，服务器不能在登记时改挂到某个工作区。
struct ServerRegistration: Codable, Equatable, Sendable {
    var contractVersion: String
    var deviceId: UUID
    var label: String
    var clientVersion: String
    var status: String
    var publicKey: DevicePublicKeyDocument
}

enum RegistrationDocumentError: Error, Equatable {
    case malformed
    case workspaceBindingForbidden
    case contractMismatch
}

enum ServerRegistrationDocument {
    static func make(
        deviceId: UUID,
        label: String,
        clientVersion: String,
        publicKey: String
    ) -> ServerRegistration? {
        guard ServerHostLabel.isSemver(clientVersion),
              validLabel(label),
              DeviceKeyText.isPublicKey(publicKey) else {
            return nil
        }
        return ServerRegistration(
            contractVersion: LocalServerContract.version,
            deviceId: deviceId,
            label: label,
            clientVersion: clientVersion,
            status: LocalServerContract.pendingStatus,
            publicKey: DevicePublicKeyDocument(
                algorithm: LocalServerContract.publicKeyAlgorithm,
                publicKey: publicKey
            )
        )
    }

    static func parse(_ data: Data) throws -> ServerRegistration {
        let object = try jsonObject(data)
        try refuseWorkspaceBinding(object)
        let registration = try decode(data)
        try acceptContract(registration)
        return registration
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RegistrationDocumentError.malformed
        }
        return object
    }

    private static func refuseWorkspaceBinding(_ object: [String: Any]) throws {
        if object["workspaceId"] != nil || object["workspace_id"] != nil {
            throw RegistrationDocumentError.workspaceBindingForbidden
        }
    }

    private static func decode(_ data: Data) throws -> ServerRegistration {
        guard let registration = try? JSONDecoder().decode(ServerRegistration.self, from: data) else {
            throw RegistrationDocumentError.malformed
        }
        return registration
    }

    private static func acceptContract(_ registration: ServerRegistration) throws {
        guard registration.contractVersion == LocalServerContract.version,
              registration.status == LocalServerContract.pendingStatus,
              registration.publicKey.algorithm == LocalServerContract.publicKeyAlgorithm,
              DeviceKeyText.isPublicKey(registration.publicKey.publicKey),
              validLabel(registration.label),
              ServerHostLabel.isSemver(registration.clientVersion) else {
            throw RegistrationDocumentError.contractMismatch
        }
    }

    private static func validLabel(_ label: String) -> Bool {
        guard (1...80).contains(label.count),
              label == label.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !label.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

extension Curve25519.Signing.PrivateKey {
    /// 只导出公钥文本。私钥留在钥匙串。
    func publicKeyText() -> String? {
        DeviceKeyText.encode(publicKey.rawRepresentation)
    }
}

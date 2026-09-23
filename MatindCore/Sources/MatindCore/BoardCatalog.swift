import Foundation

public enum BoardContentCapability: String, Codable, Equatable, Sendable {
    case none
    case read
    case fill
    case edit

    /// 只有编辑能力可以改布局。填写和只读都停在查看。
    public var permitsEditing: Bool { self == .edit }
}

public enum BoardSettingsCapability: String, Codable, Equatable, Sendable {
    case none
    case manage

    public var permitsManagement: Bool { self == .manage }
}

public struct BoardSummary: Codable, Equatable, Sendable, Identifiable {
    public var schemaVersion: String
    public var id: String
    public var workspaceId: String
    public var name: String
    public var layoutVersion: String
    public var accessRevision: String
    public var authorityKind: String
    public var authorityReceiptId: String
    public var contentCapability: BoardContentCapability
    public var settingsCapability: BoardSettingsCapability
}

public struct BoardCatalog: Codable, Equatable, Sendable {
    public var schemaVersion: String
    public var workspaceId: String
    public var boards: [BoardSummary]
}

public struct BoardMutationReceipt: Codable, Equatable, Sendable {
    public var schemaVersion: String
    public var outcome: String
    public var operationId: String
    public var board: BoardSummary
}

public struct BoardDeleteReceipt: Codable, Equatable, Sendable {
    public var schemaVersion: String
    public var outcome: String
    public var operationId: String
    public var boardId: String
}

public enum BoardPageName {
    /// 和网页端一致：取已有「新页面 N」的最大序号再加一。
    public static func next(among names: [String]) -> String {
        let highest = names.reduce(0) { partial, name in
            max(partial, sequenceNumber(in: name))
        }
        return "新页面 \(highest + 1)"
    }

    private static func sequenceNumber(in name: String) -> Int {
        let prefix = "新页面 "
        guard name.hasPrefix(prefix) else { return 0 }
        let suffix = String(name.dropFirst(prefix.count))
        guard let number = Int(suffix), number >= 0, String(number) == suffix else { return 0 }
        return number
    }
}

public enum BoardDocuments {
    public static func create(name: String, idempotencyKey: UUID) throws -> Data {
        try validateName(name)
        return try object([
            "schemaVersion": "1",
            "name": name,
            "idempotencyKey": canonical(idempotencyKey)
        ])
    }

    public static func rename(name: String, idempotencyKey: UUID) throws -> Data {
        try create(name: name, idempotencyKey: idempotencyKey)
    }

    public static func delete(
        expectedName: String,
        expectedAccessRevision: String,
        idempotencyKey: UUID,
        reason: String?
    ) throws -> Data {
        try validateName(expectedName)
        guard canonicalRevision(expectedAccessRevision) else {
            throw ControlPlaneFailure.invalid(fields: ["expectedAccessRevision": ["必须是规范的非负十进制版本"]])
        }
        var fields = [
            "schemaVersion": "1",
            "expectedName": expectedName,
            "expectedAccessRevision": expectedAccessRevision,
            "idempotencyKey": canonical(idempotencyKey)
        ]
        if let reason {
            try validateReason(reason)
            fields["reason"] = reason
        }
        return try object(fields)
    }

    private static func validateName(_ name: String) throws {
        guard !name.isEmpty,
              name == name.trimmingCharacters(in: .whitespacesAndNewlines),
              name.count <= 255 else {
            throw ControlPlaneFailure.invalid(fields: ["name": ["名称无效"]])
        }
    }

    private static func validateReason(_ reason: String) throws {
        guard !reason.isEmpty,
              reason == reason.trimmingCharacters(in: .whitespacesAndNewlines),
              reason.count <= 500 else {
            throw ControlPlaneFailure.invalid(fields: ["reason": ["原因无效"]])
        }
    }

    private static func canonicalRevision(_ value: String) -> Bool {
        guard let number = Int64(value), number >= 0 else { return false }
        return String(number) == value
    }

    private static func canonical(_ key: UUID) -> String {
        key.uuidString.lowercased()
    }

    private static func object(_ fields: [String: String]) throws -> Data {
        try JSONSerialization.data(withJSONObject: fields)
    }
}

public enum BoardReceiptParser {
    public static func catalog(_ data: Data) throws -> BoardCatalog {
        let catalog = try decode(BoardCatalog.self, from: data)
        guard catalog.schemaVersion == "1" else { throw ControlPlaneFailure.undecodable }
        return catalog
    }

    public static func mutation(_ data: Data) throws -> BoardMutationReceipt {
        let receipt = try decode(BoardMutationReceipt.self, from: data)
        guard receipt.schemaVersion == "1", accepted(receipt.outcome) else {
            throw ControlPlaneFailure.undecodable
        }
        return receipt
    }

    public static func deletion(_ data: Data) throws -> BoardDeleteReceipt {
        let receipt = try decode(BoardDeleteReceipt.self, from: data)
        guard receipt.schemaVersion == "1", accepted(receipt.outcome) else {
            throw ControlPlaneFailure.undecodable
        }
        return receipt
    }

    private static func accepted(_ outcome: String) -> Bool {
        outcome == "confirmed" || outcome == "receipt_reconciled"
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ControlPlaneFailure.undecodable
        }
    }
}

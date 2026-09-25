import Foundation

struct OwnedServer: Codable, Equatable, Sendable {
    let ownerUserId: Int64
    let deviceId: UUID
}

enum AuthorizationStatus: String, Codable, Equatable, Sendable {
    case active
    case suspended
    case revoked
}

struct WorkspaceAuthorization: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let deviceId: UUID
    let workspaceId: Int64
    var capabilities: Set<LocalCapability>
    var status: AuthorizationStatus
    var version: Int
}

enum AuthorizationDecision: Equatable, Sendable {
    case created(WorkspaceAuthorization)
    case narrowed(WorkspaceAuthorization)
    case unchanged(WorkspaceAuthorization)
    case released(WorkspaceAuthorization)
    case refused(AuthorizationRefusal)

    var writesLedger: Bool {
        switch self {
        case .created, .narrowed, .released: true
        case .unchanged, .refused: false
        }
    }
}

enum AuthorizationRefusal: Equatable, Sendable {
    case notOwner
    case invalidWorkspace
    case emptyCapabilities
    case expansionForbidden
    case missing
}

struct CapabilityGrant: Equatable, Sendable {
    let authorizationId: UUID
    let authorizationVersion: Int
    let capabilities: Set<LocalCapability>
    let ttlSeconds: Int
}

enum GrantDecision: Equatable, Sendable {
    case issued(CapabilityGrant)
    case refused(GrantRefusal)
}

enum GrantRefusal: Equatable, Sendable {
    case ttlExceeded
    case emptyCapabilities
    case authorizationMissing
    case authorizationInactive
    case capabilitiesExceeded
}

/// 比较两套能力：相同、严格缩小，或拒绝。
enum CapabilityRevision: Equatable {
    case identical
    case subset(Set<LocalCapability>)
    case empty
    case expanded

    static func classify(
        current: Set<LocalCapability>,
        proposed: Set<LocalCapability>
    ) -> CapabilityRevision {
        if proposed.isEmpty { return .empty }
        if proposed == current { return .identical }
        if proposed.isSubset(of: current) { return .subset(proposed) }
        return .expanded
    }
}

/// 所有者控制台上的授权账本。短授权必须落在仍然有效的授权里面。
struct AuthorizationLedger: Codable, Equatable, Sendable {
    var server: OwnedServer
    private(set) var records: [WorkspaceAuthorization]

    init(server: OwnedServer, records: [WorkspaceAuthorization] = []) {
        self.server = server
        self.records = records
    }

    func activeRecords() -> [WorkspaceAuthorization] {
        records.filter { $0.status == .active }
    }

    /// Adopt only the result of an owner-submitted request, preserving the server's ID/version.
    mutating func adoptConfirmed(_ record: WorkspaceAuthorization, requested: Set<LocalCapability>) -> Bool {
        guard record.deviceId == server.deviceId, LocalServerContract.validWorkspace(record.workspaceId),
              record.version > 0, record.capabilities == requested else { return false }
        if let existing = records.first(where: { $0.workspaceId == record.workspaceId && $0.status == .active }),
           !record.capabilities.isSubset(of: existing.capabilities) { return false }
        records.removeAll { $0.id == record.id || ($0.workspaceId == record.workspaceId && $0.status == .active) }
        records.append(record)
        return true
    }

    mutating func propose(
        actorUserId: Int64,
        workspaceId: Int64,
        capabilities: Set<LocalCapability>
    ) -> AuthorizationDecision {
        guard actorUserId == server.ownerUserId else {
            return .refused(.notOwner)
        }
        guard LocalServerContract.validWorkspace(workspaceId) else {
            return .refused(.invalidWorkspace)
        }
        guard let active = activeRecord(workspaceId: workspaceId) else {
            return create(workspaceId: workspaceId, capabilities: capabilities)
        }
        return revise(active, to: capabilities)
    }

    mutating func release(actorUserId: Int64, authorizationId: UUID) -> AuthorizationDecision {
        guard actorUserId == server.ownerUserId else {
            return .refused(.notOwner)
        }
        guard let index = records.firstIndex(where: { $0.id == authorizationId }) else {
            return .refused(.missing)
        }
        if records[index].status == .revoked {
            return .unchanged(records[index])
        }
        records[index].status = .revoked
        return .released(records[index])
    }

    func issueGrant(
        authorizationId: UUID,
        capabilities: Set<LocalCapability>,
        ttlSeconds: Int
    ) -> GrantDecision {
        guard LocalServerContract.acceptsGrantTTL(ttlSeconds) else {
            return .refused(.ttlExceeded)
        }
        guard !capabilities.isEmpty else {
            return .refused(.emptyCapabilities)
        }
        guard let record = records.first(where: { $0.id == authorizationId }) else {
            return .refused(.authorizationMissing)
        }
        guard record.status == .active else {
            return .refused(.authorizationInactive)
        }
        guard capabilities.isSubset(of: record.capabilities) else {
            return .refused(.capabilitiesExceeded)
        }
        return .issued(CapabilityGrant(
            authorizationId: record.id,
            authorizationVersion: record.version,
            capabilities: capabilities,
            ttlSeconds: ttlSeconds
        ))
    }

    private func activeRecord(workspaceId: Int64) -> WorkspaceAuthorization? {
        records.first { $0.workspaceId == workspaceId && $0.status == .active }
    }

    private mutating func create(
        workspaceId: Int64,
        capabilities: Set<LocalCapability>
    ) -> AuthorizationDecision {
        guard !capabilities.isEmpty else {
            return .refused(.emptyCapabilities)
        }
        let record = WorkspaceAuthorization(
            id: UUID(),
            deviceId: server.deviceId,
            workspaceId: workspaceId,
            capabilities: capabilities,
            status: .active,
            version: 1
        )
        records.append(record)
        return .created(record)
    }

    private mutating func revise(
        _ current: WorkspaceAuthorization,
        to capabilities: Set<LocalCapability>
    ) -> AuthorizationDecision {
        switch CapabilityRevision.classify(current: current.capabilities, proposed: capabilities) {
        case .identical:
            return .unchanged(current)
        case .subset(let narrowed):
            return storeNarrowed(current, capabilities: narrowed)
        case .empty:
            return .refused(.emptyCapabilities)
        case .expanded:
            return .refused(.expansionForbidden)
        }
    }

    private mutating func storeNarrowed(
        _ current: WorkspaceAuthorization,
        capabilities: Set<LocalCapability>
    ) -> AuthorizationDecision {
        guard let index = records.firstIndex(where: { $0.id == current.id }) else {
            return .refused(.missing)
        }
        records[index].capabilities = capabilities
        records[index].version += 1
        return .narrowed(records[index])
    }
}

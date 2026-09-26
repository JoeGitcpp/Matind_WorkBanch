import Foundation
import MatindCore
import Observation

struct ServiceAuditRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var moduleId: String
    var command: ServiceCommand
    var from: ServiceInstancePhase
    var to: ServiceInstancePhase
    var at: Date
}

private struct ServiceCatalogSnapshot: Codable, Equatable {
    var phases: [String: ServiceInstancePhase]
    var audit: [ServiceAuditRecord]
}

/// 本机已安装服务的阶段和审计。阶段变化只走 ServiceLifecycle。
@Observable
@MainActor
final class ServiceCatalogState {
    private(set) var phases: [String: ServiceInstancePhase] = [:]
    private(set) var audit: [ServiceAuditRecord] = []
    private(set) var notice: String?

    private let storage: LocalStorage
    private let key: String

    init(storage: LocalStorage = .shared, key: String = AppConfig.serviceCatalogKey) {
        self.storage = storage
        self.key = key
        restore()
    }

    func phase(of moduleId: String) -> ServiceInstancePhase {
        phases[moduleId] ?? .available
    }

    func perform(_ action: ServiceCardAction, on module: ServiceModuleManifest) {
        notice = nil
        switch action {
        case .install:
            install(module)
        case .cancelInstall:
            apply(.cancelInstall, to: module.moduleId)
        case .enable:
            enable(module.moduleId)
        case .stop:
            apply(.stop, to: module.moduleId)
        case .uninstall:
            uninstall(module.moduleId)
        case .retry:
            enable(module.moduleId)
        }
    }

    private func install(_ module: ServiceModuleManifest) {
        guard apply(.beginInstall, to: module.moduleId) else { return }
        switch PlatformModuleTrust.verify(moduleId: module.moduleId, version: module.version, digest: module.digest) {
        case .trusted:
            apply(.acceptPackage, to: module.moduleId)
        case .rejected:
            apply(.rejectPackage, to: module.moduleId)
            notice = "安装包校验失败，未安装"
        }
    }

    private func enable(_ moduleId: String) {
        let command: ServiceCommand = phase(of: moduleId) == .failed ? .retry : .enable
        guard apply(command, to: moduleId) else { return }
        apply(.finishStart, to: moduleId)
    }

    private func uninstall(_ moduleId: String) {
        guard apply(.beginRemoval, to: moduleId) else { return }
        apply(.finishRemoval, to: moduleId)
    }

    @discardableResult
    private func apply(_ command: ServiceCommand, to moduleId: String) -> Bool {
        let current = phase(of: moduleId)
        guard let transition = ServiceLifecycle.next(phase: current, command: command) else { return false }
        phases[moduleId] = transition.phase
        audit.append(ServiceAuditRecord(
            id: UUID(),
            moduleId: moduleId,
            command: command,
            from: current,
            to: transition.phase,
            at: Date()
        ))
        persist()
        return true
    }

    private func restore() {
        guard let snapshot = storage.get(ServiceCatalogSnapshot.self, forKey: key) else { return }
        phases = snapshot.phases
        audit = snapshot.audit
    }

    private func persist() {
        storage.set(ServiceCatalogSnapshot(phases: phases, audit: audit), forKey: key)
    }
}

enum ServiceCardAction: Equatable, Hashable, Sendable {
    case install
    case cancelInstall
    case enable
    case stop
    case uninstall
    case retry
}

enum ServiceCardCopy {
    static func title(for command: ServiceCommand) -> String {
        switch command {
        case .beginInstall: "安装"
        case .cancelInstall: "取消安装"
        case .enable: "启用"
        case .stop: "停用"
        case .beginRemoval: "卸载"
        case .retry: "重试"
        case .acceptPackage, .rejectPackage, .finishStart, .failStart, .finishRemoval:
            ""
        }
    }

    static func action(for command: ServiceCommand) -> ServiceCardAction? {
        switch command {
        case .beginInstall: .install
        case .cancelInstall: .cancelInstall
        case .enable: .enable
        case .stop: .stop
        case .beginRemoval: .uninstall
        case .retry: .retry
        case .acceptPackage, .rejectPackage, .finishStart, .failStart, .finishRemoval:
            nil
        }
    }

    static func phaseTitle(_ phase: ServiceInstancePhase) -> String {
        switch phase {
        case .available: "可安装"
        case .installing: "正在安装"
        case .installed: "已安装"
        case .starting: "正在启动"
        case .running: "运行中"
        case .degraded: "降级"
        case .stopped: "已停用"
        case .failed: "启动失败"
        case .removing: "正在卸载"
        }
    }
}

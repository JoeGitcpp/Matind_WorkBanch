import Foundation

/// 服务实例所处的阶段。卡片上能做的事由阶段决定。
public enum ServiceInstancePhase: String, Codable, Equatable, Sendable {
    case available
    case installing
    case installed
    case starting
    case running
    case degraded
    case stopped
    case failed
    case removing
}

/// 对服务实例下达的命令。安装包是否可信由调用方先判定，再传入接受或拒绝。
public enum ServiceCommand: String, Codable, Equatable, Sendable {
    case beginInstall
    case acceptPackage
    case rejectPackage
    case cancelInstall
    case enable
    case finishStart
    case failStart
    case stop
    case beginRemoval
    case finishRemoval
    case retry
}

public enum ServicePackageVerdict: Equatable, Sendable {
    case trusted
    case rejected
}

/// 平台发布的一版模块。摘要对不上就不能安装。
public struct TrustedModuleRelease: Equatable, Sendable {
    public var moduleId: String
    public var version: String
    public var digest: String

    public init(moduleId: String, version: String, digest: String) {
        self.moduleId = moduleId
        self.version = version
        self.digest = digest
    }
}

public enum PlatformModuleTrust {
    public static let releases: [TrustedModuleRelease] = [
        TrustedModuleRelease(moduleId: "matind.echo", version: "1.0.0", digest: "echo-1.0.0")
    ]

    public static func verify(moduleId: String, version: String, digest: String) -> ServicePackageVerdict {
        let matched = releases.contains { release in
            release.moduleId == moduleId && release.version == version && release.digest == digest
        }
        return matched ? .trusted : .rejected
    }
}

public struct ServiceModuleManifest: Equatable, Sendable, Identifiable {
    public var moduleId: String
    public var title: String
    public var summary: String
    public var version: String
    public var digest: String

    public var id: String { moduleId }

    public init(moduleId: String, title: String, summary: String, version: String, digest: String) {
        self.moduleId = moduleId
        self.title = title
        self.summary = summary
        self.version = version
        self.digest = digest
    }
}

public enum OfficialServiceIndex {
    public static let modules: [ServiceModuleManifest] = [
        ServiceModuleManifest(
            moduleId: "matind.echo",
            title: "回声",
            summary: "空壳模块，用来验收安装、启用、停用和卸载。",
            version: "1.0.0",
            digest: "echo-1.0.0"
        )
    ]
}

/// 一次合法的阶段变化，供审计原样记下。
public struct ServiceTransition: Equatable, Sendable {
    public var phase: ServiceInstancePhase
    public var command: ServiceCommand

    public init(phase: ServiceInstancePhase, command: ServiceCommand) {
        self.phase = phase
        self.command = command
    }
}

public enum ServiceLifecycle {
    public static func next(phase: ServiceInstancePhase, command: ServiceCommand) -> ServiceTransition? {
        guard let destination = destination(phase: phase, command: command) else { return nil }
        return ServiceTransition(phase: destination, command: command)
    }

    public static func commands(for phase: ServiceInstancePhase) -> [ServiceCommand] {
        switch phase {
        case .available:
            return [.beginInstall]
        case .installing:
            return [.cancelInstall]
        case .installed, .stopped:
            return [.enable, .beginRemoval]
        case .starting, .removing:
            return []
        case .running, .degraded:
            return [.stop]
        case .failed:
            return [.retry, .beginRemoval]
        }
    }

    private static func destination(phase: ServiceInstancePhase, command: ServiceCommand) -> ServiceInstancePhase? {
        switch phase {
        case .available:
            return availableDestination(command)
        case .installing:
            return installingDestination(command)
        case .installed, .stopped:
            return idleDestination(command)
        case .starting:
            return startingDestination(command)
        case .running, .degraded:
            return command == .stop ? .stopped : nil
        case .failed:
            return failedDestination(command)
        case .removing:
            return command == .finishRemoval ? .available : nil
        }
    }

    private static func availableDestination(_ command: ServiceCommand) -> ServiceInstancePhase? {
        command == .beginInstall ? .installing : nil
    }

    private static func installingDestination(_ command: ServiceCommand) -> ServiceInstancePhase? {
        switch command {
        case .acceptPackage:
            return .installed
        case .rejectPackage, .cancelInstall:
            return .available
        default:
            return nil
        }
    }

    private static func idleDestination(_ command: ServiceCommand) -> ServiceInstancePhase? {
        switch command {
        case .enable:
            return .starting
        case .beginRemoval:
            return .removing
        default:
            return nil
        }
    }

    private static func startingDestination(_ command: ServiceCommand) -> ServiceInstancePhase? {
        switch command {
        case .finishStart:
            return .running
        case .failStart:
            return .failed
        default:
            return nil
        }
    }

    private static func failedDestination(_ command: ServiceCommand) -> ServiceInstancePhase? {
        switch command {
        case .retry:
            return .starting
        case .beginRemoval:
            return .removing
        default:
            return nil
        }
    }
}

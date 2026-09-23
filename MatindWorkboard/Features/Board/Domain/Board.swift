import Foundation
import MatindCore

/// 工作板摘要。布局仍在后续阶段替换，这里只保留目录契约需要的字段。
struct Board: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let accessRevision: String
    let contentCapability: BoardContentCapability
    let settingsCapability: BoardSettingsCapability

    var surfaceAccess: BoardSurfaceAccess {
        contentCapability.permitsEditing ? .editable : .readOnly
    }

    init(_ summary: BoardSummary) {
        id = summary.id
        name = summary.name
        accessRevision = summary.accessRevision
        contentCapability = summary.contentCapability
        settingsCapability = summary.settingsCapability
    }

    init(
        id: String,
        name: String,
        accessRevision: String,
        contentCapability: BoardContentCapability,
        settingsCapability: BoardSettingsCapability
    ) {
        self.id = id
        self.name = name
        self.accessRevision = accessRevision
        self.contentCapability = contentCapability
        self.settingsCapability = settingsCapability
    }
}

/// 内容能力映射成界面可执行的动作，避免用布尔值一路传下去。
enum BoardSurfaceAccess: Equatable, Sendable {
    case editable
    case readOnly
}

enum PresentedFailure {
    static func message(for error: Error) -> String {
        if let failure = error as? ControlPlaneFailure {
            return failure.message
        }
        if let api = error as? APIError {
            return apiMessage(api)
        }
        return ControlPlaneFailure.unreachable.message
    }

    private static func apiMessage(_ error: APIError) -> String {
        switch error {
        case .unauthorized:
            return ControlPlaneFailure.unauthenticated.message
        case .networkError:
            return ControlPlaneFailure.unreachable.message
        case .decodingError:
            return ControlPlaneFailure.undecodable.message
        case .serverError:
            return error.localizedDescription
        }
    }
}

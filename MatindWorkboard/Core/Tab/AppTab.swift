import Foundation

/// 应用标签页类型
/// 支持工作板、设置、自动化蓝图和本机服务标签
enum AppTab: Identifiable, Hashable {
    case board(id: String, name: String)
    case settings
    case automation
    case services

    var id: String {
        switch self {
        case .board(let id, _): return "board-\(id)"
        case .settings: return "settings"
        case .automation: return "automation"
        case .services: return "services"
        }
    }

    var title: String {
        switch self {
        case .board(_, let name): return name
        case .settings: return "设置"
        case .automation: return "自动化蓝图"
        case .services: return "本机服务"
        }
    }

    var icon: String {
        switch self {
        case .board: return "rectangle.stack"
        case .settings: return "gearshape"
        case .automation: return "flowchart"
        case .services: return "server.rack"
        }
    }

    /// 是否为固定标签（不可关闭）
    var isPinned: Bool {
        false
    }

    /// 是否为工作板标签
    var isBoard: Bool {
        if case .board = self { return true }
        return false
    }
}

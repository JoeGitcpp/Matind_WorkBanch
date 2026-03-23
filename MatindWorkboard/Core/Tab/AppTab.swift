import Foundation

/// 应用标签页类型
/// 支持工作板、设置、自动化蓝图三种标签
enum AppTab: Identifiable, Hashable {
    case board(id: String, name: String)
    case settings
    case automation

    var id: String {
        switch self {
        case .board(let id, _): return "board-\(id)"
        case .settings: return "settings"
        case .automation: return "automation"
        }
    }

    var title: String {
        switch self {
        case .board(_, let name): return name
        case .settings: return "设置"
        case .automation: return "自动化蓝图"
        }
    }

    var icon: String {
        switch self {
        case .board: return "rectangle.stack"
        case .settings: return "gearshape"
        case .automation: return "flowchart"
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

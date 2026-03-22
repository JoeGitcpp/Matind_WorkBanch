import Foundation

/// 工作板上的插件实例（包含布局信息）
struct WidgetInstance: Codable, Identifiable, Sendable {
    let id: String
    let pluginId: String
    var gridX: Int       // 网格列位置（0-11）
    var gridY: Int       // 网格行位置
    var gridW: Int       // 宽度（列数，1-12）
    var gridH: Int       // 高度（行数）

    enum CodingKeys: String, CodingKey {
        case id
        case pluginId = "plugin_id"
        case gridX = "grid_x"
        case gridY = "grid_y"
        case gridW = "grid_w"
        case gridH = "grid_h"
    }

    static func defaultInstance(pluginId: String, at row: Int) -> WidgetInstance {
        WidgetInstance(id: UUID().uuidString, pluginId: pluginId, gridX: 0, gridY: row, gridW: 4, gridH: 3)
    }
}

struct BoardLayout: Codable, Sendable {
    let boardId: String
    let widgets: [WidgetInstance]
}

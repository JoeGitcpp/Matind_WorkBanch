import Foundation

/// 工作板上的一个组件。pluginId 存的是网页端种类名，例如 HyperTable。
struct WidgetInstance: Codable, Identifiable, Sendable {
    let id: String
    let pluginId: String
    var gridX: Int
    var gridY: Int
    var gridW: Int
    var gridH: Int
    var params: [String: String]

    enum CodingKeys: String, CodingKey {
        case id
        case pluginId = "plugin_id"
        case gridX = "grid_x"
        case gridY = "grid_y"
        case gridW = "grid_w"
        case gridH = "grid_h"
        case params
    }

    init(
        id: String,
        pluginId: String,
        gridX: Int,
        gridY: Int,
        gridW: Int,
        gridH: Int,
        params: [String: String] = [:]
    ) {
        self.id = id
        self.pluginId = pluginId
        self.gridX = gridX
        self.gridY = gridY
        self.gridW = gridW
        self.gridH = gridH
        self.params = params
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        pluginId = try container.decode(String.self, forKey: .pluginId)
        gridX = try container.decode(Int.self, forKey: .gridX)
        gridY = try container.decode(Int.self, forKey: .gridY)
        gridW = try container.decode(Int.self, forKey: .gridW)
        gridH = try container.decode(Int.self, forKey: .gridH)
        // 旧的本机布局没有参数，缺省为空，不能因此整份布局读不出来。
        params = try container.decodeIfPresent([String: String].self, forKey: .params) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(pluginId, forKey: .pluginId)
        try container.encode(gridX, forKey: .gridX)
        try container.encode(gridY, forKey: .gridY)
        try container.encode(gridW, forKey: .gridW)
        try container.encode(gridH, forKey: .gridH)
        try container.encode(params, forKey: .params)
    }
}

/// 工作板格子的边界。移动、缩放、拖动预览都从这里取限制，避免各处写死不同的数字。
struct BoardGridBounds: Equatable, Sendable {
    var columns: Int
    var minWidth: Int
    var minHeight: Int
    /// 与网页端组件默认最大高度保持一致。
    var maxHeight: Int

    static let standard = BoardGridBounds(columns: 12, minWidth: 2, minHeight: 1, maxHeight: 12)

    /// 一个格子起点能放下给定宽度的最右列。
    func clampedOrigin(x: Int, y: Int, width: Int) -> (x: Int, y: Int) {
        (x: max(0, min(x, columns - width)), y: max(0, y))
    }

    /// 缩放不能越过右边界，也不能小于最小占格或高于最大占格。
    func clampedSpan(x: Int, width: Int, height: Int) -> (width: Int, height: Int) {
        let widest = max(minWidth, columns - max(0, x))
        return (
            width: max(minWidth, min(widest, width)),
            height: max(minHeight, min(maxHeight, height))
        )
    }
}

struct BoardLayout: Codable, Sendable {
    let boardId: String
    let widgets: [WidgetInstance]
}

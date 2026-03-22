import Foundation

protocol BoardLayoutRepositoryProtocol: Sendable {
    func fetchLayout(boardId: String) async throws -> BoardLayout
    func saveLayout(_ layout: BoardLayout) async throws
}

struct BoardLayoutRepository: BoardLayoutRepositoryProtocol {
    private let client: APIClient
    private let storage = LocalStorage.shared

    init(client: APIClient = .shared) {
        self.client = client
    }

    func fetchLayout(boardId: String) async throws -> BoardLayout {
        // 先尝试本地缓存
        if let cached = storage.get(BoardLayout.self, forKey: "layout:\(boardId)") {
            return cached
        }
        // 没有缓存则返回空布局
        return BoardLayout(boardId: boardId, widgets: [])
    }

    func saveLayout(_ layout: BoardLayout) async throws {
        // 本地持久化
        storage.set(layout, forKey: "layout:\(layout.boardId)")
        // 后端同步（非关键路径，失败不影响 UI）
        struct SaveRequest: Encodable {
            let layout: [WidgetInstance]
        }
        let _: EmptyResponse = (try? await client.post(
            "/work-widget-layout/save/\(layout.boardId)",
            body: SaveRequest(layout: layout.widgets)
        )) ?? EmptyResponse()
    }
}

struct EmptyResponse: Codable {}

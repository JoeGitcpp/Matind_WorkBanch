import Foundation
import MatindCore
import Observation

@Observable
@MainActor
final class BoardLayoutViewModel {
    private(set) var widgets: [WidgetInstance] = []
    private(set) var isLoading = false
    var showPluginPicker = false

    private let repository: any BoardLayoutRepositoryProtocol
    private var currentBoardId: String?
    /// 后发起的加载作废先发起的结果，避免切页时把加载状态提前清掉。
    private var loadGeneration = UUID()
    private var saveTask: Task<Void, Never>?

    init(repository: any BoardLayoutRepositoryProtocol = BoardLayoutRepository()) {
        self.repository = repository
    }

    func load(boardId: String) async {
        let generation = UUID()
        loadGeneration = generation
        currentBoardId = boardId
        isLoading = true
        do {
            let layout = try await repository.fetchLayout(boardId: boardId)
            guard loadGeneration == generation else { return }
            widgets = layout.widgets
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            guard loadGeneration == generation else { return }
            isLoading = false
            print("[BoardLayoutViewModel] Failed to load layout: \(error)")
        }
    }

    func addWidget(_ kind: BoardWidgetKind) {
        let nextRow = widgets.map { $0.gridY + $0.gridH }.max() ?? 0
        let placement = kind.placement
        let instance = WidgetInstance(
            id: UUID().uuidString,
            pluginId: kind.rawValue,
            gridX: 0,
            gridY: nextRow,
            gridW: placement.width,
            gridH: placement.height
        )
        widgets.append(instance)
        scheduleSave()
    }

    func updateParams(id: String, datasetId: String, viewType: String) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        widgets[index].params["datasetId"] = datasetId
        if viewType.isEmpty {
            widgets[index].params.removeValue(forKey: "viewType")
        } else {
            widgets[index].params["viewType"] = viewType
        }
        scheduleSave()
    }

    func removeWidget(id: String) {
        widgets.removeAll { $0.id == id }
        scheduleSave()
    }

    func moveWidget(id: String, toX: Int, toY: Int) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        let old = widgets[index]
        widgets[index] = WidgetInstance(
            id: old.id, pluginId: old.pluginId,
            gridX: max(0, min(toX, 12 - old.gridW)), gridY: max(0, toY),
            gridW: old.gridW, gridH: old.gridH,
            params: old.params
        )
        scheduleSave()
    }

    func resizeWidget(id: String, newW: Int, newH: Int) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        let old = widgets[index]
        widgets[index] = WidgetInstance(
            id: old.id, pluginId: old.pluginId,
            gridX: old.gridX, gridY: old.gridY,
            gridW: max(2, min(12, newW)), gridH: max(1, min(8, newH)),
            params: old.params
        )
        scheduleSave()
    }

    /// 1 秒 debounce 保存
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            // try? intentionally swallows CancellationError when Task is cancelled
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let boardId = currentBoardId else { return }
            let layout = BoardLayout(boardId: boardId, widgets: widgets)
            try? await repository.saveLayout(layout)
        }
    }
}

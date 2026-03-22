import Foundation
import Observation

@Observable
@MainActor
final class BoardLayoutViewModel {
    private(set) var widgets: [WidgetInstance] = []
    private(set) var isLoading = false
    var showPluginPicker = false

    private let repository: any BoardLayoutRepositoryProtocol
    private var currentBoardId: String?
    private var saveTask: Task<Void, Never>?

    init(repository: any BoardLayoutRepositoryProtocol = BoardLayoutRepository()) {
        self.repository = repository
    }

    func load(boardId: String) async {
        currentBoardId = boardId
        isLoading = true
        defer { isLoading = false }
        do {
            let layout = try await repository.fetchLayout(boardId: boardId)
            widgets = layout.widgets
        } catch {
            print("[BoardLayoutViewModel] Failed to load layout: \(error)")
        }
    }

    func addWidget(pluginId: String) {
        let nextRow = widgets.map { $0.gridY + $0.gridH }.max() ?? 0
        let instance = WidgetInstance.defaultInstance(pluginId: pluginId, at: nextRow)
        widgets.append(instance)
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
            gridW: old.gridW, gridH: old.gridH
        )
        scheduleSave()
    }

    func resizeWidget(id: String, newW: Int, newH: Int) {
        guard let index = widgets.firstIndex(where: { $0.id == id }) else { return }
        let old = widgets[index]
        widgets[index] = WidgetInstance(
            id: old.id, pluginId: old.pluginId,
            gridX: old.gridX, gridY: old.gridY,
            gridW: max(2, min(12, newW)), gridH: max(1, min(8, newH))
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

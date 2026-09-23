import Foundation
import Observation

/// 标签页管理器
/// 管理所有打开的标签页，支持打开、关闭、切换
@Observable
@MainActor
final class TabManager {
    private(set) var tabs: [AppTab] = []
    private(set) var selectedTabId: String?
    /// 本次会话里收起的工作板。关闭页签不删除服务端数据。
    private var hiddenBoardIds: Set<String> = []

    /// 当前选中的标签
    var selectedTab: AppTab? {
        tabs.first { $0.id == selectedTabId }
    }

    /// 从工作板列表同步页签，已经收起的页签保持收起。
    func syncBoardTabs(_ boards: [Board], selectedBoardId: String?) {
        hiddenBoardIds.formIntersection(Set(boards.map(\.id)))
        let visible = boards.filter { !hiddenBoardIds.contains($0.id) }
        let nonBoardTabs = tabs.filter { !$0.isBoard }
        tabs = visible.map { AppTab.board(id: $0.id, name: $0.name) } + nonBoardTabs
        if let selectedBoardId,
           !hiddenBoardIds.contains(selectedBoardId),
           tabs.contains(where: { $0.id == "board-\(selectedBoardId)" }) {
            selectedTabId = "board-\(selectedBoardId)"
        } else if selectedTabId == nil || !tabs.contains(where: { $0.id == selectedTabId }) {
            selectedTabId = tabs.first?.id
        }
    }

    func reopen(_ boardId: String, boards: [Board]) {
        hiddenBoardIds.remove(boardId)
        syncBoardTabs(boards, selectedBoardId: boardId)
    }

    /// 打开设置标签
    func openSettings() {
        if !tabs.contains(where: { $0.id == AppTab.settings.id }) {
            tabs.append(.settings)
        }
        selectedTabId = AppTab.settings.id
    }

    /// 打开自动化蓝图标签
    func openAutomation() {
        if !tabs.contains(where: { $0.id == AppTab.automation.id }) {
            tabs.append(.automation)
        }
        selectedTabId = AppTab.automation.id
    }

    /// 选择标签
    func select(_ tabId: String) {
        selectedTabId = tabId
    }

    /// 关闭标签。工作板只在本次会话收起，不删除。
    func close(_ tabId: String) {
        if let tab = tabs.first(where: { $0.id == tabId }), case .board(let id, _) = tab {
            hiddenBoardIds.insert(id)
        }
        tabs.removeAll { $0.id == tabId }
        if selectedTabId == tabId {
            selectedTabId = tabs.last?.id
        }
    }

    /// 获取选中工作板的 ID（如果当前选中的是工作板标签）
    var selectedBoardId: String? {
        guard let tab = selectedTab, case .board(let id, _) = tab else {
            return nil
        }
        return id
    }
}

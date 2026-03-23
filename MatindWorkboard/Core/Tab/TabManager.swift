import Foundation
import Observation

/// 标签页管理器
/// 管理所有打开的标签页，支持打开、关闭、切换
@Observable
@MainActor
final class TabManager {
    private(set) var tabs: [AppTab] = []
    var selectedTabId: String?

    /// 当前选中的标签
    var selectedTab: AppTab? {
        tabs.first { $0.id == selectedTabId }
    }

    /// 从工作板列表初始化标签
    func syncBoardTabs(_ boards: [Board], selectedBoardId: String?) {
        // 保留非工作板标签
        let nonBoardTabs = tabs.filter { !$0.isBoard }

        // 创建工作板标签
        let boardTabs = boards.map { AppTab.board(id: $0.id, name: $0.name) }

        tabs = boardTabs + nonBoardTabs

        // 恢复选中状态
        if let selectedBoardId, tabs.contains(where: { $0.id == "board-\(selectedBoardId)" }) {
            selectedTabId = "board-\(selectedBoardId)"
        } else if selectedTabId == nil || !tabs.contains(where: { $0.id == selectedTabId }) {
            selectedTabId = tabs.first?.id
        }
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

    /// 关闭标签
    func close(_ tabId: String) {
        tabs.removeAll { $0.id == tabId }
        // 如果关闭的是当前选中标签，切到前一个
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

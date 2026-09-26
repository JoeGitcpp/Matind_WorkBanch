import Foundation
import Observation

/// 标签页管理器。工作板页签与目录一一对应，关闭页签就是删除页面，不在本地另藏一份。
@Observable
@MainActor
final class TabManager {
    private(set) var tabs: [AppTab] = []
    private(set) var selectedTabId: String?

    /// 当前选中的标签
    var selectedTab: AppTab? {
        tabs.first { $0.id == selectedTabId }
    }

    /// 页签跟随目录。目录里没有的页面不再显示。
    func syncBoardTabs(_ boards: [Board], selectedBoardId: String?) {
        let nonBoardTabs = tabs.filter { !$0.isBoard }
        tabs = boards.map { AppTab.board(id: $0.id, name: $0.name) } + nonBoardTabs
        if let selectedBoardId,
           tabs.contains(where: { $0.id == "board-\(selectedBoardId)" }) {
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
        openFixed(.automation)
    }

    /// 打开本机服务标签
    func openServices() {
        openFixed(.services)
    }

    private func openFixed(_ tab: AppTab) {
        if !tabs.contains(where: { $0.id == tab.id }) {
            tabs.append(tab)
        }
        selectedTabId = tab.id
    }

    /// 选择标签
    func select(_ tabId: String) {
        selectedTabId = tabId
    }

    /// 关闭设置或自动化页签。工作板页签的删除由目录接口负责，这里不收起。
    func close(_ tabId: String) {
        guard let tab = tabs.first(where: { $0.id == tabId }), !tab.isBoard else { return }
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

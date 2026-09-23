import SwiftUI

struct ContentView: View {
    @Environment(AuthState.self) private var authState
    @Environment(LocalServerState.self) private var localServer

    var body: some View {
        Group {
            switch authState.phase {
            case .restoring:
                ProgressView("正在恢复登录")
            case .unavailable:
                ContentUnavailableView {
                    Label("无法连接服务器", systemImage: "wifi.slash")
                } description: {
                    Text(authState.notice ?? "请确认本机控制面已经启动")
                } actions: {
                    Button("重试") { Task { await authState.retry() } }
                }
            case .signedOut:
                LoginView()
            case .signedIn:
                MainView()
            }
        }
        .onChange(of: authState.phase) { _, phase in
            if phase != .signedIn {
                localServer.clearSession()
            }
        }
    }
}

struct MainView: View {
    @State private var workbenchVM = WorkbenchViewModel()
    @State private var boardVM = BoardViewModel()
    @State private var tabManager = TabManager()
    @State private var notificationVM = NotificationViewModel()
    @State private var showNotifications = false
    @State private var managedBoard: Board?
    @State private var boardEditing: BoardEditing = .off
    @State private var pluginAddRequest: PluginAddRequest?
    @State private var boardPendingDelete: Board?
    @State private var deleteNotice: String?

    private var canCreateBoard: Bool {
        guard workbenchVM.selectedWorkbenchId != nil else { return false }
        switch boardVM.catalog {
        case .loaded, .empty:
            return true
        case .idle, .loading, .failed:
            return false
        }
    }

    private var createHelp: String {
        if workbenchVM.selectedWorkbenchId == nil { return "请先选择工作台" }
        switch boardVM.catalog {
        case .idle, .loading:
            return "加载中"
        case .failed:
            return "加载失败"
        case .loaded, .empty:
            return "新建页面"
        }
    }

    private func createBoard() {
        guard let workbenchId = workbenchVM.selectedWorkbenchId else { return }
        Task { await boardVM.createBoard(workbenchId: workbenchId) }
    }

    private func retryCreate() {
        guard let workbenchId = workbenchVM.selectedWorkbenchId else { return }
        Task { await boardVM.retryCreate(workbenchId: workbenchId) }
    }

    private func openManage(_ boardId: String) {
        managedBoard = boardVM.boards.first { $0.id == boardId }
    }

    private var selectedBoard: Board? {
        guard let id = tabManager.selectedBoardId else { return nil }
        return boardVM.boards.first { $0.id == id }
    }

    private var showsEditMode: Bool {
        selectedBoard?.surfaceAccess == .editable
    }

    private var showsAddPlugin: Bool {
        showsEditMode && boardEditing == .on
    }

    var body: some View {
        VStack(spacing: 0) {
            // 唯一的标签栏
            AppTabBar(
                tabs: tabManager.tabs,
                boards: boardVM.boards,
                selectedTabId: tabManager.selectedTabId,
                canCreate: canCreateBoard,
                createHelp: createHelp,
                onSelect: { tabManager.select($0) },
                onClose: closeTab,
                onCreate: createBoard,
                onManage: openManage
            )

            if let notice = deleteNotice {
                HStack {
                    Text(notice)
                        .font(.callout)
                    Spacer()
                    Button("关闭") { deleteNotice = nil }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            } else if let notice = boardVM.writeNotice {
                HStack {
                    Text(notice)
                        .font(.callout)
                    Spacer()
                    Button("重试") { retryCreate() }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Divider()

            boardCanvas
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(navigationTitle)
        .toolbar {
            // 工作台选择器（左侧）
            ToolbarItem(placement: .navigation) {
                WorkbenchPicker(
                    workbenches: workbenchVM.workbenches,
                    selectedId: workbenchVM.selectedWorkbenchId,
                    isLoading: workbenchVM.isLoading,
                    error: workbenchVM.error,
                    onSelect: { workbenchVM.selectWorkbench($0) },
                    onRetry: { Task { await workbenchVM.load() } }
                )
            }

            // 编辑模式在通知左侧；添加插件只在编辑模式下出现，并排在编辑按钮左边。
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    if showsAddPlugin {
                        Button {
                            pluginAddRequest = PluginAddRequest(id: UUID())
                        } label: {
                            Label("添加插件", systemImage: "plus")
                        }
                    }
                    if showsEditMode {
                        Button {
                            boardEditing = boardEditing.toggled
                        } label: {
                            Label(boardEditing == .on ? "完成编辑" : "编辑模式", systemImage: "pencil")
                        }
                        .tint(boardEditing == .on ? .red : nil)
                    }
                    Button(action: { showNotifications.toggle() }) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell")
                            NotificationBadge(count: notificationVM.unreadCount)
                                .offset(x: 6, y: -6)
                        }
                    }
                    .help("通知中心")
                    .popover(isPresented: $showNotifications, arrowEdge: .bottom) {
                        NotificationCenterView(viewModel: notificationVM)
                    }
                }
            }
        }
        .task { await workbenchVM.load() }
        .task {
            await notificationVM.requestNotificationPermission()
            await notificationVM.loadUnreadCount()
        }
        .onChange(of: workbenchVM.selectedWorkbenchId) { _, newId in
            handleWorkbenchChange(newId)
        }
        .onChange(of: boardVM.boards) { _, boards in
            tabManager.syncBoardTabs(boards, selectedBoardId: boardVM.selectedBoardId)
        }
        .onChange(of: tabManager.selectedBoardId) { _, newBoardId in
            handleTabBoardChange(newBoardId)
        }
        // 监听系统菜单命令
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            tabManager.openSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAutomation)) { _ in
            tabManager.openAutomation()
        }
        .alert(
            "删除页面",
            isPresented: Binding(
                get: { boardPendingDelete != nil },
                set: { if !$0 { boardPendingDelete = nil } }
            ),
            presenting: boardPendingDelete
        ) { board in
            Button("删除", role: .destructive) {
                Task { await confirmDelete(board) }
            }
            Button("取消", role: .cancel) {}
        } message: { board in
            Text("将删除「\(board.name)」。")
        }
        .sheet(item: $managedBoard) { board in
            BoardManageSheet(board: board) { name, key in
                guard let workbenchId = workbenchVM.selectedWorkbenchId else { return }
                try await boardVM.rename(
                    workbenchId: workbenchId,
                    board: board,
                    name: name,
                    idempotencyKey: key
                )
            } onDelete: { reason, key in
                guard let workbenchId = workbenchVM.selectedWorkbenchId else { return }
                try await boardVM.delete(
                    workbenchId: workbenchId,
                    board: board,
                    reason: reason,
                    idempotencyKey: key
                )
            }
        }
    }

    // MARK: - 导航标题（显示当前标签名）

    private var navigationTitle: String {
        tabManager.selectedTab?.title ?? "Matind Workboard"
    }

    // MARK: - 标签内容路由

    @ViewBuilder
    private var boardCanvas: some View {
        if let tab = tabManager.selectedTab {
            tabContent(for: tab)
        } else {
            idleCanvas
        }
    }

    @ViewBuilder
    private var idleCanvas: some View {
        switch boardVM.catalog {
        case .loading, .idle:
            ProgressView("正在加载页面")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let failure):
            ContentUnavailableView {
                Label(failure.message, systemImage: "wifi.slash")
            } actions: {
                Button("重试") {
                    guard let workbenchId = workbenchVM.selectedWorkbenchId else { return }
                    Task { await boardVM.load(workbenchId: workbenchId) }
                }
            }
        case .empty:
            ContentUnavailableView {
                Label("还没有页面", systemImage: "rectangle.stack")
            } actions: {
                Button("新建第一个页面", action: createBoard)
            }
        case .loaded:
            ContentUnavailableView("选择页面", systemImage: "rectangle.stack")
        }
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .board(let id, _):
            BoardContentView(
                boardId: id,
                access: boardVM.boards.first { $0.id == id }?.surfaceAccess ?? .readOnly,
                editing: boardEditing,
                pluginAddRequest: pluginAddRequest
            )
        case .settings:
            SettingsView()
        case .automation:
            AutomationView()
        }
    }

    // MARK: - 事件处理

    private func handleWorkbenchChange(_ newId: String?) {
        guard let wbId = newId else { return }
        Task { await boardVM.load(workbenchId: wbId) }
    }

    private func closeTab(_ tabId: String) {
        guard let tab = tabManager.tabs.first(where: { $0.id == tabId }) else { return }
        if case .board(let id, _) = tab, let board = boardVM.boards.first(where: { $0.id == id }) {
            boardPendingDelete = board
            return
        }
        tabManager.close(tabId)
    }

    private func confirmDelete(_ board: Board) async {
        boardPendingDelete = nil
        deleteNotice = nil
        guard let workbenchId = workbenchVM.selectedWorkbenchId else { return }
        do {
            try await boardVM.delete(
                workbenchId: workbenchId,
                board: board,
                reason: nil,
                idempotencyKey: UUID()
            )
        } catch {
            deleteNotice = PresentedFailure.message(for: error)
        }
    }

    private func handleTabBoardChange(_ newBoardId: String?) {
        guard let boardId = newBoardId,
              let wbId = workbenchVM.selectedWorkbenchId else { return }
        boardVM.selectBoard(boardId, workbenchId: wbId)
    }
}

// MARK: - 工作台选择器

struct WorkbenchPicker: View {
    let workbenches: [Workbench]
    let selectedId: String?
    let isLoading: Bool
    let error: String?
    let onSelect: (String) -> Void
    let onRetry: () -> Void

    var body: some View {
        Menu {
            if isLoading {
                Text("加载中...")
            } else if let error {
                Text(error)
                Button("重试", action: onRetry)
            } else if workbenches.isEmpty {
                Text("还没有可用的工作台")
            } else {
                ForEach(workbenches) { wb in
                    Button {
                        onSelect(wb.id)
                    } label: {
                        HStack {
                            Text(wb.name)
                            if wb.id == selectedId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 12))
                Text(selectedName)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectedName: String {
        if isLoading { return "加载中..." }
        if error != nil { return "无法连接" }
        guard let id = selectedId,
              let wb = workbenches.first(where: { $0.id == id }) else {
            return "选择工作台"
        }
        return wb.name
    }
}

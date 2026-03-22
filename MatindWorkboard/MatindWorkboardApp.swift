import SwiftUI

@main
struct MatindWorkboardApp: App {
    @State private var authState = AuthState()

    init() {
        // 初始化通知服务（设置 delegate）
        _ = NotificationService.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authState)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
    }
}

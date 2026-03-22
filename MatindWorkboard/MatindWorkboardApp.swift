import SwiftUI

@main
struct MatindWorkboardApp: App {
    @State private var authState = AuthState()

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

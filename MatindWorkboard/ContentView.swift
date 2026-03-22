import SwiftUI

struct ContentView: View {
    @Environment(AuthState.self) private var authState

    var body: some View {
        Group {
            if authState.isAuthenticated {
                MainView()
            } else {
                LoginView()
            }
        }
    }
}

struct MainView: View {
    var body: some View {
        NavigationSplitView {
            Text("工作区列表")
                .frame(minWidth: 200)
        } detail: {
            VStack {
                Text("Matind Workboard")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("选择左侧工作区开始使用")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Matind Workboard")
    }
}

// LoginPlaceholderView 已由 LoginView 替代

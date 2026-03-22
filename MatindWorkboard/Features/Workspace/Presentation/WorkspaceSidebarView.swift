import SwiftUI

struct WorkspaceSidebarView: View {
    @Binding var selectedWorkspaceId: String?
    let workspaces: [Workspace]
    let isLoading: Bool
    let error: String?

    var body: some View {
        List(selection: $selectedWorkspaceId) {
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("加载中…")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else if workspaces.isEmpty {
                Text("暂无协作空间")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                Section("协作空间") {
                    ForEach(workspaces) { workspace in
                        Label(workspace.name, systemImage: "folder")
                            .tag(workspace.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
    }
}

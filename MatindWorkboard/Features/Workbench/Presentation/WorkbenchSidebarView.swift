import SwiftUI

struct WorkbenchSidebarView: View {
    @Binding var selectedWorkbenchId: String?
    let workbenches: [Workbench]
    let isLoading: Bool
    let error: String?

    var body: some View {
        List(selection: $selectedWorkbenchId) {
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
            } else if workbenches.isEmpty {
                Text("暂无协作空间")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                Section("协作空间") {
                    ForEach(workbenches) { workbench in
                        Label(workbench.name, systemImage: "folder")
                            .tag(workbench.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
    }
}

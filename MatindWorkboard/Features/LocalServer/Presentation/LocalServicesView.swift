import MatindCore
import SwiftUI

/// 本机服务页。服务器卡片在上，官方服务以卡片列出。
struct LocalServicesView: View {
    @Environment(ServiceCatalogState.self) private var catalog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("本机服务")
                    .font(.title2.bold())
                Text("这台电脑上的服务由所有者和他任命的管理者安装、启停，并决定向哪些工作区授权。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                PrivateServerSection()
                serviceGrid
                if let notice = catalog.notice {
                    Text(notice)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var serviceGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("服务")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                ForEach(OfficialServiceIndex.modules) { module in
                    ServiceModuleCard(module: module)
                }
            }
        }
    }
}

private struct ServiceModuleCard: View {
    @Environment(ServiceCatalogState.self) private var catalog
    let module: ServiceModuleManifest

    var body: some View {
        let phase = catalog.phase(of: module.moduleId)
        VStack(alignment: .leading, spacing: 8) {
            Text(module.title)
                .font(.headline)
            Text(module.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(ServiceCardCopy.phaseTitle(phase))
                .font(.caption.weight(.semibold))
            actionRow(phase)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func actionRow(_ phase: ServiceInstancePhase) -> some View {
        let actions = ServiceLifecycle.commands(for: phase).compactMap(ServiceCardCopy.action)
        HStack {
            ForEach(actions, id: \.self) { action in
                Button(buttonTitle(action)) {
                    catalog.perform(action, on: module)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func buttonTitle(_ action: ServiceCardAction) -> String {
        switch action {
        case .install: "安装"
        case .cancelInstall: "取消安装"
        case .enable: "启用"
        case .stop: "停用"
        case .uninstall: "卸载"
        case .retry: "重试"
        }
    }
}

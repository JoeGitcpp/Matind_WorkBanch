import SwiftUI

/// 自动化蓝图页面
/// 作为标签页打开，展示蓝图自动化编辑器
struct AutomationView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "flowchart")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("自动化蓝图")
                .font(.title2.bold())

            Text("可视化编排自动化工作流\n即将推出")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

import SwiftUI

/// 工作板主网格视图
struct BoardGridView: View {
    @Bindable var layoutVM: BoardLayoutViewModel
    let boardId: String
    let plugins: [PluginManifest]

    // 网格配置
    private let columnCount = 12
    private let rowHeight: CGFloat = 80
    private let gap: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let colWidth = (geo.size.width - gap * CGFloat(columnCount + 1)) / CGFloat(columnCount)

            ScrollView {
                ZStack(alignment: .topLeading) {
                    // 背景网格线（仅在开发模式下）
                    #if DEBUG
                    GridBackground(columnCount: columnCount, colWidth: colWidth, gap: gap, rowHeight: rowHeight)
                    #endif

                    // 插件卡片层
                    ForEach(layoutVM.widgets) { widget in
                        if let plugin = plugins.first(where: { $0.id == widget.pluginId }) {
                            WidgetCardView(
                                widget: widget,
                                plugin: plugin,
                                colWidth: colWidth,
                                rowHeight: rowHeight,
                                gap: gap,
                                onRemove: { layoutVM.removeWidget(id: widget.id) },
                                onMove: { dx, dy in
                                    layoutVM.moveWidget(
                                        id: widget.id,
                                        toX: widget.gridX + dx,
                                        toY: widget.gridY + dy
                                    )
                                },
                                onResize: { dw, dh in
                                    layoutVM.resizeWidget(
                                        id: widget.id,
                                        newW: widget.gridW + dw,
                                        newH: widget.gridH + dh
                                    )
                                }
                            )
                        }
                    }
                }
                .frame(
                    width: geo.size.width,
                    height: max(
                        geo.size.height,
                        CGFloat((layoutVM.widgets.map { $0.gridY + $0.gridH }.max() ?? 4) + 2) * (rowHeight + gap) + gap
                    )
                )
            }
        }
        .task(id: boardId) {
            await layoutVM.load(boardId: boardId)
        }
        .sheet(isPresented: $layoutVM.showPluginPicker) {
            PluginPickerView(plugins: plugins) { pluginId in
                layoutVM.addWidget(pluginId: pluginId)
                layoutVM.showPluginPicker = false
            }
        }
    }

    /// 计算卡片在像素坐标系中的位置和尺寸
    static func frame(for widget: WidgetInstance, colWidth: CGFloat, rowHeight: CGFloat, gap: CGFloat) -> CGRect {
        CGRect(
            x: gap + CGFloat(widget.gridX) * (colWidth + gap),
            y: gap + CGFloat(widget.gridY) * (rowHeight + gap),
            width: CGFloat(widget.gridW) * colWidth + CGFloat(widget.gridW - 1) * gap,
            height: CGFloat(widget.gridH) * rowHeight + CGFloat(widget.gridH - 1) * gap
        )
    }
}

// MARK: - WidgetCardView

struct WidgetCardView: View {
    let widget: WidgetInstance
    let plugin: PluginManifest
    let colWidth: CGFloat
    let rowHeight: CGFloat
    let gap: CGFloat
    let onRemove: () -> Void
    let onMove: (Int, Int) -> Void
    let onResize: (Int, Int) -> Void

    @State private var isDragging = false

    var body: some View {
        let frame = BoardGridView.frame(for: widget, colWidth: colWidth, rowHeight: rowHeight, gap: gap)

        VStack(spacing: 0) {
            // 标题栏（拖拽手柄）
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(plugin.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("移除插件")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)
            .cursor(.openHand)

            Divider()

            // 内容区
            if let pluginDir = Bundle.main.url(
                forResource: plugin.id,
                withExtension: nil,
                subdirectory: "Plugins"
            ) {
                WebViewPluginHost(
                    pluginId: plugin.id,
                    pluginDirectory: pluginDir,
                    apiToken: nil
                )
            } else {
                Color.gray.opacity(0.05)
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "puzzlepiece")
                                .foregroundStyle(.secondary)
                            Text(plugin.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(isDragging ? 0.2 : 0.07), radius: isDragging ? 8 : 3, y: isDragging ? 4 : 1)
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
        .position(x: frame.midX, y: frame.midY)
        .frame(width: frame.width, height: frame.height)
        // 拖拽（简化：方向键步进，完整拖拽在 M6 后续迭代）
        .contextMenu {
            Menu("移动") {
                Button("↑ 上移") { onMove(0, -1) }
                Button("↓ 下移") { onMove(0, 1) }
                Button("← 左移") { onMove(-1, 0) }
                Button("→ 右移") { onMove(1, 0) }
            }
            Menu("调整大小") {
                Button("加宽") { onResize(1, 0) }
                Button("减窄") { onResize(-1, 0) }
                Button("加高") { onResize(0, 1) }
                Button("减矮") { onResize(0, -1) }
            }
            Divider()
            Button(role: .destructive, action: onRemove) {
                Label("移除", systemImage: "trash")
            }
        }
    }
}

// MARK: - PluginPickerView

struct PluginPickerView: View {
    let plugins: [PluginManifest]
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 120))]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("添加插件")
                    .font(.headline)
                Spacer()
                Button("取消") { dismiss() }
            }
            .padding()

            Divider()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(plugins) { plugin in
                        Button(action: { onSelect(plugin.id) }) {
                            VStack(spacing: 8) {
                                Image(systemName: "puzzlepiece.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.blue)
                                Text(plugin.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .multilineTextAlignment(.center)
                                if let desc = plugin.description {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .frame(width: 400, height: 300)
    }
}

// MARK: - Grid Background (Debug only)

#if DEBUG
struct GridBackground: View {
    let columnCount: Int
    let colWidth: CGFloat
    let gap: CGFloat
    let rowHeight: CGFloat

    var body: some View {
        Canvas { context, size in
            var path = Path()
            // 竖线
            for col in 0...columnCount {
                let x = gap + CGFloat(col) * (colWidth + gap)
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            // 横线（每 rowHeight + gap 一行）
            var y: CGFloat = 0
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += rowHeight + gap
            }
            context.stroke(path, with: .color(.gray.opacity(0.1)), lineWidth: 0.5)
        }
    }
}
#endif

// MARK: - View+Cursor helper (macOS only)

extension View {
    @ViewBuilder
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

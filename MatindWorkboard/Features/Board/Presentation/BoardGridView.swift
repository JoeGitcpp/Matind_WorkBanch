import MatindCore
import SwiftUI

/// 工作板主网格视图
struct BoardGridView: View {
    @Bindable var layoutVM: BoardLayoutViewModel
    @Environment(AuthState.self) private var auth
    let boardId: String
    let arrangement: BoardArrangement

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
                        WidgetCardView(
                            widget: widget,
                            accessToken: auth.accessToken ?? "",
                            colWidth: colWidth,
                            rowHeight: rowHeight,
                            gap: gap,
                            arrangement: arrangement,
                            onRemove: { layoutVM.removeWidget(id: widget.id) },
                            onParams: { datasetId, viewType in
                                layoutVM.updateParams(
                                    id: widget.id,
                                    datasetId: datasetId,
                                    viewType: viewType
                                )
                            },
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
                .frame(
                    width: geo.size.width,
                    height: max(
                        geo.size.height,
                        CGFloat((layoutVM.widgets.map { $0.gridY + $0.gridH }.max() ?? 4) + 2) * (rowHeight + gap) + gap
                    )
                )
            }
        }
        .sheet(isPresented: $layoutVM.showPluginPicker) {
            PluginPickerView { kind in
                layoutVM.addWidget(kind)
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

/// 把一次拖动的位移换成网格步数。只在跨过新格子时返回增量，避免每像素都挪一格。
struct GridTranslation {
    private var applied = (x: 0, y: 0)

    mutating func consume(translation: CGSize, unit: CGSize) -> (x: Int, y: Int)? {
        guard unit.width > 1, unit.height > 1 else { return nil }
        let nextX = Int((translation.width / unit.width).rounded())
        let nextY = Int((translation.height / unit.height).rounded())
        let step = (x: nextX - applied.x, y: nextY - applied.y)
        guard step.x != 0 || step.y != 0 else { return nil }
        applied = (nextX, nextY)
        return step
    }

    mutating func reset() {
        applied = (0, 0)
    }
}

// MARK: - WidgetCardView

struct WidgetCardView: View {
    let widget: WidgetInstance
    let accessToken: String
    let colWidth: CGFloat
    let rowHeight: CGFloat
    let gap: CGFloat
    let arrangement: BoardArrangement
    let onRemove: () -> Void
    let onParams: (String, String) -> Void
    let onMove: (Int, Int) -> Void
    let onResize: (Int, Int) -> Void

    @State private var isDragging = false
    @State private var moveTranslation = GridTranslation()
    @State private var resizeTranslation = GridTranslation()

    var body: some View {
        let frame = BoardGridView.frame(for: widget, colWidth: colWidth, rowHeight: rowHeight, gap: gap)

        VStack(spacing: 0) {
            cardHeader
            Divider()
            widgetSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: frame.width, height: frame.height, alignment: .top)
        .overlay(alignment: .bottomTrailing) {
            if arrangement == .arranging {
                resizeGrip
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(isDragging ? 0.2 : 0.07), radius: isDragging ? 8 : 3, y: isDragging ? 4 : 1)
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
        .position(x: frame.midX, y: frame.midY)
        .contextMenu {
            if arrangement == .arranging {
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

    private var gridPitch: CGSize {
        CGSize(width: colWidth + gap, height: rowHeight + gap)
    }

    /// 编辑模式下标题栏才拖动卡片。锁定时这里只是标题，避免抢走表内的列宽和行高拖拽。
    @ViewBuilder
    private var cardHeader: some View {
        let bar = HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer()
            if arrangement == .arranging {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("移除插件")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .contentShape(Rectangle())

        switch arrangement {
        case .arranging:
            bar.highPriorityGesture(moveGesture)
                .cursor(.openHand)
        case .locked:
            bar
        }
    }

    private var resizeGrip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
            .background(.bar)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(6)
            .contentShape(Rectangle())
            .highPriorityGesture(resizeGesture)
            .help("拖动调整大小")
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                isDragging = true
                var translation = moveTranslation
                guard let step = translation.consume(translation: value.translation, unit: gridPitch) else { return }
                moveTranslation = translation
                onMove(step.x, step.y)
            }
            .onEnded { _ in
                isDragging = false
                moveTranslation.reset()
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                isDragging = true
                var translation = resizeTranslation
                guard let step = translation.consume(translation: value.translation, unit: gridPitch) else { return }
                resizeTranslation = translation
                onResize(step.x, step.y)
            }
            .onEnded { _ in
                isDragging = false
                resizeTranslation.reset()
            }
    }

    private var title: String {
        BoardWidgetKind(rawValue: widget.pluginId)?.title ?? widget.pluginId
    }

    @ViewBuilder
    private var widgetSurface: some View {
        switch BoardWidgetKind(rawValue: widget.pluginId) {
        case .hyperTable:
            hyperTable
        case nil:
            missingKind
        }
    }

    @ViewBuilder
    private var hyperTable: some View {
        if let webBase = AppConfig.webBase,
           let page = HyperTableLocation.page(
            webBase: webBase,
            datasetId: widget.params["datasetId"] ?? ""
           ),
           let claims = AccessTokenClaims.snapshot(of: accessToken) {
            HyperTableEmbedHost(
                page: page,
                accessToken: accessToken,
                subject: claims.subject,
                expiresAt: claims.expiresAt,
                onParams: onParams
            )
        } else if AppConfig.webBase == nil {
            missingKind
        } else {
            Text("登录已过期，请重新登录后再打开多维表")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var missingKind: some View {
        VStack(spacing: 4) {
            Image(systemName: "rectangle.dashed")
                .foregroundStyle(.secondary)
            Text("这个组件请在网页里查看")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - PluginPickerView

struct PluginPickerView: View {
    let onSelect: (BoardWidgetKind) -> Void
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
                    ForEach(BoardWidgetKind.allCases, id: \.rawValue) { kind in
                        Button(action: { onSelect(kind) }) {
                            VStack(spacing: 8) {
                                Image(systemName: "tablecells")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.blue)
                                Text(kind.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .multilineTextAlignment(.center)
                                Text(kind.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
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

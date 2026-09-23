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
                .coordinateSpace(name: BoardCanvasSpace.name)
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
        BoardGridGeometry(columnWidth: colWidth, rowHeight: rowHeight, gap: gap)
            .frame(x: widget.gridX, y: widget.gridY, width: widget.gridW, height: widget.gridH)
    }
}

/// 工作板内容坐标。拖动位移在这个坐标系里计算，不跟卡片自己走。
enum BoardCanvasSpace {
    static let name = "board-canvas"
}

/// 格子与像素的换算。拖动过程中卡片按指针平移，松手才用这里对齐。
struct BoardGridGeometry: Equatable, Sendable {
    var columnWidth: CGFloat
    var rowHeight: CGFloat
    var gap: CGFloat

    var pitch: CGSize {
        CGSize(width: columnWidth + gap, height: rowHeight + gap)
    }

    func frame(x: Int, y: Int, width: Int, height: Int) -> CGRect {
        CGRect(
            x: gap + CGFloat(x) * pitch.width,
            y: gap + CGFloat(y) * pitch.height,
            width: CGFloat(width) * columnWidth + CGFloat(max(0, width - 1)) * gap,
            height: CGFloat(height) * rowHeight + CGFloat(max(0, height - 1)) * gap
        )
    }

    /// 松手时把卡片左上角吸到最近的格子。抓住的点相对卡片不变。
    func cell(containingOrigin origin: CGPoint) -> (x: Int, y: Int) {
        (
            x: max(0, snapped(origin.x - gap, pitch: pitch.width)),
            y: max(0, snapped(origin.y - gap, pitch: pitch.height))
        )
    }

    /// 松手时按卡片像素尺寸收回占几格。
    func span(covering size: CGSize) -> (width: Int, height: Int) {
        (
            width: max(1, snapped(size.width + gap, pitch: pitch.width)),
            height: max(1, snapped(size.height + gap, pitch: pitch.height))
        )
    }

    private func snapped(_ distance: CGFloat, pitch: CGFloat) -> Int {
        guard pitch > 1 else { return 0 }
        return Int((distance / pitch).rounded())
    }
}

/// 按下时的指针和卡片。之后只用指针在工作板里的位置计算位移，不读会重置的 translation。
struct PointerAnchor: Equatable {
    var pointer: CGPoint
    var frame: CGRect

    func translation(to location: CGPoint) -> CGSize {
        CGSize(width: location.x - pointer.x, height: location.y - pointer.y)
    }
}

/// 拖动时的预览。格子要等松手再改，否则手势坐标会跟着卡片跑，抓住的位置就会跳。
enum CardPointerPreview: Equatable {
    case moving(start: CGRect, translation: CGSize)
    case resizing(start: CGRect, translation: CGSize)

    var frame: CGRect {
        switch self {
        case .moving(let start, let translation):
            return start.offsetBy(dx: translation.width, dy: translation.height)
        case .resizing(let start, let translation):
            return CGRect(
                x: start.minX,
                y: start.minY,
                width: max(1, start.width + translation.width),
                height: max(1, start.height + translation.height)
            )
        }
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

    @State private var preview: CardPointerPreview?
    @State private var moveAnchor: PointerAnchor?
    @State private var resizeAnchor: PointerAnchor?

    var body: some View {
        let frame = preview?.frame ?? restingFrame

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
        .shadow(color: .black.opacity(preview == nil ? 0.07 : 0.2), radius: preview == nil ? 3 : 8, y: preview == nil ? 1 : 4)
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

    private var geometry: BoardGridGeometry {
        BoardGridGeometry(columnWidth: colWidth, rowHeight: rowHeight, gap: gap)
    }

    private var restingFrame: CGRect {
        geometry.frame(x: widget.gridX, y: widget.gridY, width: widget.gridW, height: widget.gridH)
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
        DragGesture(minimumDistance: 4, coordinateSpace: .named(BoardCanvasSpace.name))
            .onChanged { value in
                let anchor = moveAnchor ?? PointerAnchor(pointer: value.startLocation, frame: restingFrame)
                moveAnchor = anchor
                preview = .moving(start: anchor.frame, translation: anchor.translation(to: value.location))
            }
            .onEnded { value in
                let anchor = moveAnchor ?? PointerAnchor(pointer: value.startLocation, frame: restingFrame)
                let translation = anchor.translation(to: value.location)
                let origin = CGPoint(
                    x: anchor.frame.minX + translation.width,
                    y: anchor.frame.minY + translation.height
                )
                let cell = geometry.cell(containingOrigin: origin)
                moveAnchor = nil
                preview = nil
                onMove(cell.x - widget.gridX, cell.y - widget.gridY)
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(BoardCanvasSpace.name))
            .onChanged { value in
                let anchor = resizeAnchor ?? PointerAnchor(pointer: value.startLocation, frame: restingFrame)
                resizeAnchor = anchor
                preview = .resizing(start: anchor.frame, translation: anchor.translation(to: value.location))
            }
            .onEnded { value in
                let anchor = resizeAnchor ?? PointerAnchor(pointer: value.startLocation, frame: restingFrame)
                let translation = anchor.translation(to: value.location)
                let size = CGSize(
                    width: anchor.frame.width + translation.width,
                    height: anchor.frame.height + translation.height
                )
                let span = geometry.span(covering: size)
                resizeAnchor = nil
                preview = nil
                onResize(span.width - widget.gridW, span.height - widget.gridH)
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

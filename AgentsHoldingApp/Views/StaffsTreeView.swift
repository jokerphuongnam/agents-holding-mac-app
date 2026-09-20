import AppKit
import SwiftUI

/// Staffs org graph — top is senior, below are reports.
/// Zoom/pan model (keeps a card under the cursor/center stable):
/// - content laid out at `layoutZoom` (crisp after bake)
/// - live `rubberScale` + `panOffset` transform: screen = point * rubber + offset
/// - ⌘+scroll / ± buttons / pinch zoom **around the focal point** (cursor or viewport center)
/// - drag or plain scroll pans; viewport chrome stays fixed
struct StaffsTreeView: View {
    let roots: [StaffTreeNode]
    let onSelect: (StaffNode) -> Void

    private let viewportMaxHeight: CGFloat = 560

    @StateObject private var zoomState = OrgGraphZoomState()
    @State private var viewportSize: CGSize = .zero
    @State private var didCenterCEO = false

    private var focusStaffId: String? {
        let ids = roots.map(\.staff.id)
        if let ceo = ids.first(where: { $0 == "holding-ceo" || $0 == "ceo" }) {
            return ceo
        }
        return roots.first?.staff.id
    }

    private var layout: OrgLayout {
        OrgLayout(zoom: zoomState.layoutZoom)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(L10n.staffsTree, systemImage: "person.3")
                    .font(.headline)
                Spacer()
                if !roots.isEmpty {
                    zoomToolbar
                }
            }
            Text(L10n.staffsTreeHelp)
                .font(.caption)
                .foregroundStyle(.secondary)

            if roots.isEmpty {
                Text(L10n.staffsTreeEmpty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                graphViewport
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var graphViewport: some View {
        GeometryReader { viewportGeo in
            ZStack(alignment: .topLeading) {
                graphContent
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: OrgContentSizeKey.self,
                                value: geo.size
                            )
                        }
                    )
                    .scaleEffect(zoomState.rubberScale, anchor: .topLeading)
                    .offset(zoomState.panOffset)
                    .gesture(panDragGesture)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .onAppear {
                viewportSize = viewportGeo.size
                zoomState.viewportSize = viewportGeo.size
                zoomState.installEventMonitors()
                centerCEOIfNeeded()
            }
            .onChange(of: viewportGeo.size) { _, newSize in
                viewportSize = newSize
                zoomState.viewportSize = newSize
            }
            .onDisappear {
                zoomState.removeEventMonitors()
            }
            .onHover { hovering in
                zoomState.isHovered = hovering
                if !hovering { zoomState.cursorInViewport = nil }
            }
            .overlay {
                ViewportCursorTracker { point in
                    zoomState.cursorInViewport = point
                }
                .allowsHitTesting(false)
            }
            .simultaneousGesture(pinchZoomGesture)
            .onPreferenceChange(CardFrameKey.self) { frames in
                zoomState.cardFrames = frames
                centerCEOIfNeeded()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 280, maxHeight: viewportMaxHeight)
        .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var zoomToolbar: some View {
        HStack(spacing: 6) {
            Button {
                zoomState.zoomOutTowardFocal()
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help(L10n.staffsTreeZoomOut)
            .disabled(!zoomState.canZoomOut)
            .accessibilityLabel(L10n.staffsTreeZoomOut)

            Text("\(Int((zoomState.displayZoom * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 36, alignment: .center)

            Button {
                zoomState.zoomInTowardFocal()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help(L10n.staffsTreeZoomIn)
            .disabled(!zoomState.canZoomIn)
            .accessibilityLabel(L10n.staffsTreeZoomIn)

            Button(L10n.staffsTreeZoomReset) {
                zoomState.resetTowardFocal()
            }
            .buttonStyle(.borderless)
            .disabled(abs(zoomState.displayZoom - 1) < 0.01)
        }
        .controlSize(.small)
    }

    private var graphContent: some View {
        let layout = self.layout
        return VStack(alignment: .center, spacing: layout.rootSpacing) {
            ForEach(roots) { root in
                OrgNodeView(node: root, depth: 0, layout: layout, onSelect: onSelect)
            }
        }
        .padding(layout.padding)
        .frame(minWidth: 320 * layout.zoom, alignment: .top)
        .coordinateSpace(name: OrgChartSpace.name)
    }

    private var panDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                zoomState.panDragChanged(translation: value.translation)
            }
            .onEnded { _ in
                zoomState.panDragEnded()
            }
    }

    private var pinchZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoomState.applyPinch(value)
            }
            .onEnded { _ in
                zoomState.endPinch()
            }
    }

    /// Place CEO under the viewport center once frames are known.
    private func centerCEOIfNeeded() {
        guard !didCenterCEO,
              let focusStaffId,
              viewportSize.width > 1,
              viewportSize.height > 1
        else { return }
        let anchorId = OrgScrollAnchor.card(focusStaffId)
        // CardFrameKey stores raw card frames; OrgNodeView publishes staff.id keys via cardAnchor.
        // Prefer staff id key used by CardFrameKey (staff.id), not scroll anchor string.
        guard let frame = zoomState.cardFrames[focusStaffId] ?? zoomState.cardFrames[anchorId]
        else { return }
        zoomState.centerContentPoint(
            CGPoint(x: frame.midX, y: frame.midY),
            in: viewportSize
        )
        didCenterCEO = true
    }
}

// MARK: - Cursor tracking (focal point for ⌘+scroll)

private struct ViewportCursorTracker: NSViewRepresentable {
    let onMove: (CGPoint?) -> Void

    final class Coordinator {
        var onMove: (CGPoint?) -> Void
        init(onMove: @escaping (CGPoint?) -> Void) { self.onMove = onMove }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onMove: onMove) }

    func makeNSView(context: Context) -> NSView {
        let view = CursorNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onMove = onMove
        (nsView as? CursorNSView)?.coordinator = context.coordinator
    }

    private final class CursorNSView: NSView {
        weak var coordinator: Coordinator?
        private var area: NSTrackingArea?

        override var isFlipped: Bool { true }

        /// Let clicks reach SwiftUI cards underneath.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let options: NSTrackingArea.Options = [
                .activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect,
            ]
            let newArea = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
            addTrackingArea(newArea)
            area = newArea
        }

        override func mouseMoved(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            coordinator?.onMove(p)
        }

        override func mouseEntered(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            coordinator?.onMove(p)
        }

        override func mouseExited(with event: NSEvent) {
            coordinator?.onMove(nil)
        }
    }
}

// MARK: - Zoom / pan state (focal-point stable)

/// screen = contentPoint * rubberScale + panOffset  (topLeading scale)
private final class OrgGraphZoomState: ObservableObject {
    @Published var layoutZoom: CGFloat = 1.0
    @Published var rubberScale: CGFloat = 1.0
    @Published var panOffset: CGSize = .zero

    var isHovered = false
    var viewportSize: CGSize = .zero
    /// Cursor in viewport coords (flipped / SwiftUI-like topLeading).
    var cursorInViewport: CGPoint?
    var cardFrames: [String: CGRect] = [:]

    private var pinchDisplayBase: CGFloat = 1.0
    private var isPinching = false
    private var isPanning = false
    private var panDragStart: CGSize = .zero
    private var scrollMonitor: Any?
    private var bakeWork: DispatchWorkItem?

    private let zoomMin: CGFloat = 0.5
    private let zoomMax: CGFloat = 2.0

    var displayZoom: CGFloat { layoutZoom * rubberScale }
    var canZoomIn: Bool { displayZoom < zoomMax - 0.001 }
    var canZoomOut: Bool { displayZoom > zoomMin + 0.001 }

    /// Focal point in the viewport: cursor if present, else center.
    func focalInViewport() -> CGPoint {
        if let cursorInViewport { return cursorInViewport }
        return CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
    }

    func zoomInTowardFocal() {
        nudgeRubber(factor: 1.1)
    }

    func zoomOutTowardFocal() {
        nudgeRubber(factor: 1 / 1.1)
    }

    func resetTowardFocal() {
        bakeWork?.cancel()
        let targetDisplay: CGFloat = 1
        let nextRubber = targetDisplay / max(layoutZoom, 0.001)
        setRubberScale(nextRubber, focal: focalInViewport())
        scheduleBake(delay: 0.12)
    }

    private func nudgeRubber(factor: CGFloat) {
        let targetDisplay = clamp(displayZoom * factor)
        let nextRubber = targetDisplay / max(layoutZoom, 0.001)
        setRubberScale(nextRubber, focal: focalInViewport())
        scheduleBake(delay: 0.14)
    }

    func applyPinch(_ magnification: CGFloat) {
        if !isPinching {
            isPinching = true
            pinchDisplayBase = displayZoom
            bakeWork?.cancel()
        }
        let targetDisplay = clamp(pinchDisplayBase * magnification)
        let nextRubber = targetDisplay / max(layoutZoom, 0.001)
        let focal = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        setRubberScale(nextRubber, focal: focal)
    }

    func endPinch() {
        isPinching = false
        bakeNow()
    }

    func panDragChanged(translation: CGSize) {
        if !isPanning {
            isPanning = true
            panDragStart = panOffset
        }
        panOffset = CGSize(
            width: panDragStart.width + translation.width,
            height: panDragStart.height + translation.height
        )
    }

    func panDragEnded() {
        isPanning = false
        panDragStart = panOffset
    }

    func applyScrollPan(deltaX: CGFloat, deltaY: CGFloat) {
        panOffset = CGSize(
            width: panOffset.width + deltaX,
            height: panOffset.height + deltaY
        )
    }

    func applyScrollZoom(step: CGFloat) {
        let targetDisplay = clamp(displayZoom + step)
        let nextRubber = targetDisplay / max(layoutZoom, 0.001)
        setRubberScale(nextRubber, focal: focalInViewport())
        scheduleBake(delay: 0.14)
    }

    /// Change rubber scale while keeping the content point under `focal` fixed on screen.
    private func setRubberScale(_ newRubber: CGFloat, focal: CGPoint) {
        let old = max(rubberScale, 0.0001)
        let next = max(0.01, newRubber)
        guard abs(next - old) > 0.00001 else { return }
        let factor = next / old
        // screen = p * rubber + offset  → keep screen(focal content) constant
        panOffset = CGSize(
            width: focal.x - (focal.x - panOffset.width) * factor,
            height: focal.y - (focal.y - panOffset.height) * factor
        )
        rubberScale = next
    }

    /// Place a content-space point at the viewport center.
    func centerContentPoint(_ point: CGPoint, in viewport: CGSize) {
        let r = max(rubberScale, 0.0001)
        panOffset = CGSize(
            width: viewport.width / 2 - point.x * r,
            height: viewport.height / 2 - point.y * r
        )
    }

    /// Bake rubber into layout. Offset stays — layout scales linearly with zoom.
    func bakeNow() {
        bakeWork?.cancel()
        bakeWork = nil
        let oldRubber = rubberScale
        let baked = snap(displayZoom)
        // Content point p in old layout becomes ~p*oldRubber in new layout space.
        // screen = p * oldRubber + offset (before)
        // after: layout' = L*oldRubber (approx), rubber=1, same p' = p*oldRubber
        // screen = p' * 1 + offset' = p*oldRubber + offset' → offset' = offset
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            layoutZoom = baked
            rubberScale = 1.0
            // offset unchanged
            _ = oldRubber
        }
    }

    private func scheduleBake(delay: TimeInterval) {
        bakeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.bakeNow()
        }
        bakeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, zoomMin), zoomMax)
    }

    private func snap(_ value: CGFloat) -> CGFloat {
        let clamped = clamp(value)
        return (clamped * 20).rounded() / 20
    }

    func installEventMonitors() {
        removeEventMonitors()
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.isHovered else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let dx = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.scrollingDeltaX * 3
            let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 3

            if flags.contains(.command), !flags.contains(.control) {
                let step = event.hasPreciseScrollingDeltas ? dy * 0.004 : dy * 0.06
                DispatchQueue.main.async { self.applyScrollZoom(step: step) }
                return nil
            }

            // Plain scroll → pan (natural: finger up moves content down ⇒ add delta)
            DispatchQueue.main.async {
                self.applyScrollPan(deltaX: dx, deltaY: dy)
            }
            return nil
        }
    }

    func removeEventMonitors() {
        bakeWork?.cancel()
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    deinit {
        removeEventMonitors()
    }
}

private enum OrgScrollAnchor {
    static func card(_ staffId: String) -> String { "org-card-\(staffId)" }
}

private struct OrgContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width * next.height > value.width * value.height {
            value = next
        }
    }
}

// MARK: - Layout (committed zoom multiplies real sizes)

private struct OrgLayout: Equatable {
    var zoom: CGFloat

    var cardWidth: CGFloat { 140 * zoom }
    var siblingGap: CGFloat { 24 * zoom }
    var centerGutter: CGFloat { 48 * zoom }
    var stackGap: CGFloat { 14 * zoom }
    var stem: CGFloat { 18 * zoom }
    var drop: CGFloat { 14 * zoom }
    var lineWidth: CGFloat { max(1, 2 * zoom) }
    var edgePad: CGFloat { max(1, 1 * zoom) }
    var padding: CGFloat { 16 * zoom }
    var rootSpacing: CGFloat { 28 * zoom }
    var cardPadding: CGFloat { 8 * zoom }
    var cardCorner: CGFloat { 10 * zoom }
    var nameIconGap: CGFloat { 4 * zoom }
    var cardStackSpacing: CGFloat { 3 * zoom }
    var connectorReserve: CGFloat { stem + drop }

    static let splitThreshold = 4
    static let lineColor = Color.secondary.opacity(0.6)

    var nameFont: Font { .system(size: 13 * zoom, weight: .semibold) }
    var metaFont: Font { .system(size: 10 * zoom) }
    var iconFont: Font { .system(size: 11 * zoom) }
}

private enum OrgChartSpace {
    static let name = "orgChart"
}

private enum OrgFanStyle: Equatable {
    case fan
    case splitSides(leftIds: [String], rightIds: [String])
}

private struct CardFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Node

private struct OrgNodeView: View {
    let node: StaffTreeNode
    let depth: Int
    let layout: OrgLayout
    let onSelect: (StaffNode) -> Void

    private var fanStyle: OrgFanStyle {
        let kids = node.children
        guard !kids.isEmpty else { return .fan }
        let allLeaves = kids.allSatisfy { $0.children.isEmpty }
        if allLeaves, kids.count >= OrgLayout.splitThreshold {
            let mid = (kids.count + 1) / 2
            return .splitSides(
                leftIds: kids.prefix(mid).map(\.staff.id),
                rightIds: kids.suffix(kids.count - mid).map(\.staff.id)
            )
        }
        return .fan
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            staffCard(node.staff, emphasized: depth == 0)
                .id(OrgScrollAnchor.card(node.staff.id))
                .background(cardAnchor(node.staff.id))

            if !node.children.isEmpty {
                Color.clear
                    .frame(height: layout.connectorReserve)
                childrenLayout(node.children, style: fanStyle)
            }
        }
        .overlayPreferenceValue(CardFrameKey.self) { frames in
            GeometryReader { geo in
                let origin = geo.frame(in: .named(OrgChartSpace.name)).origin
                OrgConnectorCanvas(
                    parentId: node.staff.id,
                    style: fanStyle,
                    directChildIds: node.children.map(\.staff.id),
                    frames: frames,
                    origin: origin,
                    layout: layout
                )
            }
        }
    }

    private func cardAnchor(_ id: String) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: CardFrameKey.self,
                value: [id: geo.frame(in: .named(OrgChartSpace.name))]
            )
        }
    }

    @ViewBuilder
    private func childrenLayout(_ children: [StaffTreeNode], style: OrgFanStyle) -> some View {
        switch style {
        case .fan:
            HStack(alignment: .top, spacing: layout.siblingGap) {
                ForEach(children) { child in
                    OrgNodeView(node: child, depth: depth + 1, layout: layout, onSelect: onSelect)
                }
            }
        case .splitSides(let leftIds, let rightIds):
            let byId = Dictionary(uniqueKeysWithValues: children.map { ($0.staff.id, $0) })
            HStack(alignment: .top, spacing: layout.centerGutter) {
                VStack(spacing: layout.stackGap) {
                    ForEach(leftIds, id: \.self) { id in
                        if let child = byId[id] {
                            OrgNodeView(node: child, depth: depth + 1, layout: layout, onSelect: onSelect)
                        }
                    }
                }
                VStack(spacing: layout.stackGap) {
                    ForEach(rightIds, id: \.self) { id in
                        if let child = byId[id] {
                            OrgNodeView(node: child, depth: depth + 1, layout: layout, onSelect: onSelect)
                        }
                    }
                }
            }
        }
    }

    private func staffCard(_ staff: StaffNode, emphasized: Bool) -> some View {
        Button {
            onSelect(staff)
        } label: {
            VStack(alignment: .leading, spacing: layout.cardStackSpacing) {
                HStack(spacing: layout.nameIconGap) {
                    Image(systemName: cardIcon(staff, emphasized: emphasized))
                        .font(layout.iconFont)
                    Text(staff.name)
                        .font(layout.nameFont)
                        .lineLimit(1)
                }
                Text(staff.team)
                    .font(layout.metaFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !staff.blurb.isEmpty {
                    Text(staff.blurb)
                        .font(layout.metaFont)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(layout.cardPadding)
            .frame(width: layout.cardWidth, alignment: .leading)
            .background(
                emphasized
                    ? Color.accentColor.opacity(0.18)
                    : Color.primary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: layout.cardCorner)
            )
            .overlay(
                RoundedRectangle(cornerRadius: layout.cardCorner)
                    .strokeBorder(
                        emphasized ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.22),
                        lineWidth: max(1, layout.zoom)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(staff.id)
    }

    private func cardIcon(_ staff: StaffNode, emphasized: Bool) -> String {
        if emphasized { return "crown.fill" }
        if staff.name.hasSuffix("-lead") || staff.name == "cto" {
            return "person.badge.key.fill"
        }
        return "person.fill"
    }
}

// MARK: - Connectors (edge-only; never through card interiors)

private struct OrgConnectorCanvas: View {
    let parentId: String
    let style: OrgFanStyle
    let directChildIds: [String]
    let frames: [String: CGRect]
    let origin: CGPoint
    let layout: OrgLayout

    var body: some View {
        Canvas { context, _ in
            guard let parentGlobal = frames[parentId] else { return }

            func local(_ r: CGRect) -> CGRect {
                CGRect(
                    x: r.minX - origin.x,
                    y: r.minY - origin.y,
                    width: r.width,
                    height: r.height
                )
            }

            let parent = local(parentGlobal)
            let parentBottom = CGPoint(x: parent.midX, y: parent.maxY + layout.edgePad)

            let direct: [(id: String, rect: CGRect)] = directChildIds.compactMap { id in
                frames[id].map { (id, local($0)) }
            }
            guard !direct.isEmpty else { return }

            var path = Path()
            switch style {
            case .fan:
                drawFan(path: &path, parentBottom: parentBottom, kids: direct.map(\.rect))
            case .splitSides(let leftIds, let rightIds):
                let left = leftIds.compactMap { id in direct.first { $0.id == id }?.rect }
                    .sorted { $0.minY < $1.minY }
                let right = rightIds.compactMap { id in direct.first { $0.id == id }?.rect }
                    .sorted { $0.minY < $1.minY }
                drawSplitSides(path: &path, parentBottom: parentBottom, left: left, right: right)
            }

            context.stroke(
                path,
                with: .color(OrgLayout.lineColor),
                style: StrokeStyle(
                    lineWidth: layout.lineWidth,
                    lineCap: .square,
                    lineJoin: .miter
                )
            )
        }
        .allowsHitTesting(false)
    }

    private func drawFan(path: inout Path, parentBottom: CGPoint, kids: [CGRect]) {
        let row = kids.sorted { $0.midX < $1.midX }
        guard let left = row.first, let right = row.last else { return }
        let y = (row.map(\.minY).min() ?? 0) - layout.drop

        path.move(to: parentBottom)
        path.addLine(to: CGPoint(x: parentBottom.x, y: y))

        if row.count == 1 {
            if abs(left.midX - parentBottom.x) > 0.5 {
                path.move(to: CGPoint(x: parentBottom.x, y: y))
                path.addLine(to: CGPoint(x: left.midX, y: y))
            }
        } else {
            path.move(to: CGPoint(x: left.midX, y: y))
            path.addLine(to: CGPoint(x: right.midX, y: y))
        }

        for kid in row {
            let top = kid.minY - layout.edgePad
            path.move(to: CGPoint(x: kid.midX, y: y))
            path.addLine(to: CGPoint(x: kid.midX, y: top))
        }
    }

    private func drawSplitSides(
        path: inout Path,
        parentBottom: CGPoint,
        left: [CGRect],
        right: [CGRect]
    ) {
        guard !left.isEmpty || !right.isEmpty else { return }

        let topY = ((left + right).map(\.minY).min() ?? 0) - layout.drop
        let leftEdge = left.map(\.maxX).max() ?? parentBottom.x
        let rightEdge = right.map(\.minX).min() ?? parentBottom.x
        let spineX: CGFloat = {
            if !left.isEmpty, !right.isEmpty {
                return (leftEdge + rightEdge) / 2
            }
            return parentBottom.x
        }()

        let lowestMidY = (left + right).map(\.midY).max() ?? topY

        path.move(to: parentBottom)
        path.addLine(to: CGPoint(x: parentBottom.x, y: topY))
        if abs(parentBottom.x - spineX) > 0.5 {
            path.addLine(to: CGPoint(x: spineX, y: topY))
        }

        path.move(to: CGPoint(x: spineX, y: topY))
        path.addLine(to: CGPoint(x: spineX, y: lowestMidY))

        for card in left {
            let y = card.midY
            let edgeX = card.maxX + layout.edgePad
            path.move(to: CGPoint(x: spineX, y: y))
            path.addLine(to: CGPoint(x: edgeX, y: y))
        }

        for card in right {
            let y = card.midY
            let edgeX = card.minX - layout.edgePad
            path.move(to: CGPoint(x: spineX, y: y))
            path.addLine(to: CGPoint(x: edgeX, y: y))
        }
    }
}

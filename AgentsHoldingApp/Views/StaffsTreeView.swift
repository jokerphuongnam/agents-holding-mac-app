import AppKit
import SwiftUI

/// Staffs org graph — top is senior, below are reports.
///
/// Zoom is **card-locked** (desk-garden sized trees):
/// 1. On zoom start, lock the card under the pointer (or nearest / viewport-center card).
/// 2. Every scale change re-pins that same point on the card under the focal screen point.
/// 3. After layout bake, re-pin again when new card frames arrive.
/// Pan (drag / scroll without ⌘) clears the lock.
struct StaffsTreeView: View {
    let roots: [StaffTreeNode]
    let onSelect: (StaffNode) -> Void

    private let viewportMaxHeight: CGFloat = 560

    @StateObject private var zoomState = OrgGraphZoomState()
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
                    .scaleEffect(zoomState.rubberScale, anchor: .topLeading)
                    .offset(zoomState.panOffset)
                    .gesture(panDragGesture)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .background(ViewportHostView(bridge: zoomState.viewportBridge))
            .onAppear {
                zoomState.viewportSize = viewportGeo.size
                zoomState.installEventMonitors()
            }
            .onChange(of: viewportGeo.size) { _, newSize in
                zoomState.viewportSize = newSize
            }
            .onDisappear {
                zoomState.removeEventMonitors()
            }
            .onHover { hovering in
                zoomState.isHovered = hovering
            }
            .simultaneousGesture(pinchZoomGesture)
            .onPreferenceChange(CardFrameKey.self) { frames in
                zoomState.cardFrames = frames
                zoomState.repinLockedCardIfNeeded()
                centerCEOIfNeeded(viewport: viewportGeo.size)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 280, maxHeight: viewportMaxHeight)
        .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var zoomToolbar: some View {
        HStack(spacing: 6) {
            Button { zoomState.zoomOutTowardFocal() } label: {
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

            Button { zoomState.zoomInTowardFocal() } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help(L10n.staffsTreeZoomIn)
            .disabled(!zoomState.canZoomIn)
            .accessibilityLabel(L10n.staffsTreeZoomIn)

            Button(L10n.staffsTreeZoomReset) { zoomState.resetTowardFocal() }
                .buttonStyle(.borderless)
                .disabled(abs(zoomState.displayZoom - 1) < 0.01)
        }
        .controlSize(.small)
    }

    private var graphContent: some View {
        let layout = self.layout
        return VStack(alignment: .leading, spacing: layout.rootSpacing) {
            ForEach(roots) { root in
                OrgNodeView(node: root, depth: 0, layout: layout, onSelect: onSelect)
            }
        }
        .padding(layout.padding)
        // topLeading so layoutZoom bake scales from a stable origin (desk-garden wide trees).
        .frame(minWidth: 320 * layout.zoom, alignment: .topLeading)
        .coordinateSpace(name: OrgChartSpace.name)
    }

    private var panDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in zoomState.panDragChanged(translation: value.translation) }
            .onEnded { _ in zoomState.panDragEnded() }
    }

    private var pinchZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in zoomState.applyPinch(value) }
            .onEnded { _ in zoomState.endPinch() }
    }

    private func centerCEOIfNeeded(viewport: CGSize) {
        guard !didCenterCEO, let focusStaffId, viewport.width > 1, viewport.height > 1 else { return }
        guard let frame = zoomState.cardFrames[focusStaffId] else { return }
        zoomState.centerContentPoint(CGPoint(x: frame.midX, y: frame.midY), in: viewport)
        didCenterCEO = true
    }
}

// MARK: - Viewport host (mouse → focal in view coords)

private final class ViewportBridge {
    weak var view: NSView?

    /// Mouse location in the viewport view's flipped coordinates.
    func mouseInView() -> CGPoint? {
        guard let view, let window = view.window else { return nil }
        let mouseInWindow = window.mouseLocationOutsideOfEventStream
        var p = view.convert(mouseInWindow, from: nil)
        if !view.isFlipped {
            p.y = view.bounds.height - p.y
        }
        guard view.bounds.insetBy(dx: -1, dy: -1).contains(p) else { return nil }
        return CGPoint(x: p.x, y: p.y)
    }
}

private struct ViewportHostView: NSViewRepresentable {
    let bridge: ViewportBridge

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = false
        DispatchQueue.main.async { bridge.view = view.superview ?? view }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            // Prefer the SwiftUI-backed superview that fills the viewport.
            bridge.view = nsView.superview ?? nsView
        }
    }
}

// MARK: - Card lock + zoom / pan

private struct CardLock: Equatable {
    var id: String
    /// Point inside the card, relative 0...1 (0.5,0.5 = card center).
    var rel: CGPoint
}

/// screen = contentPoint * rubberScale + panOffset (scale anchor = topLeading)
private final class OrgGraphZoomState: ObservableObject {
    @Published var layoutZoom: CGFloat = 1.0
    @Published var rubberScale: CGFloat = 1.0
    @Published var panOffset: CGSize = .zero

    let viewportBridge = ViewportBridge()
    var isHovered = false
    var viewportSize: CGSize = .zero
    var cardFrames: [String: CGRect] = [:]

    private var lock: CardLock?
    private var lockedFocal: CGPoint?
    private var pinchDisplayBase: CGFloat = 1.0
    private var isPinching = false
    private var isPanning = false
    private var panDragStart: CGSize = .zero
    private var scrollMonitor: Any?
    private var bakeWork: DispatchWorkItem?
    private var pendingRepin = false

    private let zoomMin: CGFloat = 0.5
    private let zoomMax: CGFloat = 2.0

    var displayZoom: CGFloat { layoutZoom * rubberScale }
    var canZoomIn: Bool { displayZoom < zoomMax - 0.001 }
    var canZoomOut: Bool { displayZoom > zoomMin + 0.001 }

    /// Prefer live mouse in viewport; else viewport center.
    func focalInViewport() -> CGPoint {
        if let mouse = viewportBridge.mouseInView() {
            return mouse
        }
        return CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
    }

    func zoomInTowardFocal() { nudgeRubber(factor: 1.1) }
    func zoomOutTowardFocal() { nudgeRubber(factor: 1 / 1.1) }

    func resetTowardFocal() {
        bakeWork?.cancel()
        let focal = focalInViewport()
        ensureLock(at: focal)
        let nextRubber = 1 / max(layoutZoom, 0.001)
        setRubberScale(nextRubber, focal: focal)
        scheduleBake(delay: 0.12)
    }

    private func nudgeRubber(factor: CGFloat) {
        let focal = focalInViewport()
        ensureLock(at: focal)
        let targetDisplay = clamp(displayZoom * factor)
        let nextRubber = targetDisplay / max(layoutZoom, 0.001)
        setRubberScale(nextRubber, focal: focal)
        scheduleBake(delay: 0.14)
    }

    func applyPinch(_ magnification: CGFloat) {
        let focal = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        if !isPinching {
            isPinching = true
            pinchDisplayBase = displayZoom
            ensureLock(at: focal)
            bakeWork?.cancel()
        }
        let targetDisplay = clamp(pinchDisplayBase * magnification)
        let nextRubber = targetDisplay / max(layoutZoom, 0.001)
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
            clearLock()
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
        clearLock()
        panOffset = CGSize(
            width: panOffset.width + deltaX,
            height: panOffset.height + deltaY
        )
    }

    func applyScrollZoom(step: CGFloat) {
        let focal = focalInViewport()
        ensureLock(at: focal)
        let targetDisplay = clamp(displayZoom + step)
        let nextRubber = targetDisplay / max(layoutZoom, 0.001)
        setRubberScale(nextRubber, focal: focal)
        scheduleBake(delay: 0.14)
    }

    private func setRubberScale(_ newRubber: CGFloat, focal: CGPoint) {
        let next = max(0.01, newRubber)
        guard abs(next - rubberScale) > 0.00001 else {
            repin(focal: focal)
            return
        }
        rubberScale = next
        lockedFocal = focal
        repin(focal: focal)
    }

    /// Keep the locked card point glued under `focal`.
    private func repin(focal: CGPoint) {
        guard let lock, let frame = cardFrames[lock.id] else { return }
        let contentPt = CGPoint(
            x: frame.minX + lock.rel.x * frame.width,
            y: frame.minY + lock.rel.y * frame.height
        )
        panOffset = CGSize(
            width: focal.x - contentPt.x * rubberScale,
            height: focal.y - contentPt.y * rubberScale
        )
        lockedFocal = focal
    }

    func repinLockedCardIfNeeded() {
        guard pendingRepin || lock != nil, let focal = lockedFocal ?? optionalCenterFocal() else { return }
        repin(focal: focal)
        pendingRepin = false
    }

    private func optionalCenterFocal() -> CGPoint? {
        guard viewportSize.width > 1 else { return nil }
        return CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
    }

    private func ensureLock(at focal: CGPoint) {
        if lock != nil { return }
        let contentPt = contentPoint(atViewport: focal)
        lock = makeLock(for: contentPt)
        lockedFocal = focal
    }

    private func clearLock() {
        lock = nil
        lockedFocal = nil
        pendingRepin = false
    }

    private func contentPoint(atViewport focal: CGPoint) -> CGPoint {
        let r = max(rubberScale, 0.0001)
        return CGPoint(
            x: (focal.x - panOffset.width) / r,
            y: (focal.y - panOffset.height) / r
        )
    }

    /// Lock card under point; if none, nearest card center (desk-garden dense fans).
    private func makeLock(for contentPt: CGPoint) -> CardLock? {
        guard !cardFrames.isEmpty else { return nil }
        var containing: (id: String, frame: CGRect)?
        var nearest: (id: String, frame: CGRect, dist: CGFloat)?
        for (id, frame) in cardFrames {
            if frame.contains(contentPt) {
                containing = (id, frame)
                break
            }
            let d = hypot(frame.midX - contentPt.x, frame.midY - contentPt.y)
            if nearest == nil || d < nearest!.dist {
                nearest = (id, frame, d)
            }
        }
        let picked = containing ?? nearest.map { ($0.id, $0.frame) }
        guard let picked else { return nil }
        let frame = picked.1
        let rel: CGPoint
        if containing != nil {
            rel = CGPoint(
                x: frame.width > 0 ? (contentPt.x - frame.minX) / frame.width : 0.5,
                y: frame.height > 0 ? (contentPt.y - frame.minY) / frame.height : 0.5
            )
        } else {
            rel = CGPoint(x: 0.5, y: 0.5)
        }
        return CardLock(id: picked.0, rel: rel)
    }

    func centerContentPoint(_ point: CGPoint, in viewport: CGSize) {
        let r = max(rubberScale, 0.0001)
        panOffset = CGSize(
            width: viewport.width / 2 - point.x * r,
            height: viewport.height / 2 - point.y * r
        )
    }

    /// Bake rubber → layout. Exact multiply (no snap) + repin locked card after frames refresh.
    func bakeNow() {
        bakeWork?.cancel()
        bakeWork = nil
        let focal = lockedFocal ?? focalInViewport()
        ensureLock(at: focal)
        let r = rubberScale
        guard abs(r - 1) > 0.0001 else { return }
        let newLayout = clamp(layoutZoom * r)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            layoutZoom = newLayout
            rubberScale = 1.0
        }
        lockedFocal = focal
        pendingRepin = true
        // Frames update async; also attempt immediate repin with scaled guess.
        // Relative lock inside card remains valid after uniform-ish layout scale.
        DispatchQueue.main.async { [weak self] in
            self?.repinLockedCardIfNeeded()
        }
    }

    private func scheduleBake(delay: TimeInterval) {
        bakeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.bakeNow() }
        bakeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, zoomMin), zoomMax)
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

            DispatchQueue.main.async { self.applyScrollPan(deltaX: dx, deltaY: dy) }
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

    deinit { removeEventMonitors() }
}

private enum OrgScrollAnchor {
    static func card(_ staffId: String) -> String { "org-card-\(staffId)" }
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

import AppKit
import SwiftUI

/// Staffs org graph — top is senior, below are reports.
///
/// Zoom (smooth then crisp):
/// - While ⌘+scrolling / trackpad pinch (2 fingers) / tapping ±: only `scaleEffect` + pan offset.
/// - After the user **stops** zooming (~0.3s idle): bake into layout metrics and regenerate the tree crisp.
/// - Card-lock keeps the card under the pointer fixed for the whole gesture (desk-garden sized trees).
/// Pan (drag / scroll without ⌘) clears the lock.
struct StaffsTreeView: View {
    let roots: [StaffTreeNode]
    var showsHeading: Bool = true
    /// Cap for the embedded graph. `nil` fills the parent (detached window).
    var viewportMaxHeight: CGFloat? = 900
    /// When set, shows a control that opens this graph in a dedicated window.
    var windowID: StaffsTreeWindowID? = nil
    let onSelect: (StaffNode) -> Void

    @Environment(\.openWindow) private var openWindow
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
                if showsHeading {
                    Label(L10n.staffsTree, systemImage: "person.3")
                        .font(.headline)
                }
                Spacer()
                if !roots.isEmpty {
                    zoomToolbar
                    if let windowID {
                        Button {
                            openWindow(id: "staffs-tree", value: windowID)
                        } label: {
                            Label(L10nLookup("staffs_tree_open_window", "Localizable", "Open in new window"),
                                  systemImage: "macwindow")
                        }
                        .buttonStyle(.borderless)
                        .help(L10nLookup("staffs_tree_open_window_help", "Localizable", "Open the staffs org graph in a dedicated window"))
                        .controlSize(.small)
                    }
                }
            }
            if showsHeading {
                Text(L10n.staffsTreeHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                    // Live zoom is cheap scale only — layoutZoom rebuild waits until idle bake.
                    .scaleEffect(zoomState.live.rubber, anchor: .topLeading)
                    .offset(zoomState.live.offset)
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
            // Prefer trackpad pinch over pan when both could match.
            .highPriorityGesture(pinchZoomGesture)
            .onPreferenceChange(CardFrameKey.self) { frames in
                zoomState.cardFrames = frames
                zoomState.repinLockedCardIfNeeded()
                centerCEOIfNeeded(viewport: viewportGeo.size)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: viewportMaxHeight == nil ? 480 : 360,
            maxHeight: viewportMaxHeight
        )
        .frame(maxHeight: viewportMaxHeight == nil ? .infinity : nil)
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
                .opacity(zoomState.isLiveZooming ? 0.7 : 1)

            Button { zoomState.zoomInTowardFocal() } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help(L10n.staffsTreeZoomIn)
            .disabled(!zoomState.canZoomIn)
            .accessibilityLabel(L10n.staffsTreeZoomIn)

            Button(L10n.staffsTreeZoomReset) { zoomState.resetTowardFocal() }
                .buttonStyle(.borderless)
                .disabled(abs(zoomState.displayZoom - 1) < 0.01 && abs(zoomState.live.rubber - 1) < 0.01)
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
            .onChanged { value in zoomState.applySwiftUIPinch(value) }
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

/// Live transform published as one value so each scroll tick only refreshes once.
private struct LiveZoomTransform: Equatable {
    var rubber: CGFloat = 1.0
    var offset: CGSize = .zero
}

/// screen = contentPoint * live.rubber + live.offset (scale anchor = topLeading)
///
/// While the user is zooming: mutate `live` only (scaleEffect).
/// When idle: bake into `layoutZoom` and regenerate the graph for sharp text.
private final class OrgGraphZoomState: ObservableObject {
    @Published var layoutZoom: CGFloat = 1.0
    @Published var live = LiveZoomTransform()
    @Published private(set) var isLiveZooming = false

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
    private var eventMonitor: Any?
    private var bakeWork: DispatchWorkItem?
    private var pendingRepin = false

    private let zoomMin: CGFloat = 0.5
    private let zoomMax: CGFloat = 2.0
    /// Wait until scroll/pinch stops before regenerating the tree.
    private let idleBakeDelay: TimeInterval = 0.32
    private let buttonBakeDelay: TimeInterval = 0.22

    var displayZoom: CGFloat { layoutZoom * live.rubber }
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
        isLiveZooming = true
        let focal = focalInViewport()
        ensureLock(at: focal)
        let nextRubber = 1 / max(layoutZoom, 0.001)
        setLiveRubber(nextRubber, focal: focal)
        scheduleBake(delay: buttonBakeDelay)
    }

    private func nudgeRubber(factor: CGFloat) {
        bakeWork?.cancel()
        isLiveZooming = true
        let focal = focalInViewport()
        ensureLock(at: focal)
        let targetDisplay = clamp(displayZoom * factor)
        let nextRubber = targetDisplay / max(layoutZoom, 0.001)
        setLiveRubber(nextRubber, focal: focal)
        scheduleBake(delay: buttonBakeDelay)
    }

    /// SwiftUI `MagnificationGesture` — value is absolute scale from gesture start (1.0…).
    func applySwiftUIPinch(_ magnification: CGFloat) {
        let focal = focalInViewport()
        if !isPinching {
            isPinching = true
            isLiveZooming = true
            pinchDisplayBase = displayZoom
            ensureLock(at: focal)
            bakeWork?.cancel()
        }
        let targetDisplay = clamp(pinchDisplayBase * magnification)
        let nextRubber = targetDisplay / max(layoutZoom, 0.001)
        setLiveRubber(nextRubber, focal: focal)
    }

    /// AppKit trackpad pinch — `delta` is incremental (`event.magnification`).
    func applyTrackpadMagnify(delta: CGFloat, phase: NSEvent.Phase) {
        let focal = focalInViewport()
        if phase.contains(.began) || !isPinching {
            isPinching = true
            isLiveZooming = true
            ensureLock(at: focal)
            bakeWork?.cancel()
        }
        // Incremental: newZoom = current * (1 + delta)
        let targetDisplay = clamp(displayZoom * (1 + delta))
        let nextRubber = targetDisplay / max(layoutZoom, 0.001)
        setLiveRubber(nextRubber, focal: focal)

        if phase.contains(.ended) || phase.contains(.cancelled) {
            isPinching = false
            scheduleBake(delay: 0.05)
        } else {
            // Some devices omit ended — idle bake when fingers stop.
            scheduleBake(delay: idleBakeDelay)
        }
    }

    func endPinch() {
        isPinching = false
        // Regenerate once the pinch finishes (not during the gesture).
        scheduleBake(delay: 0.05)
    }

    func panDragChanged(translation: CGSize) {
        if !isPanning {
            isPanning = true
            panDragStart = live.offset
            clearLock()
            // Panning cancels a pending regenerate — keep current rubber until idle zoom again.
            bakeWork?.cancel()
        }
        var next = live
        next.offset = CGSize(
            width: panDragStart.width + translation.width,
            height: panDragStart.height + translation.height
        )
        live = next
    }

    func panDragEnded() {
        isPanning = false
        panDragStart = live.offset
    }

    func applyScrollPan(deltaX: CGFloat, deltaY: CGFloat) {
        clearLock()
        bakeWork?.cancel()
        var next = live
        next.offset = CGSize(
            width: live.offset.width + deltaX,
            height: live.offset.height + deltaY
        )
        live = next
    }

    func applyScrollZoom(step: CGFloat) {
        bakeWork?.cancel()
        isLiveZooming = true
        let focal = focalInViewport()
        ensureLock(at: focal)
        let targetDisplay = clamp(displayZoom + step)
        let nextRubber = targetDisplay / max(layoutZoom, 0.001)
        setLiveRubber(nextRubber, focal: focal)
        // Only regenerate after the user stops scrolling.
        scheduleBake(delay: idleBakeDelay)
    }

    /// Live scale only — does not touch `layoutZoom` / does not rebuild the graph.
    private func setLiveRubber(_ newRubber: CGFloat, focal: CGPoint) {
        let old = max(live.rubber, 0.0001)
        let next = max(0.01, newRubber)
        guard abs(next - old) > 0.00001 else { return }
        let factor = next / old
        // Keep the content point under `focal` fixed (smooth; no frame lookup needed).
        var transform = live
        transform.offset = CGSize(
            width: focal.x - (focal.x - live.offset.width) * factor,
            height: focal.y - (focal.y - live.offset.height) * factor
        )
        transform.rubber = next
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            live = transform
        }
        lockedFocal = focal
    }

    /// After layout regenerate, glue the locked card back under the focal point.
    private func repinFromCardFrames(focal: CGPoint) {
        guard let lock, let frame = cardFrames[lock.id] else { return }
        let contentPt = CGPoint(
            x: frame.minX + lock.rel.x * frame.width,
            y: frame.minY + lock.rel.y * frame.height
        )
        var transform = live
        transform.offset = CGSize(
            width: focal.x - contentPt.x * live.rubber,
            height: focal.y - contentPt.y * live.rubber
        )
        live = transform
        lockedFocal = focal
    }

    func repinLockedCardIfNeeded() {
        // Only after bake — never during live scaleEffect zoom (avoids jitter).
        guard pendingRepin, let focal = lockedFocal ?? optionalCenterFocal() else { return }
        repinFromCardFrames(focal: focal)
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
        let r = max(live.rubber, 0.0001)
        return CGPoint(
            x: (focal.x - live.offset.width) / r,
            y: (focal.y - live.offset.height) / r
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
        let r = max(live.rubber, 0.0001)
        var transform = live
        transform.offset = CGSize(
            width: viewport.width / 2 - point.x * r,
            height: viewport.height / 2 - point.y * r
        )
        live = transform
    }

    /// Idle: regenerate graph at the new zoom (crisp), then re-pin the locked card.
    func bakeNow() {
        bakeWork?.cancel()
        bakeWork = nil
        let focal = lockedFocal ?? focalInViewport()
        ensureLock(at: focal)
        let r = live.rubber
        guard abs(r - 1) > 0.0001 else {
            isLiveZooming = false
            return
        }
        let newLayout = clamp(layoutZoom * r)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            layoutZoom = newLayout
            live = LiveZoomTransform(rubber: 1.0, offset: live.offset)
            isLiveZooming = false
        }
        lockedFocal = focal
        pendingRepin = true
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
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
            guard let self, self.isHovered else { return event }

            // Trackpad pinch (2 fingers) — native magnify events.
            if event.type == .magnify {
                let delta = event.magnification
                let phase = event.phase
                DispatchQueue.main.async {
                    self.applyTrackpadMagnify(delta: delta, phase: phase)
                }
                return nil
            }

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
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
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

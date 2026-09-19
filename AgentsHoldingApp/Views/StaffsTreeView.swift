import AppKit
import SwiftUI

/// Staffs org graph — top is senior, below are reports.
/// Connectors **stop at card edges** (never run through a card body).
/// Large leaf teams: left/right stacks + center gutter spine.
///
/// Zoom is hybrid for smoothness + sharpness:
/// - while ⌘+scrolling / pinching / tapping +−: cheap `scaleEffect` (`rubberScale`)
/// - after a short idle: bake into layout metrics (`layoutZoom`) so text stays crisp
/// ScrollView viewport stays fixed; only graph content zooms.
struct StaffsTreeView: View {
    let roots: [StaffTreeNode]
    let onSelect: (StaffNode) -> Void

    private let viewportMaxHeight: CGFloat = 560

    @StateObject private var zoomState = OrgGraphZoomState()
    @State private var baseContentSize: CGSize = .zero

    /// Prefer classic CEO roots when centering the viewport.
    private var focusRootId: String? {
        let ids = roots.map(\.staff.id)
        if let ceo = ids.first(where: { $0 == "holding-ceo" || $0 == "ceo" }) {
            return OrgScrollAnchor.card(ceo)
        }
        return roots.first.map { OrgScrollAnchor.card($0.staff.id) }
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
                ScrollViewReader { proxy in
                    ScrollView([.horizontal, .vertical], showsIndicators: true) {
                        graphContent
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: OrgContentSizeKey.self,
                                        value: geo.size
                                    )
                                }
                            )
                            .background(GraphScrollViewLocator(bridge: zoomState.scrollBridge))
                            // Smooth interactive zoom (bitmap). Baked to layout after idle.
                            // topLeading + scroll compensation keeps the viewport focal point stable.
                            .scaleEffect(zoomState.rubberScale, anchor: .topLeading)
                            .frame(
                                width: scaledWidth,
                                height: scaledHeight,
                                alignment: .topLeading
                            )
                    }
                    .frame(maxWidth: .infinity, minHeight: 280, maxHeight: viewportMaxHeight, alignment: .topLeading)
                    .clipped()
                    .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onHover { zoomState.isHovered = $0 }
                    .simultaneousGesture(pinchZoomGesture)
                    .onAppear {
                        zoomState.installCommandScrollMonitor()
                        scrollCEOToCenter(proxy)
                    }
                    .onDisappear {
                        zoomState.removeCommandScrollMonitor()
                    }
                    .onChange(of: focusRootId) { _, _ in
                        scrollCEOToCenter(proxy)
                    }
                    .onPreferenceChange(OrgContentSizeKey.self) { newSize in
                        guard newSize.width > 1, newSize.height > 1 else { return }
                        baseContentSize = newSize
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scaledWidth: CGFloat? {
        baseContentSize.width > 1 ? baseContentSize.width * zoomState.rubberScale : nil
    }

    private var scaledHeight: CGFloat? {
        baseContentSize.height > 1 ? baseContentSize.height * zoomState.rubberScale : nil
    }

    private var zoomToolbar: some View {
        HStack(spacing: 6) {
            Button {
                zoomState.zoomOutAnimated()
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
                zoomState.zoomInAnimated()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help(L10n.staffsTreeZoomIn)
            .disabled(!zoomState.canZoomIn)
            .accessibilityLabel(L10n.staffsTreeZoomIn)

            Button(L10n.staffsTreeZoomReset) {
                zoomState.resetAnimated()
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

    private var pinchZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoomState.applyPinch(value)
            }
            .onEnded { _ in
                zoomState.endPinch()
            }
    }

    /// Center the CEO card in the graph viewport (after layout settles).
    private func scrollCEOToCenter(_ proxy: ScrollViewProxy) {
        guard let id = focusRootId else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(id, anchor: .center)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }
}

// MARK: - Scroll bridge (keep viewport focal point while zooming)

private final class GraphScrollBridge {
    weak var scrollView: NSScrollView?

    /// After content scale changes from `oldRubber` → `newRubber` (topLeading),
    /// re-scroll so the same document point stays under the viewport center.
    func preserveCenter(oldRubber: CGFloat, newRubber: CGFloat) {
        guard let scrollView, oldRubber > 0.0001 else { return }
        let factor = newRubber / oldRubber
        guard abs(factor - 1) > 0.00001 else { return }
        let visible = scrollView.contentView.documentVisibleRect
        let targetMid = CGPoint(x: visible.midX * factor, y: visible.midY * factor)
        // Wait one turn so SwiftUI applies the new content size first.
        DispatchQueue.main.async { [weak self] in
            self?.scrollSoCenterIs(targetMid)
        }
    }

    /// After layout bake (document size may change slightly), keep the same relative center.
    func preserveNormalizedCenter(_ normalized: CGPoint) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let scrollView, let doc = scrollView.documentView else { return }
            let size = doc.bounds.size
            guard size.width > 1, size.height > 1 else { return }
            let mid = CGPoint(x: normalized.x * size.width, y: normalized.y * size.height)
            self.scrollSoCenterIs(mid)
        }
    }

    func normalizedCenter() -> CGPoint? {
        guard let scrollView, let doc = scrollView.documentView else { return nil }
        let size = doc.bounds.size
        guard size.width > 1, size.height > 1 else { return nil }
        let visible = scrollView.contentView.documentVisibleRect
        return CGPoint(x: visible.midX / size.width, y: visible.midY / size.height)
    }

    private func scrollSoCenterIs(_ mid: CGPoint) {
        guard let scrollView else { return }
        let visible = scrollView.contentView.documentVisibleRect
        let doc = scrollView.documentView?.bounds.size ?? .zero
        let maxX = max(0, doc.width - visible.width)
        let maxY = max(0, doc.height - visible.height)
        let origin = NSPoint(
            x: min(max(0, mid.x - visible.width / 2), maxX),
            y: min(max(0, mid.y - visible.height / 2), maxY)
        )
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

/// Finds the enclosing `NSScrollView` from inside SwiftUI content.
private struct GraphScrollViewLocator: NSViewRepresentable {
    let bridge: GraphScrollBridge

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.isHidden = true
        DispatchQueue.main.async {
            bridge.scrollView = view.enclosingScrollView
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            bridge.scrollView = nsView.enclosingScrollView
        }
    }
}

// MARK: - Zoom state (smooth rubber + crisp bake)

/// `rubberScale` = live scaleEffect (smooth). `layoutZoom` = real metrics (crisp after idle).
private final class OrgGraphZoomState: ObservableObject {
    @Published var layoutZoom: CGFloat = 1.0
    @Published var rubberScale: CGFloat = 1.0

    var isHovered = false
    let scrollBridge = GraphScrollBridge()
    private var pinchDisplayBase: CGFloat = 1.0
    private var isPinching = false
    private var scrollMonitor: Any?
    private var bakeWork: DispatchWorkItem?

    private let zoomMin: CGFloat = 0.5
    private let zoomMax: CGFloat = 2.0

    var displayZoom: CGFloat { layoutZoom * rubberScale }
    var canZoomIn: Bool { displayZoom < zoomMax - 0.001 }
    var canZoomOut: Bool { displayZoom > zoomMin + 0.001 }

    func resetAnimated() {
        bakeWork?.cancel()
        let targetRubber = 1 / max(layoutZoom, 0.001)
        setRubberScale(targetRubber)
        scheduleBake(delay: 0.12)
    }

    func zoomInAnimated() {
        nudgeRubber(factor: 1.1)
    }

    func zoomOutAnimated() {
        nudgeRubber(factor: 1 / 1.1)
    }

    private func nudgeRubber(factor: CGFloat) {
        let targetDisplay = clamp(displayZoom * factor)
        let nextRubber = targetDisplay / max(layoutZoom, 0.001)
        setRubberScale(nextRubber)
        scheduleBake(delay: 0.14)
    }

    func applyPinch(_ magnification: CGFloat) {
        if !isPinching {
            isPinching = true
            pinchDisplayBase = displayZoom
            bakeWork?.cancel()
        }
        let targetDisplay = clamp(pinchDisplayBase * magnification)
        setRubberScale(targetDisplay / max(layoutZoom, 0.001))
    }

    func endPinch() {
        isPinching = false
        pinchDisplayBase = displayZoom
        bakeNow()
    }

    func applyScrollStep(_ step: CGFloat) {
        let targetDisplay = clamp(displayZoom + step)
        setRubberScale(targetDisplay / max(layoutZoom, 0.001))
        scheduleBake(delay: 0.14)
    }

    /// Set rubber scale and keep the same document point under the viewport center.
    private func setRubberScale(_ newRubber: CGFloat) {
        let old = rubberScale
        let next = max(0.01, newRubber)
        guard abs(next - old) > 0.00001 else { return }
        rubberScale = next
        scrollBridge.preserveCenter(oldRubber: old, newRubber: next)
    }

    /// Collapse rubber into layout metrics (same visual size → swap blur for crisp type).
    func bakeNow() {
        bakeWork?.cancel()
        bakeWork = nil
        let baked = snap(displayZoom)
        // Capture focal point before document size changes.
        let normalized = scrollBridge.normalizedCenter()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            layoutZoom = baked
            rubberScale = 1.0
            pinchDisplayBase = baked
        }
        if let normalized {
            scrollBridge.preserveNormalizedCenter(normalized)
            // Second pass after layout settles.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                self?.scrollBridge.preserveNormalizedCenter(normalized)
            }
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

    /// ⌘ + scroll zooms graph content. (⌃+scroll is macOS screen zoom — do not use.)
    func installCommandScrollMonitor() {
        removeCommandScrollMonitor()
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.isHovered else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command), !flags.contains(.control) else {
                return event
            }
            let delta = event.scrollingDeltaY
            let step = event.hasPreciseScrollingDeltas ? delta * 0.004 : delta * 0.06
            DispatchQueue.main.async {
                self.applyScrollStep(step)
            }
            return nil
        }
    }

    func removeCommandScrollMonitor() {
        bakeWork?.cancel()
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    deinit {
        removeCommandScrollMonitor()
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

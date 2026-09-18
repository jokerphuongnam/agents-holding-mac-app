import AppKit
import SwiftUI

/// Staffs org graph — top is senior, below are reports.
/// Connectors **stop at card edges** (never run through a card body).
/// Large leaf teams: left/right stacks + center gutter spine.
/// Zoom: **Control + scroll wheel** (also trackpad pinch).
struct StaffsTreeView: View {
    let roots: [StaffTreeNode]
    let onSelect: (StaffNode) -> Void

    private let viewportMaxHeight: CGFloat = 560

    @StateObject private var zoomState = OrgGraphZoomState()
    @State private var contentSize: CGSize = .zero

    /// Prefer classic CEO roots when centering the viewport.
    private var focusRootId: String? {
        let ids = roots.map(\.staff.id)
        if let ceo = ids.first(where: { $0 == "holding-ceo" || $0 == "ceo" }) {
            return OrgScrollAnchor.card(ceo)
        }
        return roots.first.map { OrgScrollAnchor.card($0.staff.id) }
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
                            .scaleEffect(zoomState.zoom, anchor: .topLeading)
                            .frame(
                                width: max(contentSize.width * zoomState.zoom, 320 * zoomState.zoom),
                                height: max(contentSize.height * zoomState.zoom, 1),
                                alignment: .topLeading
                            )
                    }
                    .frame(maxWidth: .infinity, maxHeight: viewportMaxHeight, alignment: .topLeading)
                    .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .onHover { zoomState.isHovered = $0 }
                    .gesture(pinchZoomGesture)
                    .onAppear {
                        zoomState.installControlScrollMonitor()
                        scrollCEOToCenter(proxy)
                    }
                    .onDisappear {
                        zoomState.removeControlScrollMonitor()
                    }
                    .onChange(of: focusRootId) { _, _ in
                        scrollCEOToCenter(proxy)
                    }
                    .onPreferenceChange(OrgContentSizeKey.self) { contentSize = $0 }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var zoomToolbar: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { zoomState.zoomOut() }
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help(L10n.staffsTreeZoomOut)
            .disabled(!zoomState.canZoomOut)
            .accessibilityLabel(L10n.staffsTreeZoomOut)

            Text("\(Int((zoomState.zoom * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 36, alignment: .center)

            Button {
                withAnimation(.easeOut(duration: 0.15)) { zoomState.zoomIn() }
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help(L10n.staffsTreeZoomIn)
            .disabled(!zoomState.canZoomIn)
            .accessibilityLabel(L10n.staffsTreeZoomIn)

            Button(L10n.staffsTreeZoomReset) {
                withAnimation(.easeOut(duration: 0.2)) { zoomState.reset() }
            }
            .buttonStyle(.borderless)
            .disabled(abs(zoomState.zoom - 1) < 0.01)
        }
        .controlSize(.small)
    }

    private var graphContent: some View {
        VStack(alignment: .center, spacing: 28) {
            ForEach(roots) { root in
                OrgNodeView(node: root, depth: 0, onSelect: onSelect)
            }
        }
        .padding(16)
        .frame(minWidth: 320, alignment: .top)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }
}

/// Reference-type zoom state so Control+scroll NSEvent monitor sees live hover/zoom.
private final class OrgGraphZoomState: ObservableObject {
    @Published var zoom: CGFloat = 1.0
    var isHovered = false
    private var pinchBase: CGFloat = 1.0
    private var scrollMonitor: Any?

    private let zoomMin: CGFloat = 0.4
    private let zoomMax: CGFloat = 2.5

    var canZoomIn: Bool { zoom < zoomMax - 0.001 }
    var canZoomOut: Bool { zoom > zoomMin + 0.001 }

    func reset() {
        zoom = 1.0
        pinchBase = 1.0
    }

    func zoomIn() {
        setZoom(zoom + 0.1)
    }

    func zoomOut() {
        setZoom(zoom - 0.1)
    }

    func applyPinch(_ magnification: CGFloat) {
        zoom = min(max(pinchBase * magnification, zoomMin), zoomMax)
    }

    func endPinch() {
        pinchBase = zoom
    }

    private func setZoom(_ value: CGFloat) {
        let next = min(max(value, zoomMin), zoomMax)
        zoom = next
        pinchBase = next
    }

    func installControlScrollMonitor() {
        removeControlScrollMonitor()
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.isHovered, event.modifierFlags.contains(.control) else {
                return event
            }
            let delta = event.scrollingDeltaY
            let step = event.hasPreciseScrollingDeltas ? delta * 0.004 : delta * 0.06
            let next = min(max(self.zoom + step, self.zoomMin), self.zoomMax)
            if abs(next - self.zoom) > 0.0001 {
                DispatchQueue.main.async {
                    self.zoom = next
                    self.pinchBase = next
                }
            }
            return nil
        }
    }

    func removeControlScrollMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    deinit {
        removeControlScrollMonitor()
    }
}

private enum OrgScrollAnchor {
    static func card(_ staffId: String) -> String { "org-card-\(staffId)" }
}

private struct OrgContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

// MARK: - Layout

private enum OrgLayout {
    static let cardWidth: CGFloat = 140
    static let siblingGap: CGFloat = 24
    /// Wide gutter so the center spine cannot sit on a card.
    static let centerGutter: CGFloat = 48
    static let stackGap: CGFloat = 14
    static let splitThreshold: Int = 4
    static let stem: CGFloat = 18
    static let drop: CGFloat = 14
    static let lineWidth: CGFloat = 2
    static let lineColor = Color.secondary.opacity(0.6)
    /// Keep strokes slightly outside the rounded rect.
    static let edgePad: CGFloat = 1
    static var connectorReserve: CGFloat { stem + drop }
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
                    .frame(height: OrgLayout.connectorReserve)
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
                    origin: origin
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
            HStack(alignment: .top, spacing: OrgLayout.siblingGap) {
                ForEach(children) { child in
                    OrgNodeView(node: child, depth: depth + 1, onSelect: onSelect)
                }
            }
        case .splitSides(let leftIds, let rightIds):
            let byId = Dictionary(uniqueKeysWithValues: children.map { ($0.staff.id, $0) })
            HStack(alignment: .top, spacing: OrgLayout.centerGutter) {
                VStack(spacing: OrgLayout.stackGap) {
                    ForEach(leftIds, id: \.self) { id in
                        if let child = byId[id] {
                            OrgNodeView(node: child, depth: depth + 1, onSelect: onSelect)
                        }
                    }
                }
                VStack(spacing: OrgLayout.stackGap) {
                    ForEach(rightIds, id: \.self) { id in
                        if let child = byId[id] {
                            OrgNodeView(node: child, depth: depth + 1, onSelect: onSelect)
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
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: cardIcon(staff, emphasized: emphasized))
                        .font(.caption)
                    Text(staff.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                Text(staff.team)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !staff.blurb.isEmpty {
                    Text(staff.blurb)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(8)
            .frame(width: OrgLayout.cardWidth, alignment: .leading)
            .background(
                emphasized
                    ? Color.accentColor.opacity(0.18)
                    : Color.primary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        emphasized ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.22),
                        lineWidth: 1
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
            let parentBottom = CGPoint(x: parent.midX, y: parent.maxY + OrgLayout.edgePad)

            // Direct children only — never route using grandchild frames.
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
                    lineWidth: OrgLayout.lineWidth,
                    lineCap: .square,
                    lineJoin: .miter
                )
            )
        }
        .allowsHitTesting(false)
    }

    /// T above a row — drops stop at the **top edge** of each card.
    private func drawFan(path: inout Path, parentBottom: CGPoint, kids: [CGRect]) {
        let row = kids.sorted { $0.midX < $1.midX }
        guard let left = row.first, let right = row.last else { return }
        let y = (row.map(\.minY).min() ?? 0) - OrgLayout.drop

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
            let top = kid.minY - OrgLayout.edgePad
            path.move(to: CGPoint(x: kid.midX, y: y))
            path.addLine(to: CGPoint(x: kid.midX, y: top))
        }
    }

    /// Center spine in the gutter; stubs end on each card’s **near edge** only.
    private func drawSplitSides(
        path: inout Path,
        parentBottom: CGPoint,
        left: [CGRect],
        right: [CGRect]
    ) {
        guard !left.isEmpty || !right.isEmpty else { return }

        let topY = ((left + right).map(\.minY).min() ?? 0) - OrgLayout.drop

        // Gutter bounds from column boxes — spine stays strictly between them.
        let leftEdge = left.map(\.maxX).max() ?? parentBottom.x
        let rightEdge = right.map(\.minX).min() ?? parentBottom.x
        let spineX: CGFloat = {
            if !left.isEmpty, !right.isEmpty {
                return (leftEdge + rightEdge) / 2
            }
            return parentBottom.x
        }()

        let lowestMidY = (left + right).map(\.midY).max() ?? topY

        // Stem → spine head (may jog into gutter center).
        path.move(to: parentBottom)
        path.addLine(to: CGPoint(x: parentBottom.x, y: topY))
        if abs(parentBottom.x - spineX) > 0.5 {
            path.addLine(to: CGPoint(x: spineX, y: topY))
        }

        // Vertical spine only in the gutter.
        path.move(to: CGPoint(x: spineX, y: topY))
        path.addLine(to: CGPoint(x: spineX, y: lowestMidY))

        // Left stack: stubs stop at card.maxX (never enter interior).
        for card in left {
            let y = card.midY
            let edgeX = card.maxX + OrgLayout.edgePad
            path.move(to: CGPoint(x: spineX, y: y))
            path.addLine(to: CGPoint(x: edgeX, y: y))
        }

        // Right stack: stubs stop at card.minX.
        for card in right {
            let y = card.midY
            let edgeX = card.minX - OrgLayout.edgePad
            path.move(to: CGPoint(x: spineX, y: y))
            path.addLine(to: CGPoint(x: edgeX, y: y))
        }
    }
}

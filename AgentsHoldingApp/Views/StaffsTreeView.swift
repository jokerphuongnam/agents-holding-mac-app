import SwiftUI

/// Staffs org graph — top is senior, below are reports.
/// T-routes **without arrowheads**, drawn to card anchors.
///
/// Teams with many leaf staffs (desk-garden game-lead ×5, backend ×4):
/// split into **left | center spine | right** columns so a horizontal bar
/// never runs through a middle card.
struct StaffsTreeView: View {
    let roots: [StaffTreeNode]
    let onSelect: (StaffNode) -> Void

    private let viewportMaxHeight: CGFloat = 560

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.staffsTree, systemImage: "person.3")
                .font(.headline)
            Text(L10n.staffsTreeHelp)
                .font(.caption)
                .foregroundStyle(.secondary)

            if roots.isEmpty {
                Text(L10n.staffsTreeEmpty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    VStack(alignment: .center, spacing: 28) {
                        ForEach(roots) { root in
                            OrgNodeView(node: root, depth: 0, onSelect: onSelect)
                        }
                    }
                    .padding(16)
                    .frame(minWidth: 320, alignment: .top)
                    .coordinateSpace(name: OrgChartSpace.name)
                }
                .frame(maxWidth: .infinity, maxHeight: viewportMaxHeight, alignment: .topLeading)
                .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Layout (desk-garden tuned)

private enum OrgLayout {
    static let cardWidth: CGFloat = 140
    static let siblingGap: CGFloat = 24
    /// Gutter between left/right stacks — center spine lives here.
    static let centerGutter: CGFloat = 40
    static let stackGap: CGFloat = 12
    /// ≥ this many leaf members → left/right split (avoids bar-through-card).
    static let splitThreshold: Int = 4
    static let stem: CGFloat = 16
    static let drop: CGFloat = 16
    static let stub: CGFloat = 10
    static let lineWidth: CGFloat = 2
    static let lineColor = Color.secondary.opacity(0.6)
    static var connectorReserve: CGFloat { stem + drop }
}

private enum OrgChartSpace {
    static let name = "orgChart"
}

private enum OrgFanStyle {
    /// One horizontal T above siblings (few children / branch leads).
    case fan
    /// Two stacks + center spine (many leaf staffs on one team).
    case splitSides
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
            return .splitSides
        }
        return .fan
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            staffCard(node.staff, emphasized: depth == 0)
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
                    childIds: node.children.map(\.staff.id),
                    style: fanStyle,
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
        case .splitSides:
            let mid = (children.count + 1) / 2
            let left = Array(children.prefix(mid))
            let right = Array(children.suffix(children.count - mid))
            HStack(alignment: .top, spacing: OrgLayout.centerGutter) {
                VStack(spacing: OrgLayout.stackGap) {
                    ForEach(left) { child in
                        OrgNodeView(node: child, depth: depth + 1, onSelect: onSelect)
                    }
                }
                VStack(spacing: OrgLayout.stackGap) {
                    ForEach(right) { child in
                        OrgNodeView(node: child, depth: depth + 1, onSelect: onSelect)
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

// MARK: - Connectors

private struct OrgConnectorCanvas: View {
    let parentId: String
    let childIds: [String]
    let style: OrgFanStyle
    let frames: [String: CGRect]
    let origin: CGPoint

    var body: some View {
        Canvas { context, _ in
            guard let parentGlobal = frames[parentId] else { return }
            let kidsGlobal = childIds.compactMap { frames[$0] }
            guard !kidsGlobal.isEmpty else { return }

            func local(_ r: CGRect) -> CGRect {
                CGRect(
                    x: r.minX - origin.x,
                    y: r.minY - origin.y,
                    width: r.width,
                    height: r.height
                )
            }

            let parent = local(parentGlobal)
            let kids = kidsGlobal.map(local)
            let parentBottom = CGPoint(x: parent.midX, y: parent.maxY)

            var path = Path()
            switch style {
            case .fan:
                drawFan(path: &path, parentBottom: parentBottom, kids: kids)
            case .splitSides:
                drawSplitSides(path: &path, parentBottom: parentBottom, kids: kids)
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

    /// Classic T above a single row — bar stays above cards, never through them.
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
            path.move(to: CGPoint(x: kid.midX, y: y))
            path.addLine(to: CGPoint(x: kid.midX, y: kid.minY))
        }
    }

    /// Center stem → split left/right. Buses live in the gutter; stubs into cards.
    /// No line runs through a middle staff card.
    private func drawSplitSides(path: inout Path, parentBottom: CGPoint, kids: [CGRect]) {
        let left = kids.filter { $0.midX <= parentBottom.x }.sorted { $0.minY < $1.minY }
        let right = kids.filter { $0.midX > parentBottom.x }.sorted { $0.minY < $1.minY }
        guard !left.isEmpty || !right.isEmpty else { return }

        let topY = (kids.map(\.minY).min() ?? 0) - OrgLayout.drop

        // Stem down the center.
        path.move(to: parentBottom)
        path.addLine(to: CGPoint(x: parentBottom.x, y: topY))

        // Buses sit in the center gutter (outside card boxes).
        let leftBusX: CGFloat = {
            guard !left.isEmpty else { return parentBottom.x }
            return (left.map(\.maxX).max() ?? parentBottom.x) + OrgLayout.stub
        }()
        let rightBusX: CGFloat = {
            guard !right.isEmpty else { return parentBottom.x }
            return (right.map(\.minX).min() ?? parentBottom.x) - OrgLayout.stub
        }()

        // Short center bar: left bus ← center → right bus (only through gutter).
        if !left.isEmpty {
            path.move(to: CGPoint(x: parentBottom.x, y: topY))
            path.addLine(to: CGPoint(x: leftBusX, y: topY))
        }
        if !right.isEmpty {
            path.move(to: CGPoint(x: parentBottom.x, y: topY))
            path.addLine(to: CGPoint(x: rightBusX, y: topY))
        }

        drawSideBus(path: &path, busX: leftBusX, cards: left, topY: topY)
        drawSideBus(path: &path, busX: rightBusX, cards: right, topY: topY)
    }

    private func drawSideBus(
        path: inout Path,
        busX: CGFloat,
        cards: [CGRect],
        topY: CGFloat
    ) {
        guard let first = cards.first, let last = cards.last else { return }

        // Vertical bus in the gutter (never through a card).
        path.move(to: CGPoint(x: busX, y: topY))
        path.addLine(to: CGPoint(x: busX, y: last.midY))

        // First card: drop from bar onto card top.
        path.move(to: CGPoint(x: busX, y: topY))
        path.addLine(to: CGPoint(x: first.midX, y: topY))
        path.addLine(to: CGPoint(x: first.midX, y: first.minY))

        // Remaining cards: horizontal stubs from gutter bus into card center.
        for card in cards.dropFirst() {
            path.move(to: CGPoint(x: busX, y: card.midY))
            path.addLine(to: CGPoint(x: card.midX, y: card.midY))
        }
    }
}

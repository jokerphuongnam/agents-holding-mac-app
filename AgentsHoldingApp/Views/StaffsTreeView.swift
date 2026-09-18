import SwiftUI

/// Staffs org graph — top is senior, below are reports.
/// T-junction A–B routes **without arrowheads**. Lines are drawn to each
/// **card midpoint** (PreferenceKey), so wide subtrees (desk-garden game-lead
/// ×5, CEO ×~10) do not skew connectors.
struct StaffsTreeView: View {
    let roots: [StaffTreeNode]
    let onSelect: (StaffNode) -> Void

    /// Tuned against desk-garden (~8 teams, CEO fan ~10, game-lead 5).
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

// MARK: - Layout constants (desk-garden)

private enum OrgLayout {
    static let cardWidth: CGFloat = 140
    static let siblingGap: CGFloat = 24
    /// CEO has ~10 direct reports on desk-garden — wrap every 3.
    static let perRow: Int = 3
    static let stem: CGFloat = 16
    static let drop: CGFloat = 16
    static let lineWidth: CGFloat = 2
    static let lineColor = Color.secondary.opacity(0.6)
    /// Vertical space reserved above each child row for stem/bar/drop.
    static var connectorReserve: CGFloat { stem + drop }
}

private enum OrgChartSpace {
    static let name = "orgChart"
}

/// Card frames in `OrgChartSpace` — used to draw connectors to card centers.
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

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            staffCard(node.staff, emphasized: depth == 0)
                .background(cardAnchor(node.staff.id))

            if !node.children.isEmpty {
                // Reserve room for T-connectors drawn in the overlay.
                Color.clear
                    .frame(height: OrgLayout.connectorReserve)
                childrenFans(node.children)
            }
        }
        .overlayPreferenceValue(CardFrameKey.self) { frames in
            GeometryReader { geo in
                let origin = geo.frame(in: .named(OrgChartSpace.name)).origin
                OrgConnectorCanvas(
                    parentId: node.staff.id,
                    childIds: node.children.map(\.staff.id),
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

    private func childrenFans(_ children: [StaffTreeNode]) -> some View {
        // Leaves (no subtree) may wrap — short rows, connectors stay clean.
        // Branches (leads with members) stay on one row + horizontal scroll so a
        // spine never runs through tall team content (desk-garden CEO × ~10).
        let allLeaves = children.allSatisfy { $0.children.isEmpty }
        let rows = allLeaves ? chunk(children, size: OrgLayout.perRow) : [children]
        return VStack(alignment: .center, spacing: OrgLayout.connectorReserve) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: OrgLayout.siblingGap) {
                    ForEach(row) { child in
                        OrgNodeView(node: child, depth: depth + 1, onSelect: onSelect)
                    }
                }
            }
        }
    }

    private func chunk<T>(_ items: [T], size: Int) -> [[T]] {
        guard size > 0, !items.isEmpty else { return items.isEmpty ? [] : [items] }
        var rows: [[T]] = []
        var i = 0
        while i < items.count {
            let end = min(i + size, items.count)
            rows.append(Array(items[i..<end]))
            i = end
        }
        return rows
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

// MARK: - Connectors (card-center accurate)

/// Draws stem + per-row horizontal bars + drops into each child **card** top center.
private struct OrgConnectorCanvas: View {
    let parentId: String
    let childIds: [String]
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

            // Group children into visual rows by similar top Y (wrap rows).
            let sorted = kids.sorted { $0.minY < $1.minY || ($0.minY == $1.minY && $0.midX < $1.midX) }
            var rows: [[CGRect]] = []
            for rect in sorted {
                if var last = rows.last, let sample = last.first,
                   abs(sample.minY - rect.minY) < 8 {
                    last.append(rect)
                    rows[rows.count - 1] = last.sorted { $0.midX < $1.midX }
                } else {
                    rows.append([rect])
                }
            }

            var path = Path()
            let parentBottom = CGPoint(x: parent.midX, y: parent.maxY)
            guard let firstRow = rows.first else { return }

            // Bar Y sits just above the card tops of that row.
            func barY(for row: [CGRect]) -> CGFloat {
                (row.map(\.minY).min() ?? 0) - OrgLayout.drop
            }

            let y0 = barY(for: firstRow)
            // Stem: parent card bottom → first row bar.
            path.move(to: parentBottom)
            path.addLine(to: CGPoint(x: parentBottom.x, y: y0))

            for (index, row) in rows.enumerated() {
                let y = barY(for: row)
                guard let left = row.first, let right = row.last else { continue }

                if index > 0 {
                    // Spine between wrapped rows (centered on parent).
                    let prevY = barY(for: rows[index - 1])
                    path.move(to: CGPoint(x: parentBottom.x, y: prevY))
                    path.addLine(to: CGPoint(x: parentBottom.x, y: y))
                }

                // Horizontal bar across this row’s card centers.
                if row.count == 1 {
                    // Single child: stem already at parent midX; jog to child midX if needed.
                    if abs(left.midX - parentBottom.x) > 0.5 {
                        path.move(to: CGPoint(x: parentBottom.x, y: y))
                        path.addLine(to: CGPoint(x: left.midX, y: y))
                    }
                } else {
                    path.move(to: CGPoint(x: left.midX, y: y))
                    path.addLine(to: CGPoint(x: right.midX, y: y))
                    // Join stem/spine to the bar.
                    path.move(to: CGPoint(x: parentBottom.x, y: y))
                    let clampedX = min(max(parentBottom.x, left.midX), right.midX)
                    path.addLine(to: CGPoint(x: clampedX, y: y))
                }

                // Drops into each card top center (no arrowhead).
                for kid in row {
                    path.move(to: CGPoint(x: kid.midX, y: y))
                    path.addLine(to: CGPoint(x: kid.midX, y: kid.minY))
                }
            }

            context.stroke(
                path,
                with: .color(OrgLayout.lineColor),
                style: StrokeStyle(lineWidth: OrgLayout.lineWidth, lineCap: .square, lineJoin: .miter)
            )
        }
        .allowsHitTesting(false)
    }
}

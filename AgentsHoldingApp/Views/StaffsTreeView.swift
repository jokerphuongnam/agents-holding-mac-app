import SwiftUI

/// Staffs org graph — top is senior, below are reports.
/// Keeps A–B connector routes (T-junction) but **no arrowheads**.
/// Many siblings wrap into rows so the chart stays readable; 2D scroll.
/// Card ids stay stable for a later chat/call-path overlay.
struct StaffsTreeView: View {
    let roots: [StaffTreeNode]
    let onSelect: (StaffNode) -> Void

    private let viewportMaxHeight: CGFloat = 520

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
                    VStack(alignment: .center, spacing: 24) {
                        ForEach(roots) { root in
                            OrgNodeView(node: root, depth: 0, onSelect: onSelect)
                        }
                    }
                    .padding(16)
                    .frame(minWidth: 320, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: viewportMaxHeight, alignment: .topLeading)
                .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Node

private struct OrgNodeView: View {
    let node: StaffTreeNode
    let depth: Int
    let onSelect: (StaffNode) -> Void

    private let cardWidth: CGFloat = 140
    private let siblingGap: CGFloat = 20
    private let perRow: Int = 3
    private let lineColor = Color.secondary.opacity(0.55)
    private let lineWidth: CGFloat = 2
    private let stemHeight: CGFloat = 14
    private let dropHeight: CGFloat = 14

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            staffCard(node.staff, emphasized: depth == 0)

            if !node.children.isEmpty {
                // Stem from this card down to the first fan bar (no arrowhead).
                Rectangle()
                    .fill(lineColor)
                    .frame(width: lineWidth, height: stemHeight)

                childrenFans(node.children)
            }
        }
    }

    /// Chunk children into rows of `perRow`, each row a classic T-fan.
    private func childrenFans(_ children: [StaffTreeNode]) -> some View {
        let rows = chunk(children, size: perRow)
        return VStack(alignment: .center, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    // Continuing spine between wrapped rows.
                    Rectangle()
                        .fill(lineColor)
                        .frame(width: lineWidth, height: stemHeight)
                }
                fanRow(row)
            }
        }
    }

    /// One horizontal T: piece-wise bar (continuous A–B) + drop per child, no arrow.
    private func fanRow(_ children: [StaffTreeNode]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                VStack(alignment: .center, spacing: 0) {
                    connectorCap(
                        isFirst: index == 0,
                        isLast: index == children.count - 1,
                        alone: children.count == 1
                    )
                    OrgNodeView(node: child, depth: depth + 1, onSelect: onSelect)
                        .padding(.horizontal, siblingGap / 2)
                }
            }
        }
    }

    /// Top of each sibling column: left/right bar halves + center drop.
    /// Adjacent columns touch (spacing 0) so the bar reads as one continuous line.
    private func connectorCap(isFirst: Bool, isLast: Bool, alone: Bool) -> some View {
        ZStack {
            HStack(spacing: 0) {
                if alone {
                    Color.clear.frame(maxWidth: .infinity, maxHeight: lineWidth)
                    Color.clear.frame(maxWidth: .infinity, maxHeight: lineWidth)
                } else {
                    Group {
                        if isFirst {
                            Color.clear
                        } else {
                            lineColor
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: lineWidth)

                    Group {
                        if isLast {
                            Color.clear
                        } else {
                            lineColor
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: lineWidth)
                }
            }
            .frame(height: lineWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Vertical drop from bar to child card (no arrowhead).
            Rectangle()
                .fill(lineColor)
                .frame(width: lineWidth, height: dropHeight)
        }
        .frame(height: dropHeight)
        .frame(maxWidth: .infinity)
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
            .frame(width: cardWidth, alignment: .leading)
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

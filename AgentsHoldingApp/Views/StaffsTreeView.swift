import SwiftUI

/// Staffs tree — CEO → each direct report (leads / lone members);
/// each lead → its own members (hop chain).
struct StaffsTreeView: View {
    let roots: [StaffTreeNode]
    let onSelect: (StaffNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.staffsTree, systemImage: "arrow.triangle.branch")
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
                    HStack(alignment: .top, spacing: 32) {
                        ForEach(roots) { root in
                            OrgChartNodeView(node: root, depth: 0, onSelect: onSelect)
                        }
                    }
                    .padding(8)
                }
                .frame(minHeight: 220)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One node + optional org-chart fan-out to direct reports.
private struct OrgChartNodeView: View {
    let node: StaffTreeNode
    let depth: Int
    let onSelect: (StaffNode) -> Void

    private let cardWidth: CGFloat = 148
    private let gap: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            staffCard(node.staff, emphasized: depth == 0)

            if !node.children.isEmpty {
                // Stem from this node down
                connectorStem()

                if node.children.count == 1, let only = node.children.first {
                    // Single child: one arrow straight down
                    OrgChartNodeView(node: only, depth: depth + 1, onSelect: onSelect)
                } else {
                    // Fan-out: horizontal bar, then one drop + subtree per child
                    fanOut
                }
            }
        }
    }

    private var fanOut: some View {
        let n = node.children.count
        let barWidth = CGFloat(n) * cardWidth + CGFloat(max(0, n - 1)) * gap

        return VStack(spacing: 0) {
            // Horizontal bar under the stem
            Rectangle()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: barWidth - cardWidth + 2, height: 2)
                .frame(width: barWidth, alignment: .center)

            HStack(alignment: .top, spacing: gap) {
                ForEach(node.children) { child in
                    VStack(spacing: 0) {
                        // Drop from bar to this child
                        Rectangle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 2, height: 12)
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)

                        OrgChartNodeView(node: child, depth: depth + 1, onSelect: onSelect)
                    }
                    .frame(width: cardWidth)
                }
            }
        }
    }

    private func connectorStem() -> some View {
        VStack(spacing: 2) {
            Rectangle()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 2, height: 12)
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func staffCard(_ staff: StaffNode, emphasized: Bool) -> some View {
        Button {
            onSelect(staff)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: emphasized ? "crown.fill" : (staff.name.hasSuffix("-lead") || staff.name == "cto" ? "person.badge.key.fill" : "person.fill"))
                        .font(.caption)
                    Text(staff.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                Text(staff.team)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                    : Color.secondary.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(emphasized ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

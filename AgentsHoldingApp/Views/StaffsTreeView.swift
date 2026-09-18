import SwiftUI

/// Staffs org graph — top is senior, below are reports (no arrowheads).
///
/// Layout goals: no overlapping cards, wrap when many teams, compact member
/// grids, 2D scroll. Card ids stay stable for a later chat/call-path overlay.
struct StaffsTreeView: View {
    let roots: [StaffTreeNode]
    let onSelect: (StaffNode) -> Void

    private let viewportMaxHeight: CGFloat = 480

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
                    VStack(alignment: .center, spacing: 20) {
                        ForEach(roots) { root in
                            OrgNodeView(node: root, depth: 0, onSelect: onSelect)
                        }
                    }
                    .padding(12)
                    .frame(minWidth: 320, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: viewportMaxHeight, alignment: .topLeading)
                .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One staff + its reports. Branches wrap; leaf members use an adaptive grid.
private struct OrgNodeView: View {
    let node: StaffTreeNode
    let depth: Int
    let onSelect: (StaffNode) -> Void

    private let cardWidth: CGFloat = 140
    private let teamSpacing: CGFloat = 16
    private let wrapAfter: Int = 3

    private var branches: [StaffTreeNode] {
        node.children.filter { !$0.children.isEmpty }
    }

    private var leaves: [StaffTreeNode] {
        node.children.filter { $0.children.isEmpty }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            staffCard(node.staff, emphasized: depth == 0)

            if !node.children.isEmpty {
                reportsBlock
            }
        }
    }

    @ViewBuilder
    private var reportsBlock: some View {
        VStack(alignment: .center, spacing: 14) {
            if !branches.isEmpty {
                branchLayout
            }
            if !leaves.isEmpty {
                leafGrid(leaves)
                    .frame(maxWidth: depth == 0 ? 640 : 320)
            }
        }
        .padding(depth == 0 ? 0 : 10)
        .background {
            if depth > 0 {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.08))
            }
        }
    }

    @ViewBuilder
    private var branchLayout: some View {
        let kids = branches
        if kids.count > wrapAfter {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: cardWidth), spacing: teamSpacing),
                    GridItem(.flexible(minimum: cardWidth), spacing: teamSpacing),
                    GridItem(.flexible(minimum: cardWidth), spacing: teamSpacing),
                ],
                alignment: .center,
                spacing: teamSpacing
            ) {
                ForEach(kids) { child in
                    teamBlock(child)
                }
            }
            .frame(maxWidth: 720)
        } else {
            HStack(alignment: .top, spacing: teamSpacing) {
                ForEach(kids) { child in
                    teamBlock(child)
                }
            }
        }
    }

    /// Lead + its leaf members as one visual team unit.
    private func teamBlock(_ child: StaffTreeNode) -> some View {
        VStack(alignment: .center, spacing: 10) {
            staffCard(child.staff, emphasized: false)
            if !child.children.isEmpty {
                // Nested branches (rare) recurse; pure leaves use grid.
                let nestedBranches = child.children.filter { !$0.children.isEmpty }
                let nestedLeaves = child.children.filter { $0.children.isEmpty }
                if !nestedBranches.isEmpty {
                    HStack(alignment: .top, spacing: teamSpacing) {
                        ForEach(nestedBranches) { grand in
                            OrgNodeView(node: grand, depth: depth + 2, onSelect: onSelect)
                        }
                    }
                }
                if !nestedLeaves.isEmpty {
                    leafGrid(nestedLeaves)
                        .frame(maxWidth: 300)
                }
            }
        }
        .padding(10)
        .frame(minWidth: cardWidth)
        .background(
            Color.secondary.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private func leafGrid(_ nodes: [StaffTreeNode]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: cardWidth - 8), spacing: 8)],
            alignment: .center,
            spacing: 8
        ) {
            ForEach(nodes) { leaf in
                staffCard(leaf.staff, emphasized: false)
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
                        emphasized ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.2),
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

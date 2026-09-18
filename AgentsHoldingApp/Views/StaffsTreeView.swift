import SwiftUI

/// Staffs tree — from CEO downward with arrows to direct reports.
struct StaffsTreeView: View {
    let roots: [StaffTreeNode]
    let onSelect: (StaffNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.staffsTree, systemImage: "arrow.triangle.branch")
                .font(.headline)

            if roots.isEmpty {
                Text(L10n.staffsTreeEmpty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 24) {
                        ForEach(roots) { root in
                            StaffTreeBranchView(node: root, onSelect: onSelect)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StaffTreeBranchView: View {
    let node: StaffTreeNode
    let onSelect: (StaffNode) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button {
                onSelect(node.staff)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: node.children.isEmpty ? "person.fill" : "person.3.fill")
                        Text(node.staff.name)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    }
                    Text(node.staff.team)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if !node.staff.blurb.isEmpty {
                        Text(node.staff.blurb)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .frame(maxWidth: 160, alignment: .leading)
                    }
                }
                .padding(10)
                .frame(width: 168, alignment: .leading)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            if !node.children.isEmpty {
                // Vertical arrow CEO → reports
                VStack(spacing: 2) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: 2, height: 14)
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)

                // Children row (or nested columns)
                HStack(alignment: .top, spacing: 16) {
                    ForEach(node.children) { child in
                        StaffTreeBranchView(node: child, onSelect: onSelect)
                    }
                }
            }
        }
    }
}

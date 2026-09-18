import SwiftUI

/// Inside a company: child companies + teams with staffs nested under each team.
struct CompanyCanvasView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Group {
            if let snap = appModel.openCompany {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header(snap)

                        childrenSection(snap)
                        teamsSection(snap)
                        // Only company-scoped assets here; role skills/scripts live on staff detail.
                        if !snap.skills.isEmpty {
                            FileListSection(
                                title: "Company skills",
                                systemImage: "book",
                                files: snap.skills,
                                emptyText: ""
                            ) { file in
                                appModel.openSkill(
                                    SkillRef(
                                        skillID: file.path.deletingLastPathComponent().lastPathComponent,
                                        title: file.fileName,
                                        path: file.path
                                    )
                                )
                            }
                        }
                        FileListSection(
                            title: "Company scripts (install)",
                            systemImage: "terminal",
                            files: snap.scripts,
                            emptyText: "No company-wide install scripts"
                        ) { file in
                            appModel.openCodeFile(file)
                        }
                    }
                    .padding(24)
                }
                .navigationTitle(snap.node.displayName)
            } else {
                ContentUnavailableView(
                    "No company open",
                    systemImage: "building.2",
                    description: Text("Pick a company from Holding.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(appModel.companyStack.count > 1 ? "Parent" : "Holding") {
                    appModel.backOneCompany()
                }
            }
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 160), spacing: 12)]
    }

    private func header(_ snap: CompanySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(snap.node.displayName)
                .font(.title2.weight(.semibold))
            Text(snap.node.slug)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label(snap.node.status, systemImage: "circle.fill")
                    .font(.caption)
                if !snap.node.budget.isEmpty {
                    Text("budget \(snap.node.budget)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(snap.children.count) children · \(snap.teams.count) teams · \(snap.teams.reduce(0) { $0 + $1.staffs.count }) staff")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let projectRoot = snap.node.projectRoot {
                Text(projectRoot.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            if let companyPath = snap.node.companyPath {
                Text(companyPath.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func childrenSection(_ snap: CompanySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Child companies", systemImage: "arrow.triangle.branch")
                .font(.headline)
            if snap.children.isEmpty {
                Text("No child companies")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(snap.children) { child in
                        CompanyCard(company: child) {
                            appModel.openCompanyNode(child)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func teamsSection(_ snap: CompanySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Teams & staffs", systemImage: "person.3")
                .font(.headline)

            if snap.teams.isEmpty {
                Text("No teams under system/staffs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let reportCounts = StaffDirectory().reportCounts(companyRoot: snap.companyRoot)
                ForEach(snap.teams) { team in
                    TeamBlock(team: team, reportCounts: reportCounts) { staff in
                        appModel.openStaff(staff, inHolding: false)
                    }
                }
            }
        }
    }
}

struct TeamBlock: View {
    let team: TeamNode
    var reportCounts: [String: Int] = [:]
    let onStaff: (StaffNode) -> Void

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 140), spacing: 10)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(team.name)
                    .font(.title3.weight(.semibold))
                Text("\(team.staffs.count)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            if team.staffs.isEmpty {
                Text("No staffs in this team")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(team.staffs) { staff in
                        StaffCard(staff: staff, reportCount: reportCounts[staff.name] ?? 0) {
                            onStaff(staff)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct StaffCard: View {
    let staff: StaffNode
    var reportCount: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "person.fill")
                    if reportCount > 0 {
                        Spacer()
                        Text("\(reportCount) cấp dưới")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(staff.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(staff.team)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !staff.blurb.isEmpty {
                    Text(staff.blurb)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .padding(10)
            .background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

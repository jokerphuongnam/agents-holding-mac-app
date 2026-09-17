import SwiftUI

/// Holding home: companies + holding personnel (teams/staffs).
struct HoldingCanvasView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Group {
            if let error = appModel.lastError, appModel.holding == nil {
                ContentUnavailableView(
                    "Holding not found",
                    systemImage: "building.columns",
                    description: Text(error)
                )
            } else if let holding = appModel.holding {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header(holding)
                        companiesSection(holding)
                        teamsSection(holding)
                    }
                    .padding(24)
                }
            } else {
                ProgressView("Loading holding…")
            }
        }
        .navigationTitle(appModel.holding?.name ?? "Holding")
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 180), spacing: 12)]
    }

    private func header(_ holding: HoldingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Holding")
                .font(.title2.weight(.semibold))
            Text(holding.path.path)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(holding.companies.count) companies · \(holding.teams.count) teams · \(holding.teams.reduce(0) { $0 + $1.staffs.count }) staff")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func companiesSection(_ holding: HoldingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Companies", systemImage: "building.2")
                .font(.headline)
            if holding.companies.isEmpty {
                Text("No companies in registry. Run company_registry.py scan --register")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(holding.companies) { company in
                        CompanyCard(company: company) {
                            appModel.openCompanyNode(company)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func teamsSection(_ holding: HoldingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Holding staffs", systemImage: "person.3")
                .font(.headline)
            if holding.teams.isEmpty {
                Text("No holding staffs under system/staffs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let reportCounts = StaffDirectory().reportCounts(companyRoot: holding.packageRoot)
                ForEach(holding.teams) { team in
                    TeamBlock(team: team, reportCounts: reportCounts) { staff in
                        appModel.openStaff(staff, inHolding: true)
                    }
                }
            }
        }
    }
}

struct CompanyCard: View {
    let company: CompanyNode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "building.2.fill")
                    .font(.title2)
                Text(company.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(company.slug)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let root = company.projectRoot {
                    Text(root.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

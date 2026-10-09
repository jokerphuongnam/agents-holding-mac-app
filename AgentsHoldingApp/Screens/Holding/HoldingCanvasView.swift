import SwiftUI

/// Holding home: companies + holding personnel (teams/staffs).
struct HoldingCanvasView: View {
    @Environment(AppModel.self) private var appModel
    @State private var model = HoldingScreenModel()
    @State private var showAddCompany = false

    var body: some View {
        Group {
            if let error = appModel.lastError, appModel.holding == nil {
                ContentUnavailableView(
                    L10n.holdingNotFound,
                    systemImage: "building.columns",
                    description: Text(error)
                )
            } else if let holding = appModel.holding {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            header(holding)
                            companiesSection(holding)
                            StaffsTreeView(
                                roots: StaffDirectory().buildStaffTree(companyRoot: holding.packageRoot),
                                scrollProxy: proxy,
                                companyRoot: holding.packageRoot
                            ) { staff in
                                model.send(.openStaff(staff))
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                ProgressView("Loading holding…")
            }
        }
        .navigationTitle(appModel.holding?.name ?? L10n.holding)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.send(.openUsage)
                } label: {
                    Label(L10n.usage, systemImage: "chart.bar.xaxis")
                }
                .help(L10n.usageHoldingButtonHelp)
                Button {
                    showAddCompany = true
                } label: {
                    Label(L10n.addCompany, systemImage: "plus")
                }
                .help(L10n.addCompanyHelp)
            }
        }
        .sheet(isPresented: $showAddCompany) {
            AddCompanySheet()
                .environment(appModel)
        }
        .onAppear { model.attach(appModel) }
}

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 180), spacing: 12)]
    }

    private func header(_ holding: HoldingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.holding)
                .font(.title2.weight(.semibold))
            Text(holding.path.path)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(
                L10n.holdingStats(holding.companies.count,
                    holding.teams.reduce(0) { $0 + $1.teamCount },
                    holding.teams.reduce(0) { $0 + $1.staffCount }
                )
            )
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func companiesSection(_ holding: HoldingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.companies, systemImage: "building.2")
                    .font(.headline)
                Spacer()
                Button {
                    model.send(.chooseScanFolder)
                } label: {
                    Label(L10n.scanFolder, systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .help(L10n.scanFolderHelp)
                Button {
                    showAddCompany = true
                } label: {
                    Label(L10n.add, systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
            }
            if holding.companies.isEmpty {
                Text(L10n.holdingCompaniesEmpty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(holding.companies) { company in
                        CompanyCard(company: company) {
                            model.send(.openCompany(company))
                        }
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

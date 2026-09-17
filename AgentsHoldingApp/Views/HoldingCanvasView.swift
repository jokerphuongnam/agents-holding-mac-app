import SwiftUI

/// Holding home: **companies only** (staffs/teams live inside each company).
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
                    VStack(alignment: .leading, spacing: 24) {
                        header(holding)

                        Label("Companies", systemImage: "building.2")
                            .font(.headline)

                        if holding.companies.isEmpty {
                            Text("No companies in registry. Run: python3 holding/system/install/company_registry.py scan --register")
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
            Text("\(holding.companies.count) companies")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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

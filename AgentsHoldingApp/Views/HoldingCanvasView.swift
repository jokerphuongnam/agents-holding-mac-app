import SwiftUI

/// P0 org canvas: staff + company nodes (list-as-canvas scaffold; diagram layout later).
struct HoldingCanvasView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Group {
            if let error = appModel.lastError {
                ContentUnavailableView(
                    "Holding not found",
                    systemImage: "building.columns",
                    description: Text(error)
                )
            } else if let holding = appModel.holding {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header(holding)

                        nodeSection(title: "Companies", systemImage: "building.2") {
                            if holding.companies.isEmpty {
                                Text("No companies in registry. Run: python3 holding/system/install/company_registry.py scan --register")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(holding.companies) { company in
                                        CompanyCard(company: company) {
                                            appModel.openCompany(company)
                                        }
                                    }
                                }
                            }
                        }

                        nodeSection(title: "Staff", systemImage: "person.3") {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(holding.staffs) { staff in
                                    StaffCard(staff: staff) {
                                        appModel.openStaff(staff)
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
            Text("\(holding.companies.count) companies · \(holding.staffs.count) staff")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func nodeSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
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

struct StaffCard: View {
    let staff: StaffNode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.title2)
                Text(staff.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(staff.group)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !staff.blurb.isEmpty {
                    Text(staff.blurb)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .padding(12)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

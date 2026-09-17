import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            detail
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch appModel.selection {
        case .holding:
            HoldingCanvasView()
        case .company:
            CompanyCanvasView()
        case .staff(let id):
            StaffDetailView(staffId: id)
        case .usage:
            UsagePlaceholderView()
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        List {
            Section("Navigate") {
                Button("Holding") { appModel.backToHolding() }
                Button("Usage") { appModel.selection = .usage }
            }

            if let holding = appModel.holding {
                Section("Companies") {
                    ForEach(holding.companies) { company in
                        Button(company.displayName) {
                            appModel.openCompanyNode(company)
                        }
                    }
                }
            }

            if let snap = appModel.openCompany {
                Section("In \(snap.node.displayName)") {
                    if !snap.children.isEmpty {
                        Text("Child companies")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(snap.children) { child in
                            Button(child.displayName) {
                                appModel.openCompanyNode(child)
                            }
                        }
                    }
                    ForEach(snap.teams) { team in
                        DisclosureGroup(team.name) {
                            ForEach(team.staffs) { staff in
                                Button(staff.name) {
                                    appModel.openStaff(staff)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Agents Holding")
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                if let path = appModel.holdingPath {
                    Text(path.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let err = appModel.lastError {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
                Button("Reload holding") { appModel.reloadHolding() }
                    .buttonStyle(.borderless)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

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
        case .company(let id):
            CompanyPlaceholderView(companyId: id)
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
                            appModel.openCompany(company)
                        }
                    }
                }
                Section("Staff") {
                    ForEach(holding.staffs.prefix(40)) { staff in
                        Button(staff.name) {
                            appModel.openStaff(staff)
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
                Button("Reload holding") { appModel.reloadHolding() }
                    .buttonStyle(.borderless)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

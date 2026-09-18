import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                LanguagePickerButton()
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch appModel.selection {
        case .holding:
            HoldingCanvasView()
        case .company:
            CompanyCanvasView()
        case .staff:
            StaffDetailView()
        case .skill:
            SkillDetailView()
        case .codeFile:
            CodeFileDetailView()
        case .usage:
            UsageView()
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var languageStore: LanguageStore

    var body: some View {
        List {
            Section(L10n.languageSection) {
                Picker(L10n.languagePicker, selection: $languageStore.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            Section(L10n.navigate) {
                Button(L10n.holding) { appModel.backToHolding() }
                Button(L10n.usage) { appModel.selection = .usage }
            }
            Section(L10n.actions) {
                Text(L10n.addCompanyHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let holding = appModel.holding {
                Section(L10n.companies) {
                    ForEach(holding.companies) { company in
                        Button(company.displayName) {
                            appModel.openCompanyNode(company)
                        }
                    }
                }
                Section(L10n.holdingStaffsSection) {
                    ForEach(holding.teams) { team in
                        DisclosureGroup(team.name) {
                            ForEach(team.staffs) { staff in
                                Button(staff.name) {
                                    appModel.openStaff(staff, inHolding: true)
                                }
                            }
                        }
                    }
                }
            }

            if let snap = appModel.openCompany {
                Section(L10n.inCompany(snap.node.displayName)) {
                    if !snap.children.isEmpty {
                        Text(L10n.childCompanies)
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
                                    appModel.openStaff(staff, inHolding: false)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.holding)
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
                Button(L10n.reloadHolding) { appModel.reloadHolding() }
                    .buttonStyle(.borderless)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

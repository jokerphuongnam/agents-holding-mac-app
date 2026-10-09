import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @State private var model = RootScreenModel()

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if case .company = appModel.selection, appModel.openCompany != nil {
                    Button {
                        guard let company = appModel.openCompany else { return }
                        openWindow(id: "company-chat", value: ChatWindowTarget(
                            companyRoot: company.companyRoot.path,
                            projectRoot: company.node.projectRoot?.path
                        ))
                    } label: {
                        Label(L10nLookup("chat_open", "Localizable", "Open chat"), systemImage: "bubble.left.and.bubble.right")
                    }
                }
            }
            ToolbarItem(placement: .automatic) {
                LanguagePickerButton()
            }
        }
        .onAppear { model.attach(appModel) }
        .onDisappear { model.disappear() }
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
    @Environment(AppModel.self) private var appModel
    @EnvironmentObject private var languageStore: LanguageStore
    var model: RootScreenModel

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
                Button(L10n.holding) { model.send(.backToHolding) }
                Button(L10n.usage) { model.send(.openUsage) }
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
                            model.send(.openCompany(company))
                        }
                    }
                }
                Section(L10n.holdingStaffsSection) {
                    ForEach(holding.teams) { team in
                        TeamSidebarGroup(team: team) { staff in
                            model.send(.openHoldingStaff(staff))
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
                                model.send(.openCompany(child))
                            }
                        }
                    }
                    ForEach(snap.teams) { team in
                        TeamSidebarGroup(team: team) { staff in
                            model.send(.openCompanyStaff(staff))
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
                Button(L10n.reloadHolding) { model.send(.reload) }
                    .buttonStyle(.borderless)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}



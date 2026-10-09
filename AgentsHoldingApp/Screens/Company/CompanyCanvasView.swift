import SwiftUI

/// Inside a company: child companies + teams with staffs nested under each team.
private enum CompanyRosterTab: String, CaseIterable, Identifiable {
    case tree
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tree: L10n.staffsTree
        case .list: L10n.staffsList
        }
    }
}

struct CompanyCanvasView: View {
    @Environment(AppModel.self) private var appModel
    @State private var model = CompanyScreenModel()
    @State private var rosterTab: CompanyRosterTab = .tree
    @State private var nameDraft = ""
    @State private var editingName = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        Group {
            if let snap = appModel.openCompany {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            header(snap)
                            childrenSection(snap)
                            Picker("", selection: $rosterTab) {
                                ForEach(CompanyRosterTab.allCases) { tab in
                                    Text(tab.title).tag(tab)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 420)

                            switch rosterTab {
                            case .tree:
                                StaffsTreeView(
                                    roots: StaffDirectory().buildStaffTree(companyRoot: snap.companyRoot),
                                    showsHeading: false,
                                    scrollProxy: proxy,
                                    companyRoot: snap.companyRoot
                                ) { staff in
                                    model.send(.openStaff(staff))
                                }
                            case .list:
                                teamsSection(snap)
                            }
                            companyAssets(snap)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .navigationTitle(snap.node.displayName)
                .onAppear { model.send(.refresh) }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(appModel.companyStack.count > 1 ? L10n.parent : L10n.holding) {
                            model.send(.back)
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            model.send(.openUsage)
                        } label: {
                            Label(L10n.usage, systemImage: "chart.bar.xaxis")
                        }
                        .help(L10n.usageCompanyButtonHelp)
                    }
                }
            } else {
                ContentUnavailableView(
                    L10n.noCompanyOpen,
                    systemImage: "building.2",
                    description: Text(L10n.pickCompanyHint)
                )
            }
        }
        .onAppear { model.attach(appModel) }
        .onDisappear { model.disappear() }
}

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 160), spacing: 12)]
    }

    private func commitCompanyName(_ snap: CompanySnapshot) {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != snap.node.displayName else {
            nameDraft = snap.node.displayName
            return
        }
        model.send(.rename(trimmed))
        editingName = false
    }

    private func header(_ snap: CompanySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                if editingName {
                    TextField("", text: $nameDraft)
                        .font(.title2.weight(.semibold))
                        .textFieldStyle(.plain)
                        .focused($nameFocused)
                        .onSubmit { commitCompanyName(snap) }
                } else {
                    Text(snap.node.displayName)
                        .font(.title2.weight(.semibold))
                }
                NameEditButton {
                    nameDraft = snap.node.displayName
                    editingName = true
                    nameFocused = true
                }
            }
            .onAppear { nameDraft = snap.node.displayName }
            .onChange(of: snap.node.displayName) { _, name in
                nameDraft = name
                editingName = false
            }
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
                let liveTeams = StaffDirectory().loadTeams(companyRoot: snap.companyRoot)
                Text("\(snap.children.count) children · \(liveTeams.reduce(0) { $0 + $1.teamCount }) teams · \(liveTeams.reduce(0) { $0 + $1.staffCount }) staff")
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

    private func teamsSection(_ snap: CompanySnapshot) -> some View {
        // Load teams live from disk (same as Tree) so nested large teams
        // like core/teams/cpp-llvm appear without re-opening the company.
        let directory = StaffDirectory()
        let teams = directory.loadTeams(companyRoot: snap.companyRoot)
        let counts = directory.reportCounts(companyRoot: snap.companyRoot)
        return VStack(alignment: .leading, spacing: 12) {
            if teams.isEmpty {
                Text(L10n.noStaffsInTeam)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(teams) { team in
                    TeamBlock(
                        team: team,
                        reportCounts: counts,
                        companyRoot: snap.companyRoot,
                        model: model
                    ) { staff in
                        model.send(.openStaff(staff))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func companyAssets(_ snap: CompanySnapshot) -> some View {
        if !snap.skills.isEmpty {
            FileListSection(
                title: L10n.companySkills,
                systemImage: "book",
                files: snap.skills,
                emptyText: ""
            ) { file in
                model.send(.openSkill(SkillRef(
                    skillID: file.path.deletingLastPathComponent().lastPathComponent,
                    title: file.fileName,
                    path: file.path
                )))
            }
        }
        FileListSection(
            title: L10n.companyScripts,
            systemImage: "terminal",
            files: snap.scripts,
            emptyText: L10n.companyScriptsEmpty
        ) { file in
            model.send(.openCodeFile(file))
        }
    }

    @ViewBuilder
    private func childrenSection(_ snap: CompanySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.childCompaniesTitle, systemImage: "arrow.triangle.branch")
                .font(.headline)
            if snap.children.isEmpty {
                Text(L10n.noChildCompanies)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(snap.children) { child in
                        CompanyCard(company: child) {
                            model.send(.openChild(child))
                        }
                    }
                }
            }
        }
    }

}

struct TeamBlock: View {
    @Environment(AppModel.self) private var appModel
    let team: TeamNode
    var reportCounts: [String: Int] = [:]
    var companyRoot: URL? = nil
    var model: CompanyScreenModel
    let onStaff: (StaffNode) -> Void

    @State private var newName = ""
    @State private var showingNew = false

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 140), spacing: 10)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(team.name)
                    .font(.title3.weight(.semibold))
                    .contextMenu {
                        if companyRoot != nil {
                            Button(L10n.newStaff) { showingNew = true }
                        }
                    }
                Text("\(team.staffs.count)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            if team.staffs.isEmpty && team.childTeams.isEmpty {
                Text(L10n.noStaffsInTeam)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !team.staffs.isEmpty {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(team.staffs) { staff in
                        StaffCard(staff: staff, reportCount: reportCounts[staff.name] ?? 0, onDelete: companyRoot.map { root in
                            { model.send(.removeStaff(staff, root)) }
                        }) {
                            onStaff(staff)
                        }
                    }
                }
            }
            if !team.childTeams.isEmpty {
                Text(L10n.childTeamsHop)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(team.childTeams) { child in
                    TeamBlock(
                        team: child,
                        reportCounts: reportCounts,
                        companyRoot: companyRoot,
                        model: model,
                        onStaff: onStaff
                    )
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
        .alert(L10n.newStaff, isPresented: $showingNew) {
            TextField(L10n.fileName, text: $newName)
            Button(L10n.add) {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                newName = ""
                guard let companyRoot, !name.isEmpty else { return }
                model.send(.addStaff(name: name, team: team.id, companyRoot: companyRoot))
            }
            Button(L10n.cancel, role: .cancel) { newName = "" }
        }
    }
}

struct StaffCard: View {
    let staff: StaffNode
    var reportCount: Int = 0
    var onDelete: (() -> Void)? = nil
    let action: () -> Void

    @State private var confirmingDelete = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "person.fill")
                    if reportCount > 0 {
                        Spacer()
                        Text(L10n.reportsBadge(reportCount))
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
        .contextMenu {
            if onDelete != nil {
                Button(L10n.deleteStaff, role: .destructive) { confirmingDelete = true }
            }
        }
        .alert(L10n.deleteStaff, isPresented: $confirmingDelete) {
            Button(L10n.deleteStaff, role: .destructive) { onDelete?() }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.deleteStaffConfirm(staff.name))
        }
    }
}

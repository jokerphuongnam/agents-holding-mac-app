import SwiftUI

/// Add company wizard — catalog-first roster with per-staff editor.
struct AddCompanySheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    enum Step: Int, CaseIterable {
        case folder = 0
        case roster = 1
        case confirm = 2
    }

    @State private var step: Step = .folder
    @State private var projectRootPath: String = ""
    @State private var name: String = ""
    @State private var budget: String = "medium"
    @State private var registerOnly = false
    @State private var modeHint: String = ""

    @State private var templateCatalog: [TemplateStaff] = []
    @State private var librarySkills: [LibrarySkill] = []
    @State private var roster: [StaffDraft] = []
    @State private var editingStaffName: String?

    @State private var showAddStaff = false
    @State private var addStaffTab: AddStaffTab = .existing
    @State private var newStaffName = ""
    @State private var newStaffTeam = "custom"
    @State private var newStaffDescription = ""

    private enum AddStaffTab: String, CaseIterable, Identifiable {
        case existing
        case custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .existing: return L10n.tabExisting
            case .custom: return L10n.tabCustom
            }
        }
    }

    @State private var isWorking = false
    @State private var log = ""
    @State private var localError: String?

    private let budgets = ["low", "medium", "high"]
    private let installer = CompanyInstallService()
    private let catalog = TemplateCatalogService()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                stepBody.padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 760, height: 600)
        .sheet(isPresented: Binding(
            get: { editingStaffName != nil },
            set: { if !$0 { editingStaffName = nil } }
        )) {
            if let staffName = editingStaffName,
               let idx = roster.firstIndex(where: { $0.name == staffName }) {
                StaffEditorSheet(
                    draft: $roster[idx],
                    librarySkills: librarySkills,
                    projectRootPath: projectRootPath,
                    installer: installer
                )
            }
        }
        .sheet(isPresented: $showAddStaff) {
            addStaffSheet
        }
        .onAppear {
            loadCatalog()
            if projectRootPath.isEmpty { browse() }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.addCompanyTitle)
                    .font(.title2.weight(.semibold))
                Text(stepTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Circle()
                        .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(16)
    }

    private var stepTitle: String {
        switch step {
        case .folder: return L10n.stepFolder
        case .roster: return L10n.stepRoster
        case .confirm: return L10n.stepConfirm
        }
    }

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .folder: folderStep
        case .roster: rosterStep
        case .confirm: confirmStep
        }
    }

    private var folderStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.folderHelp)
                .foregroundStyle(.secondary)
            HStack(alignment: .top) {
                Text(projectRootPath.isEmpty ? L10n.folderNotChosen : projectRootPath)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                Button(L10n.browse) { browse() }
            }
            TextField(L10n.companyNameSlug, text: $name)
                .textFieldStyle(.roundedBorder)
            Picker(L10n.budget, selection: $budget) {
                ForEach(budgets, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            if !modeHint.isEmpty {
                Text(modeHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var rosterStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.rosterHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button {
                    addStaffTab = .existing
                    newStaffName = ""
                    newStaffTeam = "custom"
                    newStaffDescription = ""
                    showAddStaff = true
                } label: {
                    Label(L10n.addStaff, systemImage: "person.badge.plus")
                }
                Spacer()
                Button(L10n.recommendedSet) { applyRecommended() }
                    .buttonStyle(.borderless)
            }

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(roster) { staff in
                    Button {
                        editingStaffName = staff.name
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: staff.isNew ? "person.crop.circle.badge.plus" : "person.fill")
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(staff.name)
                                        .fontWeight(.semibold)
                                    Text(staff.team)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(.quaternary, in: Capsule())
                                    if staff.isNew {
                                        Text(L10n.newStaffBadge)
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                Text(staff.description.isEmpty ? staff.blurb : staff.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                HStack(spacing: 10) {
                                    Label(L10n.skillsCount(staff.selectedSkillIDs.count), systemImage: "book")
                                    Label(L10n.pathsCount(staff.allowPaths.count), systemImage: "folder")
                                }
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 0)
                            if staff.name != "ceo" {
                                Button(role: .destructive) {
                                    roster.removeAll { $0.name == staff.name }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            labeled(L10n.folderLabel, projectRootPath)
            labeled(L10n.slugLabel, name)
            labeled(L10n.budgetLabel, budget)
            labeled(L10n.modeLabel, registerOnly ? L10n.modeAutoRegister : L10n.modeAutoCreate)
            labeled(
                "Staffs",
                roster.map {
                    "\($0.name)[\($0.selectedSkillIDs.count)sk,\($0.allowPaths.count)path]"
                }.joined(separator: ", ")
            )
            if let localError {
                Text(localError).foregroundStyle(.red).font(.caption)
            }
            if !log.isEmpty {
                ScrollView {
                    Text(log)
                        .font(.system(.caption2, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var addStaffSheet: some View {
        let existing = Set(roster.map(\.name))
        let available = templateCatalog.filter { !existing.contains($0.name) }
        return VStack(alignment: .leading, spacing: 12) {
            Text(L10n.addStaffTitle)
                .font(.headline)
            Picker("", selection: $addStaffTab) {
                ForEach(AddStaffTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            if addStaffTab == .existing {
                Text(L10n.existingHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if available.isEmpty {
                    Text(L10n.existingAllAdded)
                        .foregroundStyle(.secondary)
                } else {
                    List(available) { staff in
                        Button {
                            roster.append(.fromTemplate(staff))
                            roster.sort { $0.name < $1.name }
                            showAddStaff = false
                            editingStaffName = staff.name
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(staff.name).fontWeight(.semibold)
                                Text("\(staff.team) · \(staff.blurb)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            } else {
                Text(L10n.customHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TextField(L10n.nameSlug, text: $newStaffName)
                TextField(L10n.teamField, text: $newStaffTeam)
                Text(L10n.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $newStaffDescription)
                    .frame(minHeight: 100)
                    .border(Color.secondary.opacity(0.2))
            }

            HStack {
                Spacer()
                Button(L10n.close) { showAddStaff = false }
                if addStaffTab == .custom {
                    Button(L10n.addCustom) {
                        let n = newStaffName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        guard !n.isEmpty, !roster.contains(where: { $0.name == n }) else { return }
                        let draft = StaffDraft(
                            name: n,
                            team: newStaffTeam.trimmingCharacters(in: .whitespaces).isEmpty ? "custom" : newStaffTeam,
                            blurb: newStaffDescription,
                            isTemplate: false,
                            isNew: true,
                            description: newStaffDescription,
                            selectedSkillIDs: [],
                            allowPaths: [],
                            tier: "medium",
                            lead: "ceo"
                        )
                        roster.append(draft)
                        roster.sort { $0.name < $1.name }
                        showAddStaff = false
                        editingStaffName = n
                    }
                    .disabled(
                        newStaffName.trimmingCharacters(in: .whitespaces).isEmpty
                            || newStaffDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
        .padding(20)
        .frame(width: 520, height: 460)
    }

    private var footer: some View {
        HStack {
            Button(L10n.cancel) { dismiss() }
            Spacer()
            if step != .folder {
                Button(L10n.back) {
                    if let prev = Step(rawValue: step.rawValue - 1) { step = prev }
                }
            }
            if step != .confirm {
                Button(L10n.next) {
                    if let next = Step(rawValue: step.rawValue + 1) { step = next }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdvance)
            } else {
                Button(isWorking ? L10n.working : L10n.install) {
                    Task { await install() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking || !canAdvance)
            }
        }
        .padding(16)
    }

    private var canAdvance: Bool {
        switch step {
        case .folder:
            return !projectRootPath.isEmpty && !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .roster:
            return roster.contains(where: { $0.name == "ceo" })
        case .confirm:
            return true
        }
    }

    private func labeled(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Text(v).font(.system(.body, design: .monospaced)).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadCatalog() {
        guard let holding = appModel.holdingPath else { return }
        templateCatalog = catalog.loadStaffTemplates(holdingRoot: holding)
        librarySkills = catalog.loadLibrarySkills(holdingRoot: holding)
        if roster.isEmpty {
            applyRecommended()
        }
    }

    private func applyRecommended() {
        var byName: [String: StaffDraft] = [:]
        for s in roster { byName[s.name] = s }
        let rec = templateCatalog.filter { $0.recommended || $0.name == "ceo" }
        for t in rec {
            if byName[t.name] == nil {
                byName[t.name] = .fromTemplate(t)
            }
        }
        if byName["ceo"] == nil, let ceo = templateCatalog.first(where: { $0.name == "ceo" }) {
            byName["ceo"] = .fromTemplate(ceo)
        }
        roster = byName.values.sorted { $0.name < $1.name }
    }

    private func browse() {
        guard let url = installer.pickProjectFolder() else { return }
        projectRootPath = url.path
        name = installer.suggestedName(for: url)
        let existing = installer.existingCompanyDirs(in: url)
        registerOnly = !existing.isEmpty
        modeHint = registerOnly
            ? L10n.modeRegister(existing.map(\.lastPathComponent).joined(separator: ", "))
            : L10n.modeCreate
        localError = nil
    }

    @MainActor
    private func install() async {
        localError = nil
        log = ""
        isWorking = true
        defer { isWorking = false }
        guard let holding = appModel.holdingPath else {
            localError = L10n.holdingPathMissing
            return
        }

        var keep: [String] = []
        var customs: [RosterSpec.CustomStaffSpec] = []
        var configs: [String: RosterSpec.StaffConfigSpec] = [:]
        var fences: [String: [String]] = [:]

        for s in roster {
            if s.isNew {
                customs.append(
                    .init(
                        name: s.name,
                        team: s.team,
                        description: s.description,
                        tier: s.tier,
                        lead: s.lead,
                        skill_ids: s.selectedSkillIDs.sorted(),
                        paths: s.allowPaths,
                        new_skills: []
                    )
                )
            } else {
                keep.append(s.name)
                configs[s.name] = .init(
                    skill_ids: s.selectedSkillIDs.sorted(),
                    paths: s.allowPaths,
                    description: s.description,
                    tier: s.tier,
                    lead: s.lead
                )
            }
            if !s.allowPaths.isEmpty {
                fences[s.name] = s.allowPaths
            }
        }
        keep.append("ceo")

        let spec = RosterSpec(
            keep_staffs: Array(Set(keep)).sorted(),
            custom_staffs: customs,
            extra_skill_ids: [],
            staff_path_fences: fences,
            staff_configs: configs
        )

        do {
            let data = try JSONEncoder().encode(spec)
            let request = CompanyInstallRequest(
                projectRoot: URL(fileURLWithPath: projectRootPath),
                name: name,
                budget: budget,
                registerOnly: registerOnly,
                rosterSpecJSON: data
            )
            let output = try installer.install(request, holdingRoot: holding)
            log = output.isEmpty ? "OK" : output
            appModel.reloadHolding()
            try? await Task.sleep(nanoseconds: 400_000_000)
            dismiss()
        } catch {
            localError = error.localizedDescription
            log = error.localizedDescription
        }
    }
}

struct StaffEditorSheet: View {
    @Binding var draft: StaffDraft
    let librarySkills: [LibrarySkill]
    let projectRootPath: String
    let installer: CompanyInstallService
    @Environment(\.dismiss) private var dismiss
    @State private var skillFilter = ""

    private var filtered: [LibrarySkill] {
        let q = skillFilter.lowercased()
        if q.isEmpty { return librarySkills }
        return librarySkills.filter {
            $0.id.lowercased().contains(q)
                || $0.target.lowercased().contains(q)
                || $0.tags.contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(draft.name).font(.title3.weight(.semibold))
                    Text(draft.isNew ? L10n.newStaffEditorHint : L10n.templateStaff)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.done) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if draft.isNew {
                        Group {
                            Text(L10n.description).font(.headline)
                            Text(L10n.descriptionRequiredCustom)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $draft.description)
                                .frame(minHeight: 80)
                                .border(Color.secondary.opacity(0.2))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Group {
                            Text(L10n.description).font(.headline)
                            Text(draft.blurb.isEmpty ? "—" : draft.blurb)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(L10n.templateDescriptionReadonly)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Group {
                        Text(L10n.accessFiles).font(.headline)
                        Text(L10n.accessHelp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button(L10n.browseAllow) { browsePaths() }
                            Button(L10n.clear) { draft.allowPaths = [] }
                                .disabled(draft.allowPaths.isEmpty)
                        }
                        ForEach(draft.allowPaths, id: \.self) { path in
                            HStack {
                                Text(path)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button(role: .destructive) {
                                    draft.allowPaths.removeAll { $0 == path }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    Group {
                        Text(L10n.skillsLibraryStaff).font(.headline)
                        TextField(L10n.filterPlaceholder, text: $skillFilter)
                            .textFieldStyle(.roundedBorder)
                        ForEach(filtered) { skill in
                            Toggle(isOn: skillBinding(skill.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(skill.id).fontWeight(.medium)
                                    Text(skill.target)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 560, height: 520)
    }

    private func skillBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { draft.selectedSkillIDs.contains(id) },
            set: { on in
                if on { draft.selectedSkillIDs.insert(id) }
                else { draft.selectedSkillIDs.remove(id) }
            }
        )
    }

    private func browsePaths() {
        let root = URL(fileURLWithPath: projectRootPath)
        let urls = installer.pickAllowPaths(projectRoot: root)
        for url in urls {
            let rel = installer.relativePath(for: url, projectRoot: root)
            if !draft.allowPaths.contains(rel) {
                draft.allowPaths.append(rel)
            }
        }
    }
}

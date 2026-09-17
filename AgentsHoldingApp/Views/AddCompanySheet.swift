import SwiftUI

struct AddCompanySheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    enum Step: Int, CaseIterable {
        case folder = 0
        case staffs = 1
        case custom = 2
        case confirm = 3
    }

    @State private var step: Step = .folder
    @State private var projectRootPath: String = ""
    @State private var name: String = ""
    @State private var budget: String = "medium"
    @State private var registerOnly: Bool = false
    @State private var existingHint: String = ""

    @State private var templateStaffs: [TemplateStaff] = []
    @State private var librarySkills: [LibrarySkill] = []
    @State private var selectedStaffs: Set<String> = []
    @State private var customStaffs: [CustomStaffDraft] = []
    @State private var editingCustomID: String?

    @State private var isWorking = false
    @State private var log: String = ""
    @State private var localError: String?

    private let budgets = ["low", "medium", "high"]
    private let installer = CompanyInstallService()
    private let catalog = TemplateCatalogService()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                stepBody
                    .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 720, height: 560)
        .onAppear {
            loadCatalog()
            if projectRootPath.isEmpty { browse() }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add company")
                    .font(.title2.weight(.semibold))
                Text(stepTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            stepPills
        }
        .padding(16)
    }

    private var stepPills: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Circle()
                    .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var stepTitle: String {
        switch step {
        case .folder: return "1 · Folder & slug"
        case .staffs: return "2 · Review template staffs"
        case .custom: return "3 · Custom staffs & skills"
        case .confirm: return "4 · Confirm install"
        }
    }

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .folder: folderStep
        case .staffs: staffsStep
        case .custom: customStep
        case .confirm: confirmStep
        }
    }

    private var folderStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Chọn folder project để cài Company OS.")
                .foregroundStyle(.secondary)
            HStack(alignment: .top) {
                Text(projectRootPath.isEmpty ? "Chưa chọn folder" : projectRootPath)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("Browse…") { browse() }
            }
            TextField("Company name (slug)", text: $name)
                .textFieldStyle(.roundedBorder)
            Picker("Budget", selection: $budget) {
                ForEach(budgets, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Chỉ register (đã có Company OS)", isOn: $registerOnly)
            if !existingHint.isEmpty {
                Text(existingHint).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var staffsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Staffs trong template — tick để giữ sau khi cài. `ceo` luôn bắt buộc.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Select recommended") {
                    selectedStaffs = Set(templateStaffs.filter(\.recommended).map(\.name) + ["ceo"])
                }
                Button("Select all") {
                    selectedStaffs = Set(templateStaffs.map(\.name))
                }
                Button("Clear (keep ceo)") {
                    selectedStaffs = ["ceo"]
                }
            }
            .buttonStyle(.borderless)

            let grouped = Dictionary(grouping: templateStaffs, by: \.team)
            ForEach(grouped.keys.sorted(), id: \.self) { team in
                DisclosureGroup(team) {
                    ForEach(grouped[team] ?? []) { staff in
                        Toggle(isOn: binding(forStaff: staff.name)) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(staff.name).fontWeight(.semibold)
                                    if staff.recommended {
                                        Text("recommended")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(.quaternary, in: Capsule())
                                    }
                                }
                                Text(staff.blurb)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .disabled(staff.name == "ceo")
                    }
                }
            }
        }
    }

    private var customStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tạo staff mới (không có trong template): mô tả + chọn skills library hoặc tạo skill mới.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                let draft = CustomStaffDraft()
                customStaffs.append(draft)
                editingCustomID = draft.id
            } label: {
                Label("Add custom staff", systemImage: "plus")
            }

            ForEach($customStaffs) { $draft in
                DisclosureGroup(isExpanded: Binding(
                    get: { editingCustomID == draft.id },
                    set: { editingCustomID = $0 ? draft.id : nil }
                )) {
                    customStaffEditor($draft)
                } label: {
                    Text(draft.name.isEmpty ? "Untitled staff" : draft.name)
                }
            }
        }
    }

    private func customStaffEditor(_ draft: Binding<CustomStaffDraft>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("name", text: draft.name)
            TextField("team", text: draft.team)
            TextField("lead", text: draft.lead)
            Picker("tier", selection: draft.tier) {
                ForEach(["low", "medium", "high", "dispatch", "xhigh"], id: \.self) { Text($0) }
            }
            TextEditor(text: draft.description)
                .font(.body)
                .frame(minHeight: 80)
                .border(Color.secondary.opacity(0.2))

            Text("Skills từ library").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(librarySkills) { skill in
                        Toggle(isOn: skillBinding(draft: draft, skillID: skill.id)) {
                            VStack(alignment: .leading) {
                                Text(skill.id).fontWeight(.medium)
                                Text("\(skill.target) · \(skill.tags.prefix(4).joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 160)

            Text("Skills mới").font(.caption).foregroundStyle(.secondary)
            ForEach(draft.newSkills) { $ns in
                VStack(alignment: .leading, spacing: 4) {
                    TextField("skill id", text: $ns.skillID)
                    TextField("title", text: $ns.title)
                    TextEditor(text: $ns.body)
                        .frame(minHeight: 60)
                        .border(Color.secondary.opacity(0.2))
                }
                .padding(8)
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            }
            Button("Add new skill stub") {
                draft.wrappedValue.newSkills.append(NewSkillDraft())
            }
            .buttonStyle(.borderless)

            Button("Remove this staff", role: .destructive) {
                customStaffs.removeAll { $0.id == draft.wrappedValue.id }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
    }

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            labeled("Folder", projectRootPath)
            labeled("Slug", name)
            labeled("Budget", budget)
            labeled("Mode", registerOnly ? "Register only + apply roster" : "create-company + apply roster")
            labeled("Template staffs", selectedStaffs.sorted().joined(separator: ", "))
            if !customStaffs.isEmpty {
                labeled(
                    "Custom staffs",
                    customStaffs.map { "\($0.name) (\($0.selectedSkillIDs.count) skills, \($0.newSkills.count) new)" }.joined(separator: "; ")
                )
            }
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
                .frame(maxHeight: 180)
                .padding(8)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
            Spacer()
            if step != .folder {
                Button("Back") { goBack() }
            }
            if step != .confirm {
                Button("Next") { goNext() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdvance)
            } else {
                Button(isWorking ? "Working…" : "Install") {
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
        case .staffs:
            return selectedStaffs.contains("ceo")
        case .custom:
            return customStaffs.allSatisfy { draft in
                let n = draft.name.trimmingCharacters(in: .whitespaces)
                return n.isEmpty == false && !n.contains(" ")
            } || customStaffs.isEmpty
        case .confirm:
            return true
        }
    }

    private func labeled(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Text(v).font(.system(.body, design: .monospaced)).textSelection(.enabled)
        }
    }

    private func binding(forStaff name: String) -> Binding<Bool> {
        Binding(
            get: { selectedStaffs.contains(name) },
            set: { on in
                if name == "ceo" { selectedStaffs.insert("ceo"); return }
                if on { selectedStaffs.insert(name) } else { selectedStaffs.remove(name) }
            }
        )
    }

    private func skillBinding(draft: Binding<CustomStaffDraft>, skillID: String) -> Binding<Bool> {
        Binding(
            get: { draft.wrappedValue.selectedSkillIDs.contains(skillID) },
            set: { on in
                if on { draft.wrappedValue.selectedSkillIDs.insert(skillID) }
                else { draft.wrappedValue.selectedSkillIDs.remove(skillID) }
            }
        )
    }

    private func loadCatalog() {
        guard let holding = appModel.holdingPath else { return }
        templateStaffs = catalog.loadStaffTemplates(holdingRoot: holding)
        librarySkills = catalog.loadLibrarySkills(holdingRoot: holding)
        if selectedStaffs.isEmpty {
            selectedStaffs = Set(templateStaffs.filter(\.recommended).map(\.name))
            selectedStaffs.insert("ceo")
        }
    }

    private func browse() {
        guard let url = installer.pickProjectFolder() else { return }
        projectRootPath = url.path
        name = installer.suggestedName(for: url)
        let existing = installer.existingCompanyDirs(in: url)
        if !existing.isEmpty {
            registerOnly = true
            existingHint = "Phát hiện: \(existing.map(\.lastPathComponent).joined(separator: ", "))"
        } else {
            registerOnly = false
            existingHint = "Chưa có Company OS → create-company rồi apply roster đã chọn."
        }
        localError = nil
    }

    private func goNext() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    private func goBack() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        step = prev
    }

    @MainActor
    private func install() async {
        localError = nil
        log = ""
        isWorking = true
        defer { isWorking = false }
        guard let holding = appModel.holdingPath else {
            localError = "Holding path missing"
            return
        }

        let spec = RosterSpec(
            keep_staffs: selectedStaffs.sorted(),
            custom_staffs: customStaffs.map { draft in
                RosterSpec.CustomStaffSpec(
                    name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    team: draft.team,
                    description: draft.description,
                    tier: draft.tier,
                    lead: draft.lead,
                    skill_ids: draft.selectedSkillIDs.sorted(),
                    new_skills: draft.newSkills.compactMap { ns in
                        let sid = ns.skillID.trimmingCharacters(in: .whitespaces)
                        guard !sid.isEmpty else { return nil }
                        return RosterSpec.NewSkillSpec(
                            id: sid,
                            title: ns.title.isEmpty ? sid : ns.title,
                            body: ns.body
                        )
                    }
                )
            },
            extra_skill_ids: []
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
            try? await Task.sleep(nanoseconds: 500_000_000)
            dismiss()
        } catch {
            localError = error.localizedDescription
            log = error.localizedDescription
        }
    }
}

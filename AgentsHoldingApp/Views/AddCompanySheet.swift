import SwiftUI

/// Add company: pick folder → choose staffs from templates → choose skills from library.
/// No blank “invent staff/skill” forms — catalog only (less guesswork, more consistent SoT).
struct AddCompanySheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    enum Step: Int, CaseIterable {
        case folder = 0
        case staffs = 1
        case skills = 2
        case paths = 3
        case confirm = 4
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
    @State private var selectedSkillIDs: Set<String> = []
    @State private var skillFilter: String = ""
    /// staff name → allowed paths (project-relative when possible)
    @State private var staffPathFences: [String: [String]] = [:]
    @State private var pathsFocusStaff: String = "ceo"

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
        case .folder: return "1 · Folder & slug"
        case .staffs: return "2 · Chọn staffs từ template"
        case .skills: return "3 · Chọn skills từ library"
        case .paths: return "4 · Path fence (browse files/folders)"
        case .confirm: return "5 · Confirm"
        }
    }

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .folder: folderStep
        case .staffs: staffsStep
        case .skills: skillsStep
        case .paths: pathsStep
        case .confirm: confirmStep
        }
    }

    private var folderStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Chọn folder project. Roster chỉ lấy từ template/library — không tự chế staff/skill trống.")
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
            Text("Chỉ staffs có sẵn trong `templates/company/system/staffs`. `ceo` bắt buộc. Không invent role mới ở bước này.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Recommended") {
                    selectedStaffs = Set(templateStaffs.filter(\.recommended).map(\.name) + ["ceo"])
                }
                Button("All templates") {
                    selectedStaffs = Set(templateStaffs.map(\.name))
                }
                Button("Only ceo") {
                    selectedStaffs = ["ceo"]
                }
            }
            .buttonStyle(.borderless)

            let grouped = Dictionary(grouping: templateStaffs, by: \.team)
            ForEach(grouped.keys.sorted(), id: \.self) { team in
                DisclosureGroup("\(team) · \((grouped[team] ?? []).count)") {
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

    private var filteredSkills: [LibrarySkill] {
        let q = skillFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return librarySkills }
        return librarySkills.filter {
            $0.id.lowercased().contains(q)
                || $0.target.lowercased().contains(q)
                || $0.tags.contains { $0.lowercased().contains(q) }
        }
    }

    private var skillsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Skills chỉ lấy từ `templates/skills-library` (MANIFEST). Không tạo skill trống — muốn skill mới thì thêm vào library/holding trước.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Filter skills…", text: $skillFilter)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Clear skills") { selectedSkillIDs = [] }
                Text("\(selectedSkillIDs.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)

            ForEach(filteredSkills) { skill in
                Toggle(isOn: binding(forSkill: skill.id)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(skill.id).fontWeight(.semibold)
                        Text("\(skill.path)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("target: \(skill.target.isEmpty ? "—" : skill.target) · tags: \(skill.tags.prefix(6).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var pathsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Với mỗi staff đã chọn, Browse để allow file/folder được làm việc. Path ưu tiên relative tới project folder. Có thể để trống (chưa fence).")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Staff", selection: $pathsFocusStaff) {
                ForEach(selectedStaffs.sorted(), id: \.self) { Text($0).tag($0) }
            }

            let paths = staffPathFences[pathsFocusStaff] ?? []
            HStack {
                Button("Browse allow…") { browseAllowPaths(for: pathsFocusStaff) }
                Button("Clear") {
                    staffPathFences[pathsFocusStaff] = []
                }
                .disabled(paths.isEmpty)
            }

            if paths.isEmpty {
                Text("Chưa gán path — staff này chưa có fence từ wizard.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(paths, id: \.self) { path in
                    HStack {
                        Text(path)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button(role: .destructive) {
                            staffPathFences[pathsFocusStaff] = paths.filter { $0 != path }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Divider()
            Text("Tóm tắt fences")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(selectedStaffs.sorted(), id: \.self) { staff in
                let n = staffPathFences[staff]?.count ?? 0
                Text("\(staff): \(n == 0 ? "—" : "\(n) path(s)")")
                    .font(.caption)
            }
        }
        .onAppear {
            if !selectedStaffs.contains(pathsFocusStaff) {
                pathsFocusStaff = selectedStaffs.sorted().first ?? "ceo"
            }
        }
    }

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            labeled("Folder", projectRootPath)
            labeled("Slug", name)
            labeled("Budget", budget)
            labeled("Mode", registerOnly ? "Register + apply roster" : "create-company + apply roster")
            labeled("Staffs (template)", selectedStaffs.sorted().joined(separator: ", "))
            labeled(
                "Skills (library)",
                selectedSkillIDs.isEmpty ? "— (none extra)" : selectedSkillIDs.sorted().joined(separator: ", ")
            )
            labeled(
                "Path fences",
                selectedStaffs.sorted().map { staff in
                    let paths = staffPathFences[staff] ?? []
                    return paths.isEmpty ? "\(staff): —" : "\(staff): \(paths.joined(separator: ", "))"
                }.joined(separator: " | ")
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
        case .skills, .paths, .confirm:
            return true
        }
    }

    private func browseAllowPaths(for staff: String) {
        let root = URL(fileURLWithPath: projectRootPath)
        let urls = installer.pickAllowPaths(projectRoot: root)
        guard !urls.isEmpty else { return }
        var current = staffPathFences[staff] ?? []
        for url in urls {
            let rel = installer.relativePath(for: url, projectRoot: root)
            if !current.contains(rel) {
                current.append(rel)
            }
        }
        staffPathFences[staff] = current
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

    private func binding(forSkill id: String) -> Binding<Bool> {
        Binding(
            get: { selectedSkillIDs.contains(id) },
            set: { on in
                if on { selectedSkillIDs.insert(id) } else { selectedSkillIDs.remove(id) }
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
            existingHint = "Chưa có Company OS → create-company rồi apply roster/skills đã chọn từ catalog."
        }
        localError = nil
    }

    private func goNext() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        if next == .paths, !selectedStaffs.contains(pathsFocusStaff) {
            pathsFocusStaff = selectedStaffs.sorted().first ?? "ceo"
        }
        // Drop fences for staffs no longer selected
        staffPathFences = staffPathFences.filter { selectedStaffs.contains($0.key) }
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

        var fences: [String: [String]] = [:]
        for staff in selectedStaffs {
            let paths = (staffPathFences[staff] ?? []).filter { !$0.isEmpty }
            if !paths.isEmpty {
                fences[staff] = paths
            }
        }
        let spec = RosterSpec(
            keep_staffs: selectedStaffs.sorted(),
            custom_staffs: [],
            extra_skill_ids: selectedSkillIDs.sorted(),
            staff_path_fences: fences
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

import AppKit
import MarkdownUI
import SwiftUI
import UniformTypeIdentifiers

private enum FenceKind {
    case allow
    case deny
}

private struct PathFencePicker: View {
    let title: String
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
            dropZone
            HStack {
                Spacer()
                Button(L10n.cancel, action: onCancel)
                Button(L10n.choose) { browse() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var dropZone: some View {
        Text(L10n.pathFenceDrop)
            .font(.callout)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 140)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(hovering ? Color.accentColor : Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            )
            .contentShape(Rectangle())
            .onTapGesture { browse() }
            .onDrop(of: [.fileURL], isTargeted: $hovering) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { onPick(url) }
                }
                return true
            }
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.choose
        guard panel.runModal() == .OK, let url = panel.url else { return }
        onPick(url)
    }
}

struct StaffDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var harnessProfiles: StaffHarnessProfiles?
    @State private var reportsExpanded = false
    @State private var scopeExpanded = false
    @State private var fenceTarget: FenceKind?
    @State private var fenceFile: URL?
    @State private var fenceAllowed: [String] = []
    @State private var fenceDenied: [String] = []

    var body: some View {
        Group {
            if let detail = appModel.staffDetail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(detail)
                        orgSection(detail)
                        scopeSection(detail)
                        if !detail.plans.isEmpty {
                            FileListSection(
                                title: L10n.companyPlans,
                                systemImage: "list.clipboard",
                                files: detail.plans,
                                emptyText: "",
                                collapsed: true,
                                createTitle: L10n.newPlan,
                                onCreate: { name in
                                    createAndOpen(detail) {
                                        try CompanyFileActions.createPlan(
                                            name: name,
                                            owner: detail.node.name,
                                            companyRoot: detail.companyRoot
                                        )
                                    }
                                },
                                onDelete: { delete($0) }
                            ) { file in
                                appModel.openCodeFile(file)
                            }
                            .id(detail.node.id + "-plans")
                        }
                        FileListSection(
                            title: L10n.skillsFiles,
                            systemImage: "book",
                            files: detail.skillFiles,
                            emptyText: L10n.skillsEmpty(detail.node.team, detail.node.name),
                            collapsed: true,
                            createTitle: L10n.newSkill,
                            onCreate: { name in
                                createAndOpen(detail) {
                                    try CompanyFileActions.createSkill(
                                        name: name,
                                        staff: detail.node.name,
                                        team: detail.node.team,
                                        companyRoot: detail.companyRoot
                                    )
                                }
                            },
                            onDelete: { delete($0) }
                        ) { file in
                            appModel.openSkill(
                                SkillRef(
                                    skillID: file.path.deletingLastPathComponent().lastPathComponent,
                                    title: file.fileName,
                                    path: file.path
                                )
                            )
                        }
                        .id(detail.node.id + "-skills")
                        FileListSection(
                            title: L10n.scriptsFiles,
                            systemImage: "terminal",
                            files: detail.scriptFiles,
                            emptyText: L10n.scriptsEmpty,
                            collapsed: true,
                            createTitle: L10n.newScript,
                            onCreate: { name in
                                createAndOpen(detail) {
                                    try CompanyFileActions.createScript(
                                        name: name,
                                        staff: detail.node.name,
                                        team: detail.node.team,
                                        companyRoot: detail.companyRoot,
                                        hop: detail.node.name == "ceo"
                                    )
                                }
                            },
                            onDelete: { delete($0) }
                        ) { file in
                            appModel.openCodeFile(file)
                        }
                        .id(detail.node.id + "-scripts")
                        bodySection(detail)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle(detail.node.name)
                .sheet(item: $harnessProfiles) { _ in
                    HarnessProfileSheet()
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.back) { appModel.backFromStaff() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            let inHolding = appModel.openCompany == nil
                            appModel.openUsageForStaff(detail.node.name, inHolding: inHolding)
                        } label: {
                            Label(L10n.usage, systemImage: "chart.bar.xaxis")
                        }
                        .help(L10n.usageStaffButtonHelp)
                    }
                }
            } else {
                ContentUnavailableView(L10n.staffNotFound, systemImage: "person.slash")
            }
        }
    }

    private func header(_ detail: StaffDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.node.name)
                .font(.largeTitle.weight(.semibold))
                .contextMenu {
                    Button(L10n.deleteStaff, role: .destructive) {
                        appModel.removeStaff(detail.node, companyRoot: detail.companyRoot)
                    }
                }
            Text(L10n.team(detail.node.team))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if !detail.tier.isEmpty {
                    Button {
                        let profiles = HarnessProfileService().profiles(
                            forStaff: detail.node.name,
                            tier: detail.tier,
                            companyRoot: detail.companyRoot
                        )
                        harnessProfiles = profiles
                    } label: {
                        HStack(spacing: 4) {
                            Text(detail.tier)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(L10n.harnessTierHelp)
                }
                if !detail.permissionMode.isEmpty {
                    badge(detail.permissionMode)
                }
                if !detail.capabilityMode.isEmpty {
                    badge(detail.capabilityMode)
                }
            }
            if !detail.node.blurb.isEmpty {
                Text(detail.node.blurb)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func superiorMenu(_ detail: StaffDetail) -> some View {
        Button(L10n.clearSuperior) {
            appModel.setStaffLead(of: detail.node.name, to: "", companyRoot: detail.companyRoot)
        }
        ForEach(hopCandidates(detail).filter { $0.name != detail.lead }, id: \.id) { staff in
            Button(staff.name) {
                appModel.setStaffLead(of: detail.node.name, to: staff.name, companyRoot: detail.companyRoot)
            }
        }
    }

    @ViewBuilder
    private func reportsMenu(_ detail: StaffDetail) -> some View {
        let reporting = Set(detail.reports.map(\.name))
        ForEach(hopCandidates(detail).filter { !reporting.contains($0.name) }, id: \.id) { staff in
            Button(L10n.addReport(staff.name)) {
                appModel.setStaffLead(of: staff.name, to: detail.node.name, companyRoot: detail.companyRoot)
            }
        }
    }

    private func hopCandidates(_ detail: StaffDetail) -> [StaffNode] {
        StaffDirectory().loadTeams(companyRoot: detail.companyRoot)
            .flatMap(\.allStaffs)
            .filter { $0.name != detail.node.name }
            .sorted { $0.name < $1.name }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }

    @ViewBuilder
    private func orgSection(_ detail: StaffDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.orgHopChain, systemImage: "arrow.up.arrow.down")
                .font(.headline)
            Text(L10n.orgHopHelp)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .top) {
                Text(L10n.superiorLabel)
                    .foregroundStyle(.secondary)
                    .frame(width: 200, alignment: .leading)
                    .contextMenu {
                        superiorMenu(detail)
                    }
                if let lead = detail.lead, !lead.isEmpty {
                    Button {
                        appModel.openStaffNamed(lead)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill")
                            Text(lead)
                                .fontWeight(.semibold)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(L10n.openSuperior)
                    .contextMenu { superiorMenu(detail) }
                } else {
                    Text(L10n.topDispatcher)
                        .foregroundStyle(.tertiary)
                }
            }
            if let realLead = detail.realLead, !realLead.isEmpty {
                HStack(alignment: .top) {
                    Text(NSLocalizedString("real_lead_label", comment: ""))
                        .foregroundStyle(.secondary)
                        .frame(width: 200, alignment: .leading)
                    Button {
                        appModel.openStaffNamed(realLead)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill")
                            Text(realLead)
                                .fontWeight(.semibold)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    reportsExpanded.toggle()
                } label: {
                    HStack {
                        Text(L10n.reportsLabel)
                            .foregroundStyle(.secondary)
                        Text("\(detail.reports.count)")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                        Spacer()
                        Image(systemName: reportsExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { reportsMenu(detail) }
                if reportsExpanded && detail.reports.isEmpty {
                    Text(L10n.noReportsLeaf)
                        .foregroundStyle(.tertiary)
                } else if reportsExpanded {
                    VStack(spacing: 0) {
                        ForEach(detail.reports) { report in
                            Button {
                                appModel.openStaff(report, inHolding: appModel.openCompany == nil)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "person.fill")
                                        .foregroundStyle(Color.accentColor)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(report.name)
                                            .fontWeight(.semibold)
                                        Text(report.team)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 8)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(L10n.removeReport, role: .destructive) {
                                    let fallback = detail.lead ?? ""
                                    let next = fallback == report.name ? "" : fallback
                                    appModel.setStaffLead(
                                        of: report.name,
                                        to: next,
                                        companyRoot: detail.companyRoot
                                    )
                                }
                            }
                            if report.id != detail.reports.last?.id {
                                Divider()
                            }
                        }
                    }
                    .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func scopeSection(_ detail: StaffDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let pathCount = detail.allowedPaths.count + detail.deniedHints.count
            Button {
                scopeExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Label(L10n.pathFence, systemImage: "folder.badge.gearshape")
                        .font(.headline)
                    Text("\(pathCount)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    Spacer()
                    Image(systemName: scopeExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(L10n.addAllowed) { beginFence(.allow, detail) }
                Button(L10n.addDenied) { beginFence(.deny, detail) }
            }

            if scopeExpanded {
                Text(L10n.pathFenceHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if scopeExpanded && detail.allowedPaths.isEmpty && detail.deniedHints.isEmpty {
                Text(L10n.pathFenceEmpty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if scopeExpanded {
                fenceHeading(L10n.allowedRw, add: L10n.addAllowed) {
                    beginFence(.allow, detail)
                }
                ForEach(detail.allowedPaths, id: \.self) { path in
                    fenceRow(path, destructive: false) {
                        var next = detail.allowedPaths
                        next.removeAll { $0 == path }
                        appModel.setPathFence(file: detail.sourceFile, allowed: next, denied: detail.deniedHints)
                    }
                }

                fenceHeading(L10n.deniedMustNot, add: L10n.addDenied) {
                    beginFence(.deny, detail)
                }
                .padding(.top, 4)
                ForEach(detail.deniedHints, id: \.self) { path in
                    fenceRow(path, destructive: true) {
                        var next = detail.deniedHints
                        next.removeAll { $0 == path }
                        appModel.setPathFence(file: detail.sourceFile, allowed: detail.allowedPaths, denied: next)
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { fenceTarget != nil },
            set: { if !$0 { fenceTarget = nil } }
        )) {
            PathFencePicker(
                title: fenceTarget == .deny ? L10n.addDenied : L10n.addAllowed,
                onPick: { url in
                    commitFence(url)
                },
                onCancel: { fenceTarget = nil }
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
    }

    private func fenceHeading(_ title: String, add: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button(action: action) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help(add)
        }
    }

    private func fenceRow(_ path: String, destructive: Bool, remove: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(path)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(destructive ? Color.red.opacity(0.8) : Color.primary)
                .textSelection(.enabled)
            Spacer()
            Button(role: .destructive, action: remove) {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .help(L10n.removePath)
        }
    }

    private func beginFence(_ kind: FenceKind, _ detail: StaffDetail) {
        fenceTarget = kind
        fenceFile = detail.sourceFile
        fenceAllowed = detail.allowedPaths
        fenceDenied = detail.deniedHints
        scopeExpanded = true
    }

    private func commitFence(_ url: URL) {
        guard let file = fenceFile, let kind = fenceTarget else { return }
        let path = fencePath(for: url)
        guard !path.isEmpty else { return }
        var allowed = fenceAllowed
        var denied = fenceDenied
        if kind == .allow {
            if !allowed.contains(path) { allowed.append(path) }
        } else if !denied.contains(path) {
            denied.append(path)
        }
        fenceTarget = nil
        appModel.setPathFence(file: file, allowed: allowed, denied: denied)
    }

    /// Prefer a path relative to the company project. Keep an absolute path otherwise.
    private func fencePath(for url: URL) -> String {
        let picked = url.standardizedFileURL.path
        guard let root = appModel.openCompany?.node.projectRoot?.standardizedFileURL.path else {
            return picked
        }
        if picked == root { return "." }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        if picked.hasPrefix(prefix) {
            return String(picked.dropFirst(prefix.count))
        }
        return picked
    }

    private func createAndOpen(_ detail: StaffDetail, _ make: () throws -> URL) {
        do {
            let url = try make()
            appModel.refreshOpenStaff()
            appModel.openCodeFile(CodeFileRef.make(url: url, relativeTo: detail.companyRoot))
        } catch {
            appModel.lastError = error.localizedDescription
        }
    }

    private func delete(_ file: CodeFileRef) {
        do {
            try CompanyFileActions.delete(file.path)
            appModel.refreshOpenStaff()
        } catch {
            appModel.lastError = error.localizedDescription
        }
    }

    private func bodySection(_ detail: StaffDetail) -> some View {
        EditableTextFileView(
            url: detail.sourceFile,
            title: L10n.staffBrief,
            embedded: true,
            onBack: {}
        )
    }
}

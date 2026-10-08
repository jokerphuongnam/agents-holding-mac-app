import MarkdownUI
import SwiftUI

struct StaffDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var harnessProfiles: StaffHarnessProfiles?
    @State private var reportsExpanded = false
    @State private var scopeExpanded = false

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
                .sheet(item: $harnessProfiles) { profiles in
                    HarnessProfileSheet(profiles: profiles)
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
                } else {
                    Text(L10n.topDispatcher)
                        .foregroundStyle(.tertiary)
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

            if scopeExpanded && !detail.allowedPaths.isEmpty {
                Text(L10n.allowedRw)
                    .font(.subheadline.weight(.semibold))
                ForEach(detail.allowedPaths, id: \.self) { path in
                    Text(path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            if scopeExpanded && !detail.deniedHints.isEmpty {
                Text(L10n.deniedMustNot)
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
                ForEach(detail.deniedHints, id: \.self) { path in
                    Text(path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red.opacity(0.8))
                        .textSelection(.enabled)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
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

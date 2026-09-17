import SwiftUI

struct StaffDetailView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Group {
            if let detail = appModel.staffDetail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(detail)
                        orgSection(detail)
                        scopeSection(detail)
                        skillsSection(detail)
                        bodySection(detail)
                    }
                    .padding(24)
                }
                .navigationTitle(detail.node.name)
            } else {
                ContentUnavailableView("Staff not found", systemImage: "person.slash")
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") { appModel.backFromStaff() }
            }
        }
    }

    private func header(_ detail: StaffDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.node.name)
                .font(.largeTitle.weight(.semibold))
            Text("Team: \(detail.node.team)")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if !detail.tier.isEmpty {
                    badge(detail.tier)
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
            Label("Org", systemImage: "arrow.up.arrow.down")
                .font(.headline)

            HStack(alignment: .top) {
                Text("Lead (cấp trên)")
                    .foregroundStyle(.secondary)
                    .frame(width: 140, alignment: .leading)
                if let lead = detail.lead, !lead.isEmpty {
                    Text(lead)
                        .fontWeight(.semibold)
                } else {
                    Text("— (none / top)")
                        .foregroundStyle(.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Reports (cấp dưới)")
                    .foregroundStyle(.secondary)
                if detail.reports.isEmpty {
                    Text("Không quản lý staff nào")
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(detail.reports) { report in
                        Button {
                            appModel.openStaff(report, inHolding: appModel.openCompany == nil)
                        } label: {
                            HStack {
                                Image(systemName: "person.fill")
                                Text(report.name)
                                Text("· \(report.team)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
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
            Label("Path fence (filesystem)", systemImage: "folder.badge.gearshape")
                .font(.headline)
            Text("Staff không đọc cả project — chỉ các path được cấp dưới đây (cộng với skills).")
                .font(.caption)
                .foregroundStyle(.secondary)

            if detail.allowedPaths.isEmpty && detail.deniedHints.isEmpty {
                Text("Chưa parse được path fence từ staff md / SCOPE.md — xem body bên dưới.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !detail.allowedPaths.isEmpty {
                Text("Allowed / RW")
                    .font(.subheadline.weight(.semibold))
                ForEach(detail.allowedPaths, id: \.self) { path in
                    Text(path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            if !detail.deniedHints.isEmpty {
                Text("Denied / must not")
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

    @ViewBuilder
    private func skillsSection(_ detail: StaffDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Skills (biên nhiệm vụ)", systemImage: "book")
                .font(.headline)
            Text("Mỗi skill = phạm vi việc được làm (vd. devops → CLI; git → git). Bấm để đọc SKILL.md.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if detail.skills.isEmpty {
                Text("Không có skill id trên agents.tsv — staff có thể chỉ dựa path fence / brief.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(detail.skills) { skill in
                    Button {
                        appModel.openSkill(skill)
                    } label: {
                        HStack {
                            Image(systemName: skill.path == nil ? "questionmark.circle" : "doc.text")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.skillID)
                                    .fontWeight(.semibold)
                                if skill.title != skill.skillID {
                                    Text(skill.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if skill.path == nil {
                                    Text("SKILL.md not found")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .padding(10)
                        .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(skill.path == nil)
                }
            }
        }
    }

    private func bodySection(_ detail: StaffDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Staff brief", systemImage: "doc.plaintext")
                .font(.headline)
            Text(detail.bodyMarkdown)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

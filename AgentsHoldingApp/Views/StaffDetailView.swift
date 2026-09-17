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
            Label("Org (hop chain)", systemImage: "arrow.up.arrow.down")
                .font(.headline)
            Text("Cấp trên = staff có thể Assign/hop để ra lệnh cho người này. Cấp dưới = người này hop ra lệnh được.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .top) {
                Text("Cấp trên (có thể hop → mình)")
                    .foregroundStyle(.secondary)
                    .frame(width: 200, alignment: .leading)
                if let lead = detail.lead, !lead.isEmpty {
                    Text(lead)
                        .fontWeight(.semibold)
                } else {
                    Text("— (top dispatcher)")
                        .foregroundStyle(.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Cấp dưới (mình hop → họ)")
                    .foregroundStyle(.secondary)
                if detail.reports.isEmpty {
                    Text("Không hop xuống staff nào (leaf)")
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
            Label("Skills (files)", systemImage: "doc.text")
                .font(.headline)
            Text("List SKILL.md — bấm file để mở dạng Markdown. Mỗi skill = biên nhiệm vụ (vd. devops → CLI).")
                .font(.caption)
                .foregroundStyle(.secondary)

            if detail.skills.isEmpty {
                Text("Không có skill id trên agents.tsv — staff có thể chỉ dựa path fence / brief.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(detail.skills) { skill in
                        Button {
                            appModel.openSkill(skill)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: skill.path == nil ? "questionmark.folder" : "doc.richtext")
                                    .foregroundStyle(skill.path == nil ? .orange : .accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(skill.fileLabel)
                                        .font(.system(.body, design: .monospaced))
                                        .fontWeight(.medium)
                                    if skill.title != skill.skillID {
                                        Text(skill.title)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let path = skill.path {
                                        Text(path.path)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    } else {
                                        Text("SKILL.md not found under system/skills")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                Spacer()
                                if skill.path != nil {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 8)
                        }
                        .buttonStyle(.plain)
                        .disabled(skill.path == nil)
                        if skill.id != detail.skills.last?.id {
                            Divider()
                        }
                    }
                }
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
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

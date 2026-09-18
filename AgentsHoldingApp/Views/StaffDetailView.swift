import MarkdownUI
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
                        FileListSection(
                            title: "Skills (files)",
                            systemImage: "book",
                            files: detail.skillFiles,
                            emptyText: "No skills for this staff"
                        ) { file in
                            appModel.openSkill(
                                SkillRef(
                                    skillID: file.path.deletingLastPathComponent().lastPathComponent,
                                    title: file.fileName,
                                    path: file.path
                                )
                            )
                        }
                        FileListSection(
                            title: "Scripts (files)",
                            systemImage: "terminal",
                            files: detail.scriptFiles,
                            emptyText: "No scripts for this staff"
                        ) { file in
                            appModel.openCodeFile(file)
                        }
                        bodySection(detail)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                } else {
                    Text("— (top dispatcher)")
                        .foregroundStyle(.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Cấp dưới (mình hop → họ)")
                        .foregroundStyle(.secondary)
                    if !detail.reports.isEmpty {
                        Text("\(detail.reports.count)")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                if detail.reports.isEmpty {
                    Text("Không hop xuống staff nào (leaf)")
                        .foregroundStyle(.tertiary)
                } else {
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
            Label("Path fence (filesystem)", systemImage: "folder.badge.gearshape")
                .font(.headline)
            Text("Staff không đọc cả project — chỉ các path được cấp dưới đây (cộng với skills).")
                .font(.caption)
                .foregroundStyle(.secondary)

            if detail.allowedPaths.isEmpty && detail.deniedHints.isEmpty {
                Text("Chưa parse được path fence từ staff md / SCOPE.md — xem brief bên dưới.")
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

    private func bodySection(_ detail: StaffDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Staff brief", systemImage: "doc.richtext")
                .font(.headline)
            Markdown(detail.bodyMarkdown)
                .markdownTheme(.gitHub)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

import MarkdownUI
import SwiftUI

struct SkillDetailView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Group {
            if let skill = appModel.openSkill, let path = skill.path,
               let text = try? String(contentsOf: path, encoding: .utf8) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(skill.fileLabel)
                            .font(.title2.weight(.semibold))
                        Text(path.path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Divider()
                        Markdown(text)
                            .markdownTheme(.gitHub)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(24)
                }
                .navigationTitle(skill.skillID)
            } else {
                ContentUnavailableView(L10n.tr("skill_not_found"), systemImage: "book.closed")
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.tr("back")) { appModel.backFromSkill() }
            }
        }
    }
}

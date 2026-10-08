import SwiftUI

struct SkillDetailView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Group {
            if let skill = appModel.openSkill, let path = skill.path {
                EditableTextFileView(
                    url: path,
                    title: skill.skillID,
                    subtitle: path.path,
                    onBack: { appModel.backFromSkill() }
                )
            } else {
                ContentUnavailableView(L10n.skillNotFound, systemImage: "book.closed")
            }
        }
    }
}

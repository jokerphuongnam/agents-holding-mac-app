import SwiftUI

struct SkillDetailView: View {
    @Environment(AppModel.self) private var appModel
    @State private var model = SkillScreenModel()

    var body: some View {
        let _ = model.attach(appModel)
        Group {
            if let skill = appModel.openSkill, let path = skill.path {
                EditableTextFileView(
                    url: path,
                    title: skill.skillID,
                    subtitle: path.path,
                    onBack: { model.send(.back) }
                )
            } else {
                ContentUnavailableView(L10n.skillNotFound, systemImage: "book.closed")
            }
        }
    }
}

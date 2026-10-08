import Foundation

enum SkillScreenAction {
    case back
}

@MainActor
final class SkillScreenModel: ActionScreenModel<SkillScreenAction>, ViewModel {
    func observable(action: SkillScreenAction) -> () -> Void {
        if case .back = action { app?.backFromSkill() }
        return {}
    }
}

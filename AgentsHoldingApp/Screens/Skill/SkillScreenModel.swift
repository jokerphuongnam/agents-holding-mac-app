import ScreenViewModel
import Foundation

enum SkillScreenAction {
    case back
}

@MainActor
final class SkillScreenModel: ActionScreenModel<SkillScreenAction> {
    override func observable(action: SkillScreenAction, cancel _: Cancel) -> Effect<SkillScreenAction> {
        if case .back = action { app?.backFromSkill() }
        return .none
    }
}

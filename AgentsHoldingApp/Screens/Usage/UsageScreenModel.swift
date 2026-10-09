import ScreenViewModel
import Foundation

enum UsageScreenAction {
    case back
}

@MainActor
final class UsageScreenModel: ActionScreenModel<UsageScreenAction> {
    override func observable(action: UsageScreenAction) -> Effect<UsageScreenAction> {
        if case .back = action { app?.backFromUsage() }
        return .none
    }
}

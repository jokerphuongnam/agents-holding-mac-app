import ScreenViewModel
import Foundation

enum UsageScreenAction {
    case back
}

@MainActor
final class UsageScreenModel: ActionScreenModel<UsageScreenAction> {
    override func observable(action: UsageScreenAction, cancel _: @escaping () -> Void) -> Effect<UsageScreenAction> {
        if case .back = action { app?.backFromUsage() }
        return .none
    }
}

import ScreenViewModel
import Foundation

enum AddCompanyScreenAction {
    case reloadHolding
}

@MainActor
final class AddCompanyScreenModel: ActionScreenModel<AddCompanyScreenAction> {
    override func observable(action: AddCompanyScreenAction, cancel _: Cancel) -> Effect<AddCompanyScreenAction> {
        if case .reloadHolding = action { app?.reloadHolding() }
        return .none
    }
}

import Foundation

enum AddCompanyScreenAction {
    case reloadHolding
}

@MainActor
final class AddCompanyScreenModel: ActionScreenModel<AddCompanyScreenAction>, ViewModel {
    func observable(action: AddCompanyScreenAction) -> () -> Void {
        if case .reloadHolding = action { app?.reloadHolding() }
        return {}
    }
}

import ScreenViewModel
import Foundation

enum SettingsScreenAction {
    case reload
}

@MainActor
final class SettingsScreenModel: ActionScreenModel<SettingsScreenAction> {
    override func observable(action: SettingsScreenAction, cancel _: Cancel) -> Effect<SettingsScreenAction> {
        guard let app else { return .none }
        switch action {
        case .reload:
            app.reloadHolding()
        }
        return .none
    }
}

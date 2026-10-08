import Foundation

enum SettingsScreenAction {
    case reload
}

@MainActor
final class SettingsScreenModel: ActionScreenModel<SettingsScreenAction>, ViewModel {
    func observable(action: SettingsScreenAction) -> () -> Void {
        guard let app else { return {} }
        switch action {
        case .reload:
            app.reloadHolding()
        }
        return {}
    }
}

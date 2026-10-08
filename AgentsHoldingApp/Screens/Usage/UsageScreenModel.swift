import Foundation

enum UsageScreenAction {
    case back
}

@MainActor
final class UsageScreenModel: ActionScreenModel<UsageScreenAction>, ViewModel {
    func observable(action: UsageScreenAction) -> () -> Void {
        if case .back = action { app?.backFromUsage() }
        return {}
    }
}

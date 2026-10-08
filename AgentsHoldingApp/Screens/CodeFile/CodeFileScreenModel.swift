import Foundation

enum CodeFileScreenAction {
    case back
}

@MainActor
final class CodeFileScreenModel: ActionScreenModel<CodeFileScreenAction>, ViewModel {
    func observable(action: CodeFileScreenAction) -> () -> Void {
        if case .back = action { app?.backFromCodeFile() }
        return {}
    }
}

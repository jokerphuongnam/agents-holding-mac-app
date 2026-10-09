import ScreenViewModel
import Foundation

enum CodeFileScreenAction {
    case back
}

@MainActor
final class CodeFileScreenModel: ActionScreenModel<CodeFileScreenAction> {
    override func observable(action: CodeFileScreenAction, cancel _: @escaping () -> Void) -> Effect<CodeFileScreenAction> {
        if case .back = action { app?.backFromCodeFile() }
        return .none
    }
}

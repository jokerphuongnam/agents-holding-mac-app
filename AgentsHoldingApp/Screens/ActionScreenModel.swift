import Observation
import ScreenViewModel

/// App screen model. The package owns `send` and `Effect`. This type only keeps the shared app model.
@MainActor
@Observable
class ActionScreenModel<Action>: ScreenModel<Action> {
    weak var app: AppModel?

    func attach(_ app: AppModel) {
        self.app = app
    }
}

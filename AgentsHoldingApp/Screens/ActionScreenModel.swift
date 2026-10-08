import Combine
import Foundation
import Observation

/// Screen view model. The view calls `send`. `observable(action:)` is required, so a screen cannot compile without it.
/// The closure it returns runs when this object is released (observers, timers).
@MainActor
protocol ViewModel: AnyObject {
    associatedtype Action
    var effects: ViewModelEffects<Action> { get }
    func send(_ action: Action)
    func observable(action: Action) -> () -> Void
}

extension ViewModel {
    func send(_ action: Action) {
        effects.install { [weak self] action in
            guard let self else { return }
            let cleanup = self.observable(action: action)
            self.effects.cleanups.append(cleanup)
        }
        effects.actions.send(action)
    }
}

/// Owns the action stream and the cleanups. Released with the view model, so `deinit` runs the cleanups.
final class ViewModelEffects<Action> {
    let actions = PassthroughSubject<Action, Never>()
    fileprivate var subscriptions: [AnyCancellable] = []
    fileprivate var cleanups: [() -> Void] = []
    private var installed = false

    /// First `send` installs the sink. Later sends reuse it.
    fileprivate func install(_ receive: @escaping (Action) -> Void) {
        guard !installed else { return }
        installed = true
        let subscription = actions
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: receive)
        subscriptions.append(subscription)
    }

    deinit {
        subscriptions.removeAll()
        let pending = cleanups
        cleanups.removeAll()
        pending.forEach { $0() }
    }
}

@MainActor
@Observable
class ActionScreenModel<Action> {
    let effects = ViewModelEffects<Action>()
    weak var app: AppModel?

    func attach(_ app: AppModel) {
        self.app = app
    }
}

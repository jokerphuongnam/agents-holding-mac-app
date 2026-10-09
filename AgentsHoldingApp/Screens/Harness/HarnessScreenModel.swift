import ScreenViewModel
import Foundation

enum HarnessScreenAction {
    case setTier(String, staffFile: URL, name: String, companyRoot: URL)
    case setRouter(Bool, URL)
    case setRuntime(String, staff: String, companyRoot: URL)
    case setMapping(runtime: String, tier: String, model: String, effort: String, companyRoot: URL)
}

@MainActor
final class HarnessScreenModel: ActionScreenModel<HarnessScreenAction> {
    override func observable(action: HarnessScreenAction, cancel _: @escaping () -> Void) -> Effect<HarnessScreenAction> {
        guard let app else { return .none }
        switch action {
        case .setTier(let tier, let file, let name, let root):
            app.setStaffTier(tier, staffFile: file, name: name, companyRoot: root)
        case .setRouter(let enabled, let root):
            app.setHarnessRouter(enabled: enabled, companyRoot: root)
        case .setRuntime(let runtime, let staff, let root):
            app.setStaffRuntime(runtime, staff: staff, companyRoot: root)
        case .setMapping(let runtime, let tier, let model, let effort, let root):
            app.setHarnessTier(runtime: runtime, tier: tier, model: model, effort: effort, companyRoot: root)
        }
        return .none
    }
}

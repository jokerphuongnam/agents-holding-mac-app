import ScreenViewModel
import Foundation

enum RootScreenAction {
    case backToHolding
    case openUsage
    case reload
    case openCompany(CompanyNode)
    case openHoldingStaff(StaffNode)
    case openCompanyStaff(StaffNode)
}

@MainActor
final class RootScreenModel: ActionScreenModel<RootScreenAction> {
    override func observable(action: RootScreenAction, cancel _: @escaping () -> Void) -> Effect<RootScreenAction> {
        guard let app else { return .none }
        switch action {
        case .backToHolding:
            app.backToHolding()
        case .openUsage:
            app.openUsageHolding()
        case .reload:
            app.reloadHolding()
        case .openCompany(let company):
            app.openCompanyNode(company)
        case .openHoldingStaff(let staff):
            app.openStaff(staff, inHolding: true)
        case .openCompanyStaff(let staff):
            app.openStaff(staff, inHolding: false)
        }
        return .none
    }
}

import ScreenViewModel
import Foundation

enum HoldingScreenAction {
    case openCompany(CompanyNode)
    case openStaff(StaffNode)
    case openUsage
    case chooseScanFolder
}

@MainActor
final class HoldingScreenModel: ActionScreenModel<HoldingScreenAction> {
    override func observable(action: HoldingScreenAction, cancel _: @escaping () -> Void) -> Effect<HoldingScreenAction> {
        guard let app else { return .none }
        switch action {
        case .openCompany(let company):
            app.openCompanyNode(company)
        case .openStaff(let staff):
            app.openStaff(staff, inHolding: true)
        case .openUsage:
            app.openUsageHolding()
        case .chooseScanFolder:
            app.chooseCompanyScanFolder()
        }
        return .none
    }
}

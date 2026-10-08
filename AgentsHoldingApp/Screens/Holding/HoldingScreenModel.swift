import Foundation

enum HoldingScreenAction {
    case openCompany(CompanyNode)
    case openStaff(StaffNode)
    case openUsage
    case chooseScanFolder
}

@MainActor
final class HoldingScreenModel: ActionScreenModel<HoldingScreenAction>, ViewModel {
    func observable(action: HoldingScreenAction) -> () -> Void {
        guard let app else { return {} }
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
        return {}
    }
}

import ScreenViewModel
import Foundation

enum StaffsTreeAction {
    case add(name: String, team: String, companyRoot: URL)
    case remove(StaffNode, URL)
    case open(StaffNode, companyRoot: URL, inHolding: Bool)
}

@MainActor
final class StaffsTreeScreenModel: ActionScreenModel<StaffsTreeAction> {
    override func observable(action: StaffsTreeAction, cancel _: Cancel) -> Effect<StaffsTreeAction> {
        guard let app else { return .none }
        switch action {
        case .add(let name, let team, let root):
            app.addStaff(name: name, team: team, companyRoot: root)
        case .remove(let staff, let root):
            app.removeStaff(staff, companyRoot: root)
        case .open(let staff, let root, let inHolding):
            app.openStaff(staff, companyRoot: root, inHolding: inHolding)
        }
        return .none
    }
}

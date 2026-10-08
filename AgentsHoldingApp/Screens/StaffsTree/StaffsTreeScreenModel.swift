import Foundation

enum StaffsTreeAction {
    case add(name: String, team: String, companyRoot: URL)
    case remove(StaffNode, URL)
    case open(StaffNode, companyRoot: URL, inHolding: Bool)
}

@MainActor
final class StaffsTreeScreenModel: ActionScreenModel<StaffsTreeAction>, ViewModel {
    func observable(action: StaffsTreeAction) -> () -> Void {
        guard let app else { return {} }
        switch action {
        case .add(let name, let team, let root):
            app.addStaff(name: name, team: team, companyRoot: root)
        case .remove(let staff, let root):
            app.removeStaff(staff, companyRoot: root)
        case .open(let staff, let root, let inHolding):
            app.openStaff(staff, companyRoot: root, inHolding: inHolding)
        }
        return {}
    }
}

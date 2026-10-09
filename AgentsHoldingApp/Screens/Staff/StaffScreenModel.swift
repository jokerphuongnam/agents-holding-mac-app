import ScreenViewModel
import Foundation

enum StaffScreenAction {
    case back
    case openUsage(name: String, inHolding: Bool)
    case rename(StaffDetail, String)
    case remove(StaffNode, URL)
    case clearLead(name: String, companyRoot: URL)
    case setLead(name: String, lead: String, companyRoot: URL)
    case openStaff(StaffNode, inHolding: Bool)
    case openNamed(String)
    case setFence(file: URL, allowed: [String], denied: [String])
    case refresh
    case openCodeFile(CodeFileRef)
    case openSkill(SkillRef)
    case fail(String)
}

@MainActor
final class StaffScreenModel: ActionScreenModel<StaffScreenAction> {
    override func observable(action: StaffScreenAction) -> Effect<StaffScreenAction> {
        guard let app else { return .none }
        switch action {
        case .back:
            app.backFromStaff()
        case .openUsage(let name, let inHolding):
            app.openUsageForStaff(name, inHolding: inHolding)
        case .rename(let detail, let name):
            app.renameStaff(detail, to: name)
        case .remove(let staff, let root):
            app.removeStaff(staff, companyRoot: root)
        case .clearLead(let name, let root):
            app.setStaffLead(of: name, to: "", companyRoot: root)
        case .setLead(let name, let lead, let root):
            app.setStaffLead(of: name, to: lead, companyRoot: root)
        case .openStaff(let staff, let inHolding):
            app.openStaff(staff, inHolding: inHolding)
        case .openNamed(let name):
            app.openStaffNamed(name)
        case .setFence(let file, let allowed, let denied):
            app.setPathFence(file: file, allowed: allowed, denied: denied)
        case .refresh:
            app.refreshOpenStaff()
        case .openCodeFile(let file):
            app.openCodeFile(file)
        case .openSkill(let skill):
            app.openSkill(skill)
        case .fail(let message):
            app.lastError = message
        }
        return .none
    }
}

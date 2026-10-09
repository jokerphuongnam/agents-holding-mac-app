import ScreenViewModel
import Foundation

enum CompanyScreenAction {
    case refresh
    case back
    case openUsage
    case rename(String)
    case openStaff(StaffNode)
    case openChild(CompanyNode)
    case openSkill(SkillRef)
    case openCodeFile(CodeFileRef)
    case removeStaff(StaffNode, URL)
    case addStaff(name: String, team: String, companyRoot: URL)
}

@MainActor
final class CompanyScreenModel: ActionScreenModel<CompanyScreenAction> {
    override func observable(action: CompanyScreenAction, cancel _: Cancel) -> Effect<CompanyScreenAction> {
        guard let app else { return .none }
        switch action {
        case .refresh:
            app.refreshOpenCompany()
        case .back:
            app.backOneCompany()
        case .openUsage:
            app.openUsageCompany()
        case .rename(let name):
            app.renameOpenCompany(to: name)
        case .openStaff(let staff):
            app.openStaff(staff, inHolding: false)
        case .openChild(let child):
            app.openCompanyNode(child)
        case .openSkill(let skill):
            app.openSkill(skill)
        case .openCodeFile(let file):
            app.openCodeFile(file)
        case .removeStaff(let staff, let root):
            app.removeStaff(staff, companyRoot: root)
        case .addStaff(let name, let team, let root):
            app.addStaff(name: name, team: team, companyRoot: root)
        }
        return .none
    }
}

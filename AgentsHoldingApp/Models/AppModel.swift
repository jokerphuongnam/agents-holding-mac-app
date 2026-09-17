import Combine
import Foundation

/// App-wide navigation + discovered holding/company graph (P0 read model).
@MainActor
final class AppModel: ObservableObject {
    @Published var holdingPath: URL?
    @Published var holding: HoldingSnapshot?
    @Published var openCompany: CompanySnapshot?
    @Published var selection: NavigationSelection = .holding
    @Published var lastError: String?
    @Published var companyStack: [CompanyNode] = []
    @Published var staffDetail: StaffDetail?
    @Published var openSkill: SkillRef?

    /// When viewing holding staff, company OS root is the holding package.
    private var holdingPackageRoot: URL?

    private let holdingDiscovery = HoldingDiscovery()
    private let companyDiscovery = CompanyDiscovery()
    private let staffDirectory = StaffDirectory()

    init() {
        reloadHolding()
    }

    func reloadHolding() {
        lastError = nil
        do {
            let path = try holdingDiscovery.resolveHoldingPath()
            holdingPath = path
            let snap = try holdingDiscovery.loadSnapshot(at: path)
            holding = snap
            holdingPackageRoot = resolveHoldingPackage(from: path)
            openCompany = nil
            companyStack = []
            staffDetail = nil
            openSkill = nil
            selection = .holding
        } catch {
            holdingPath = nil
            holding = nil
            holdingPackageRoot = nil
            openCompany = nil
            lastError = error.localizedDescription
        }
    }

    func openCompanyNode(_ company: CompanyNode) {
        lastError = nil
        do {
            let snap = try companyDiscovery.loadCompany(from: company, holdingRoot: holdingPath)
            openCompany = snap
            if let idx = companyStack.firstIndex(where: { $0.id == company.id }) {
                companyStack = Array(companyStack.prefix(through: idx))
                companyStack[idx] = snap.node
            } else {
                companyStack.append(snap.node)
            }
            staffDetail = nil
            openSkill = nil
            selection = .company(snap.node.id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func openStaff(_ staff: StaffNode, inHolding: Bool = false) {
        let root: URL?
        if inHolding {
            root = holdingPackageRoot
        } else {
            root = openCompany?.companyRoot
        }
        guard let root,
              let detail = staffDirectory.loadStaffDetail(name: staff.name, team: staff.team, companyRoot: root)
        else {
            lastError = "Could not load staff \(staff.name)"
            return
        }
        staffDetail = detail
        openSkill = nil
        selection = .staff(staff.id)
    }

    func openSkill(_ skill: SkillRef) {
        openSkill = skill
        selection = .skill(skill.skillID)
    }

    func backToHolding() {
        openCompany = nil
        companyStack = []
        staffDetail = nil
        openSkill = nil
        selection = .holding
    }

    func backOneCompany() {
        staffDetail = nil
        openSkill = nil
        guard companyStack.count > 1 else {
            backToHolding()
            return
        }
        companyStack.removeLast()
        if let parent = companyStack.last {
            openCompanyNode(parent)
        }
    }

    func backFromStaff() {
        openSkill = nil
        staffDetail = nil
        if let company = openCompany?.node {
            selection = .company(company.id)
        } else {
            selection = .holding
        }
    }

    func backFromSkill() {
        openSkill = nil
        if let staff = staffDetail {
            selection = .staff(staff.node.id)
        } else {
            backFromStaff()
        }
    }

    private func resolveHoldingPackage(from holdingRoot: URL) -> URL? {
        let nested = holdingRoot.appendingPathComponent("holding")
        if FileManager.default.fileExists(atPath: nested.appendingPathComponent("system/staffs").path) {
            return nested
        }
        if FileManager.default.fileExists(atPath: holdingRoot.appendingPathComponent("system/staffs").path) {
            return holdingRoot
        }
        return nil
    }
}

enum NavigationSelection: Hashable {
    case holding
    case company(String)
    case staff(String)
    case skill(String)
    case usage
}

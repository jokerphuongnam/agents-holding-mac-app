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
    @Published var openCodeFile: CodeFileRef?
    /// Scope for Usage screen (holding / company+children / staff).
    @Published var usageScope: UsageScope = .holdingAll

    /// When viewing holding staff, company OS root is the holding package.
    private(set) var holdingPackageRoot: URL?

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
            openCodeFile = nil
            usageScope = .holdingAll
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
            openCodeFile = nil
            selection = .company(snap.node.id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Re-read the open company from disk (staffs / agents.tsv / nested teams).
    func refreshOpenCompany() {
        guard let node = openCompany?.node ?? companyStack.last else { return }
        openCompanyNode(node)
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
        openCodeFile = nil
        selection = .staff(staff.id)
    }

    /// Open staff by role name within the current company OS (or holding).
    func openStaffNamed(_ name: String) {
        let inHolding = openCompany == nil
        let teams = inHolding ? (holding?.teams ?? []) : (openCompany?.teams ?? [])
        if let node = teams.flatMap(\.allStaffs).first(where: { $0.name == name }) {
            openStaff(node, inHolding: inHolding)
            return
        }
        // Fallback: search team folders via detail loader (team unknown).
        let root = inHolding ? holdingPackageRoot : openCompany?.companyRoot
        guard let root else {
            lastError = "No company/holding root to open staff \(name)"
            return
        }
        let teamPaths = teams.flatMap { collectTeamIDs($0) } + ["leadership"]
        for team in teamPaths {
            if let detail = staffDirectory.loadStaffDetail(name: name, team: team, companyRoot: root) {
                staffDetail = detail
                openSkill = nil
                openCodeFile = nil
                selection = .staff(detail.node.id)
                return
            }
        }
        lastError = "Staff not found: \(name)"
    }

    private func collectTeamIDs(_ team: TeamNode) -> [String] {
        [team.id] + team.childTeams.flatMap { collectTeamIDs($0) }
    }

    func openSkill(_ skill: SkillRef) {
        openSkill = skill
        openCodeFile = nil
        selection = .skill(skill.skillID)
    }

    func openCodeFile(_ file: CodeFileRef) {
        openCodeFile = file
        openSkill = nil
        selection = .codeFile(file.id)
    }

    func openUsageHolding() {
        usageScope = .holdingAll
        selection = .usage
    }

    func openUsageCompany() {
        usageScope = .companySubtree
        selection = .usage
    }

    func openUsageForStaff(_ name: String, inHolding: Bool) {
        usageScope = .staff(name: name, inHolding: inHolding)
        selection = .usage
    }

    /// Leave Usage and return to the screen that opened it.
    func backFromUsage() {
        switch usageScope {
        case .staff(let name, let inHolding):
            if let detail = staffDetail, detail.node.name == name {
                selection = .staff(detail.node.id)
            } else if let node = (inHolding ? holding?.teams : openCompany?.teams)?
                .flatMap(\.allStaffs)
                .first(where: { $0.name == name }) {
                openStaff(node, inHolding: inHolding)
            } else if let company = openCompany?.node, !inHolding {
                selection = .company(company.id)
            } else {
                selection = .holding
            }
        case .companySubtree:
            if let company = openCompany?.node {
                selection = .company(company.id)
            } else {
                selection = .holding
            }
        case .holdingAll:
            selection = .holding
        }
    }

    /// Company OS roots for the current usage scope (parent + children when subtree).
    func usageCompanyRoots() -> [(slug: String, root: URL)] {
        switch usageScope {
        case .holdingAll:
            return allRegisteredCompanyRoots()
        case .companySubtree:
            guard let open = openCompany else { return [] }
            return companySubtreeRoots(from: open)
        case .staff(_, let inHolding):
            if inHolding {
                return allRegisteredCompanyRoots()
            }
            guard let open = openCompany else { return [] }
            return companySubtreeRoots(from: open)
        }
    }

    private func allRegisteredCompanyRoots() -> [(slug: String, root: URL)] {
        guard let holding else { return [] }
        var out: [(String, URL)] = []
        for company in holding.companies {
            if let snap = try? companyDiscovery.loadCompany(from: company, holdingRoot: holdingPath) {
                out.append((snap.node.slug, snap.companyRoot))
            }
        }
        return out
    }

    private func companySubtreeRoots(from snap: CompanySnapshot) -> [(slug: String, root: URL)] {
        var out: [(String, URL)] = [(snap.node.slug, snap.companyRoot)]
        for child in snap.children {
            if let childSnap = try? companyDiscovery.loadCompany(from: child, holdingRoot: holdingPath) {
                out.append(contentsOf: companySubtreeRoots(from: childSnap))
            }
        }
        return out
    }

    func backToHolding() {
        openCompany = nil
        companyStack = []
        staffDetail = nil
        openSkill = nil
        openCodeFile = nil
        selection = .holding
    }

    func backOneCompany() {
        staffDetail = nil
        openSkill = nil
        openCodeFile = nil
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
        openCodeFile = nil
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
        } else if let company = openCompany?.node {
            selection = .company(company.id)
        } else {
            selection = .holding
        }
    }

    func backFromCodeFile() {
        openCodeFile = nil
        if let company = openCompany?.node {
            selection = .company(company.id)
        } else {
            selection = .holding
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
    case codeFile(String)
    case usage
}

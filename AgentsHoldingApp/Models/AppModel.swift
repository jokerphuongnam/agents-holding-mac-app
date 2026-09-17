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
    /// Breadcrumb stack of company ids (holding → parent → child …).
    @Published var companyStack: [CompanyNode] = []

    private let holdingDiscovery = HoldingDiscovery()
    private let companyDiscovery = CompanyDiscovery()

    init() {
        reloadHolding()
    }

    func reloadHolding() {
        lastError = nil
        do {
            let path = try holdingDiscovery.resolveHoldingPath()
            holdingPath = path
            holding = try holdingDiscovery.loadSnapshot(at: path)
            openCompany = nil
            companyStack = []
            selection = .holding
        } catch {
            holdingPath = nil
            holding = nil
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
            selection = .company(snap.node.id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func openStaff(_ staff: StaffNode) {
        selection = .staff(staff.id)
    }

    func backToHolding() {
        openCompany = nil
        companyStack = []
        selection = .holding
    }

    func backOneCompany() {
        guard companyStack.count > 1 else {
            backToHolding()
            return
        }
        companyStack.removeLast()
        if let parent = companyStack.last {
            openCompanyNode(parent)
        }
    }

    func staff(for id: String) -> StaffNode? {
        openCompany?.teams.flatMap(\.staffs).first { $0.id == id }
    }

    func company(for id: String) -> CompanyNode? {
        if let open = openCompany, open.node.id == id { return open.node }
        if let stacked = companyStack.first(where: { $0.id == id }) { return stacked }
        return holding?.companies.first { $0.id == id }
    }
}

enum NavigationSelection: Hashable {
    case holding
    case company(String)
    case staff(String)
    case usage
}

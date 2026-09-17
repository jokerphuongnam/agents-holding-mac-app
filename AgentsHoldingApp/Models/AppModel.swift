import Combine
import Foundation

/// App-wide navigation + discovered holding/company graph (P0 read model).
@MainActor
final class AppModel: ObservableObject {
    @Published var holdingPath: URL?
    @Published var holding: HoldingSnapshot?
    @Published var selection: NavigationSelection = .holding
    @Published var lastError: String?

    private let discovery = HoldingDiscovery()

    init() {
        reloadHolding()
    }

    func reloadHolding() {
        lastError = nil
        do {
            let path = try discovery.resolveHoldingPath()
            holdingPath = path
            holding = try discovery.loadSnapshot(at: path)
            selection = .holding
        } catch {
            holdingPath = nil
            holding = nil
            lastError = error.localizedDescription
        }
    }

    func openCompany(_ company: CompanyNode) {
        selection = .company(company.id)
    }

    func openStaff(_ staff: StaffNode) {
        selection = .staff(staff.id)
    }

    func backToHolding() {
        selection = .holding
    }
}

enum NavigationSelection: Hashable {
    case holding
    case company(String)
    case staff(String)
    case usage
}

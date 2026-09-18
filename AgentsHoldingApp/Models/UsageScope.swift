import Foundation

/// How the Usage screen is opened / scoped.
enum UsageScope: Equatable {
    /// All companies currently in the holding registry (+ holding ledger).
    case holdingAll
    /// Open company + its child companies (recursive).
    case companySubtree
    /// Analytics for one staff; company context = holding-all or company-subtree.
    case staff(name: String, inHolding: Bool)

    var staffName: String? {
        if case .staff(let name, _) = self { return name }
        return nil
    }
}

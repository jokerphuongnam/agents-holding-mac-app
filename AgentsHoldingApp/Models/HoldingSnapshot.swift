import Foundation

struct HoldingSnapshot: Equatable {
    var path: URL
    var name: String
    var staffs: [StaffNode]
    var companies: [CompanyNode]
}

struct StaffNode: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var blurb: String
    var group: String
}

struct CompanyNode: Identifiable, Hashable {
    /// Registry id when present; otherwise `slug|projectRoot` (slug alone is not unique).
    var id: String
    var slug: String
    var displayName: String
    var projectRoot: URL?
    var companyPath: URL?
    var status: String
    var budget: String
    var topology: String
    var pointerPath: URL?

    init(
        id: String? = nil,
        slug: String,
        displayName: String? = nil,
        projectRoot: URL? = nil,
        companyPath: URL? = nil,
        status: String = "active",
        budget: String = "",
        topology: String = "",
        pointerPath: URL? = nil
    ) {
        if let id, !id.isEmpty, id != slug {
            self.id = id
        } else {
            let rootKey = projectRoot?.path ?? companyPath?.path ?? ""
            self.id = rootKey.isEmpty ? slug : "\(slug)|\(rootKey)"
        }
        self.slug = slug
        self.displayName = displayName ?? slug.replacingOccurrences(of: "-company", with: "")
        self.projectRoot = projectRoot
        self.companyPath = companyPath
        self.status = status
        self.budget = budget
        self.topology = topology
        self.pointerPath = pointerPath
    }
}

import Foundation

struct HoldingSnapshot: Equatable {
    var path: URL
    var name: String
    /// Holding inventory = companies only (no holding staff roster on home canvas).
    var companies: [CompanyNode]
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

/// Opened company: child companies + teams with nested staffs.
struct CompanySnapshot: Equatable {
    var node: CompanyNode
    var children: [CompanyNode]
    var teams: [TeamNode]
}

struct TeamNode: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var staffs: [StaffNode]
}

struct StaffNode: Identifiable, Hashable {
    /// Unique within a company: `team/name`.
    var id: String
    var name: String
    var team: String
    var blurb: String

    init(name: String, team: String, blurb: String) {
        self.id = "\(team)/\(name)"
        self.name = name
        self.team = team
        self.blurb = blurb
    }
}

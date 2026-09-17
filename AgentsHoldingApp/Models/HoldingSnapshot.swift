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
    var id: String { slug }
    var slug: String
    var displayName: String
    var pointerPath: URL?
    var projectRoot: URL?
}

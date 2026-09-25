import Foundation

/// Opens a dedicated Staffs tree window (`WindowGroup` id `staffs-tree`).
struct StaffsTreeWindowID: Codable, Hashable {
    /// Absolute path to company OS root (`system/staffs` parent).
    var companyRootPath: String
    var title: String
    var inHolding: Bool
}

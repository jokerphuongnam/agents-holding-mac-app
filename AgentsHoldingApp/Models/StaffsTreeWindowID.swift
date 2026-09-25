import Foundation

/// Opens a dedicated Staffs tree window (`WindowGroup` id `staffs-tree`).
struct StaffsTreeWindowID: Codable, Hashable {
    /// Absolute path to company OS root (`system/staffs` parent).
    var companyRootPath: String
    var title: String
    var inHolding: Bool
}

/// SwiftUI may restore / auto-open `WindowGroup(id:for:)` on launch.
/// Only keep the window when the toolbar button set this token first.
@MainActor
enum StaffsTreeWindowGate {
    private static var intentionalOpen = false

    static func markIntentionalOpen() {
        intentionalOpen = true
    }

    /// Returns whether this appearance was from the toolbar button, then clears the token.
    static func consumeOpenToken() -> Bool {
        let ok = intentionalOpen
        intentionalOpen = false
        return ok
    }
}

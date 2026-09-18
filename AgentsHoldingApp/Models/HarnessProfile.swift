import Foundation

struct HarnessModeProfile: Identifiable, Hashable {
    var id: String { mode }
    /// grok | claude | codex | merge
    var mode: String
    /// Effective vendor runtime (for merge: resolved; else same as mode).
    var runtime: String
    var model: String
    var effort: String
    var note: String
}

struct StaffHarnessProfiles: Identifiable, Hashable {
    var id: String { "\(staffName)|\(tier)" }
    var staffName: String
    var tier: String
    var modes: [HarnessModeProfile]
}

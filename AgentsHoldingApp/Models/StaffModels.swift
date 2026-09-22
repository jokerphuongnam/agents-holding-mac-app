import Foundation

struct StaffNode: Identifiable, Hashable {
    /// Unique within a roster: `team/name`.
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

/// One team folder under `system/staffs`. Child teams live in `teams/` beneath it.
/// Class so the tree can nest (a struct cannot contain itself).
final class TeamNode: Identifiable, Hashable {
    /// Path relative to `system/staffs`, e.g. `rust` or `rust/teams/ruma`.
    var id: String
    var name: String
    var staffs: [StaffNode]
    var childTeams: [TeamNode]

    init(id: String, name: String, staffs: [StaffNode], childTeams: [TeamNode] = []) {
        self.id = id
        self.name = name
        self.staffs = staffs
        self.childTeams = childTeams
    }

    var staffCount: Int {
        staffs.count + childTeams.reduce(0) { $0 + $1.staffCount }
    }

    var teamCount: Int {
        1 + childTeams.reduce(0) { $0 + $1.teamCount }
    }

    var allStaffs: [StaffNode] {
        staffs + childTeams.flatMap(\.allStaffs)
    }

    static func == (lhs: TeamNode, rhs: TeamNode) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct AgentRow: Hashable {
    var name: String
    var tier: String
    var permissionMode: String
    var capabilityMode: String
    var skillIDs: [String]
    var lead: String
    var qc: String
    var routing: String
    var blurb: String
}

struct SkillRef: Identifiable, Hashable {
    var id: String { skillID }
    var skillID: String
    var title: String
    /// Absolute path to SKILL.md when found.
    var path: URL?
    /// Display as a file row, e.g. `…/mpm-cli/SKILL.md`.
    var fileLabel: String {
        if let path {
            return path.lastPathComponent == "SKILL.md"
                ? "\(path.deletingLastPathComponent().lastPathComponent)/SKILL.md"
                : path.lastPathComponent
        }
        return "\(skillID)/SKILL.md (missing)"
    }
}

struct StaffDetail: Hashable {
    var node: StaffNode
    var tier: String
    var permissionMode: String
    var capabilityMode: String
    var lead: String?
    var reports: [StaffNode]
    var skills: [SkillRef]
    /// File rows for this staff's SKILL.md (same set as skills, for file-list UI).
    var skillFiles: [CodeFileRef]
    /// Scripts owned / used by this staff (under their skill dirs; ceo + hop scripts).
    var scriptFiles: [CodeFileRef]
    var allowedPaths: [String]
    var deniedHints: [String]
    var bodyMarkdown: String
    /// Company OS root used to resolve skills/scope (`…/*-company` or holding package).
    var companyRoot: URL
}

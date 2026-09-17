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

struct TeamNode: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var staffs: [StaffNode]
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
    var allowedPaths: [String]
    var deniedHints: [String]
    var bodyMarkdown: String
    /// Company OS root used to resolve skills/scope (`…/*-company` or holding package).
    var companyRoot: URL
}

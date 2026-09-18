import Foundation

struct TemplateStaff: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var team: String
    var blurb: String
    var recommended: Bool
}

struct LibrarySkill: Identifiable, Hashable {
    var id: String
    var title: String
    var path: String
    var tags: [String]
    var target: String
}

/// Editable roster row (template or newly added).
struct StaffDraft: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var team: String
    var blurb: String
    var isTemplate: Bool
    var isNew: Bool
    var description: String
    var selectedSkillIDs: Set<String>
    var allowPaths: [String]
    var tier: String
    var lead: String

    static func fromTemplate(_ t: TemplateStaff) -> StaffDraft {
        StaffDraft(
            name: t.name,
            team: t.team,
            blurb: t.blurb,
            isTemplate: true,
            isNew: false,
            description: t.blurb,
            selectedSkillIDs: [],
            allowPaths: [],
            tier: t.name.hasSuffix("-lead") || t.name == "ceo" || t.name == "cto" ? "dispatch" : "medium",
            lead: t.name == "ceo" ? "" : "ceo"
        )
    }
}

struct RosterSpec: Encodable {
    var keep_staffs: [String]
    var custom_staffs: [CustomStaffSpec]
    var extra_skill_ids: [String]
    var staff_path_fences: [String: [String]]
    var staff_configs: [String: StaffConfigSpec]

    struct StaffConfigSpec: Encodable {
        var skill_ids: [String]
        var paths: [String]
        var description: String
        var tier: String
        var lead: String
    }

    struct CustomStaffSpec: Encodable {
        var name: String
        var team: String
        var description: String
        var tier: String
        var lead: String
        var skill_ids: [String]
        var paths: [String]
        var new_skills: [NewSkillSpec]
    }

    struct NewSkillSpec: Encodable {
        var id: String
        var title: String
        var body: String
    }
}

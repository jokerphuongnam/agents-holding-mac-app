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

struct NewSkillDraft: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var skillID: String = ""
    var title: String = ""
    var body: String = ""
}

struct CustomStaffDraft: Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = ""
    var team: String = "custom"
    var description: String = ""
    var tier: String = "medium"
    var lead: String = "ceo"
    var selectedSkillIDs: Set<String> = []
    var newSkills: [NewSkillDraft] = []
}

struct RosterSpec: Encodable {
    var keep_staffs: [String]
    var custom_staffs: [CustomStaffSpec]
    var extra_skill_ids: [String]

    struct CustomStaffSpec: Encodable {
        var name: String
        var team: String
        var description: String
        var tier: String
        var lead: String
        var skill_ids: [String]
        var new_skills: [NewSkillSpec]
    }

    struct NewSkillSpec: Encodable {
        var id: String
        var title: String
        var body: String
    }
}

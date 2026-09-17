import Foundation

/// Loads staff templates + skills-library catalog from agents-holding.
struct TemplateCatalogService {
    func loadStaffTemplates(holdingRoot: URL) -> [TemplateStaff] {
        let root = staffsTemplateRoot(holdingRoot)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else {
            return []
        }
        let recommended: Set<String> = [
            "ceo", "cto", "ba-lead", "ba-user", "ba-workflow",
            "po-lead", "po-new", "po-modify", "git", "qc-lead",
        ]
        var out: [TemplateStaff] = []
        for team in names where !team.hasPrefix(".") {
            let teamDir = root.appendingPathComponent(team)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: teamDir.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: teamDir.path) else { continue }
            for file in files where file.hasSuffix(".md") && file != "ORG.md" {
                let name = (file as NSString).deletingPathExtension
                let text = (try? String(contentsOf: teamDir.appendingPathComponent(file), encoding: .utf8)) ?? ""
                let blurb = firstDescription(text) ?? name
                out.append(
                    TemplateStaff(
                        name: name,
                        team: team,
                        blurb: blurb,
                        recommended: recommended.contains(name)
                    )
                )
            }
        }
        return out.sorted {
            if $0.recommended != $1.recommended { return $0.recommended && !$1.recommended }
            if $0.team != $1.team { return $0.team < $1.team }
            return $0.name < $1.name
        }
    }

    func loadLibrarySkills(holdingRoot: URL) -> [LibrarySkill] {
        let library = skillsLibraryRoot(holdingRoot)
        let manifest = library.appendingPathComponent("MANIFEST.json")
        guard let data = try? Data(contentsOf: manifest),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let skills = json["skills"] as? [[String: Any]]
        else { return [] }

        return skills.compactMap { row -> LibrarySkill? in
            guard let id = row["id"] as? String else { return nil }
            let path = row["path"] as? String ?? id
            let tags = row["tags"] as? [String] ?? []
            let target = row["target"] as? String ?? ""
            return LibrarySkill(id: id, title: id, path: path, tags: tags, target: target)
        }
        .sorted { $0.id < $1.id }
    }

    private func staffsTemplateRoot(_ holdingRoot: URL) -> URL {
        let candidates = [
            holdingRoot.appendingPathComponent("templates/company/system/staffs"),
            holdingRoot.appendingPathComponent("holding/../templates/company/system/staffs"),
        ]
        for c in candidates {
            let standardized = c.standardizedFileURL
            if FileManager.default.fileExists(atPath: standardized.path) {
                return standardized
            }
        }
        return holdingRoot.appendingPathComponent("templates/company/system/staffs")
    }

    private func skillsLibraryRoot(_ holdingRoot: URL) -> URL {
        let c = holdingRoot.appendingPathComponent("templates/skills-library").standardizedFileURL
        if FileManager.default.fileExists(atPath: c.path) { return c }
        return holdingRoot.appendingPathComponent("templates/skills-library")
    }

    private func firstDescription(_ text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("description:") {
                return t.dropFirst("description:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        let body = text.components(separatedBy: "---")
        if body.count >= 3 {
            for line in body[2].components(separatedBy: .newlines) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty && !t.hasPrefix("#") {
                    return String(t.prefix(120))
                }
            }
        }
        return nil
    }
}

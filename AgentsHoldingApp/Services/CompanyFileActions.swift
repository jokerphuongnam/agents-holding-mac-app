import Foundation

enum CompanyFileActions {
    static func delete(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    static func createPlan(name: String, owner: String, companyRoot: URL) throws -> URL {
        let file = companyRoot
            .appendingPathComponent("cache/plans")
            .appendingPathComponent(fileName(name, fallbackExtension: "md"))
        let body = "# \(file.deletingPathExtension().lastPathComponent)\n\nPlan owner: `\(owner)`\n"
        try writeNew(body, to: file)
        return file
    }

    static func createSkill(name: String, staff: String, team: String, companyRoot: URL) throws -> URL {
        let slug = slugify(name)
        let file = companyRoot
            .appendingPathComponent("system/skills/customs")
            .appendingPathComponent(team)
            .appendingPathComponent(staff)
            .appendingPathComponent(slug)
            .appendingPathComponent("SKILL.md")
        let body = "---\nname: \(slug)\ndescription: \n---\n\n# \(slug)\n"
        try writeNew(body, to: file)
        return file
    }

    static func createScript(name: String, staff: String, team: String, companyRoot: URL, hop: Bool) throws -> URL {
        let fileName = fileName(name, fallbackExtension: "py")
        let dir = hop
            ? companyRoot.appendingPathComponent("system/skills/defaults/marlin-hop/scripts")
            : companyRoot
                .appendingPathComponent("system/skills/customs")
                .appendingPathComponent(team)
                .appendingPathComponent(staff)
                .appendingPathComponent("scripts")
        let file = dir.appendingPathComponent(fileName)
        try writeNew("", to: file)
        return file
    }

    private static func writeNew(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func slugify(_ raw: String) -> String {
        let cleaned = raw.lowercased().map { ch -> Character in
            ch.isLetter || ch.isNumber ? ch : "-"
        }
        let slug = String(cleaned).split(separator: "-").joined(separator: "-")
        return slug.isEmpty ? "new-skill" : slug
    }

    private static func fileName(_ raw: String, fallbackExtension: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "untitled" : trimmed
        if (base as NSString).pathExtension.isEmpty {
            return "\(base).\(fallbackExtension)"
        }
        return base
    }
}

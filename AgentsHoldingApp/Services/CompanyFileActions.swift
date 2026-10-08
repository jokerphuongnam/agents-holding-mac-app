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

    static func createStaff(name: String, team: String, companyRoot: URL) throws {
        let slug = slugify(name)
        let folder = appendRelative(team, to: companyRoot.appendingPathComponent("system/staffs"))
        let file = folder.appendingPathComponent("\(slug).md")
        let body = """
        ---
        name: \(slug)
        description:
        tier: default
        permission_mode: default
        capability_mode: all
        ---

        """
        try writeNew(body, to: file)
        let lead = soleLead(in: folder, excluding: slug)
        try appendAgentRow(name: slug, lead: lead, companyRoot: companyRoot)
        if let lead {
            try appendRoster(parent: lead, child: slug, companyRoot: companyRoot)
        } else if slug.hasSuffix("-lead"), slug != "ceo" {
            try appendRoster(parent: "ceo", child: slug, companyRoot: companyRoot)
        }
    }

    /// Point `name` at `lead` in agents.tsv and roster.tsv. Empty lead removes the roster row.
    /// Replace the `## Path fence` block in a staff file. Other sections stay as they are.
    static func writePathFence(file: URL, allowed: [String], denied: [String]) throws {
        var text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let block = renderPathFence(allowed: allowed, denied: denied)
        if let range = pathFenceRange(in: text) {
            text.replaceSubrange(range, with: block)
        } else {
            if !text.hasSuffix("\n") { text += "\n" }
            text += "\n" + block
        }
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    private static func renderPathFence(allowed: [String], denied: [String]) -> String {
        var lines = ["## Path fence", "", "### allow_rw"]
        lines.append(contentsOf: allowed.map { "- `\($0)`" })
        lines.append("")
        lines.append("### deny")
        lines.append(contentsOf: denied.map { "- `\($0)`" })
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func pathFenceRange(in text: String) -> Range<String.Index>? {
        let needle = "## Path fence"
        guard let start = text.range(of: needle)?.lowerBound else { return nil }
        var end = text.endIndex
        let rest = text[start...].dropFirst(needle.count)
        if let next = rest.range(of: "\n## ") {
            end = next.lowerBound
        }
        return start..<end
    }

    /// Rename a staff everywhere the hop uses that id: file, frontmatter, agents, roster, skill folder.
    static func renameStaff(from old: String, to raw: String, team: String, companyRoot: URL) throws -> String {
        let slug = slugify(raw)
        guard slug != old else { return old }
        let folder = appendRelative(team, to: companyRoot.appendingPathComponent("system/staffs"))
        let source = folder.appendingPathComponent("\(old).md")
        let destination = folder.appendingPathComponent("\(slug).md")
        if FileManager.default.fileExists(atPath: destination.path) {
            throw CocoaError(.fileWriteFileExists)
        }
        if FileManager.default.fileExists(atPath: source.path) {
            try FileManager.default.moveItem(at: source, to: destination)
        }
        try setFrontmatter(destination, key: "name", value: slug)
        try replaceName(old, with: slug, in: hopData(companyRoot, "agents.tsv"))
        try replaceName(old, with: slug, in: hopData(companyRoot, "roster.tsv"))
        try renameCustomsFolder(team: team, from: old, to: slug, companyRoot: companyRoot)
        try renameRouterMatch(from: old, to: slug, companyRoot: companyRoot)
        return slug
    }

    /// Visible company title. Slug and folder stay put.
    static func storedDisplayName(companyPath: URL) -> String? {
        let url = companyPath.appendingPathComponent("COMPANY.md")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: .newlines).prefix(20) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("name:") else { continue }
            let value = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    static func setDisplayName(_ name: String, companyPath: URL) throws {
        let url = companyPath.appendingPathComponent("COMPANY.md")
        var lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").components(separatedBy: "\n")
        let row = "name: \(name)"
        if let index = lines.prefix(20).firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("name:")
        }) {
            lines[index] = row
        } else {
            lines.insert(row, at: 0)
            lines.insert("", at: 1)
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func setTier(of name: String, to tier: String, staffFile: URL, companyRoot: URL) throws {
        try updateAgentColumn(name: name, column: "tier", value: tier, companyRoot: companyRoot)
        try setFrontmatter(staffFile, key: "tier", value: tier)
    }

    static func setLead(of name: String, to lead: String, companyRoot: URL) throws {
        try updateAgentLead(name: name, lead: lead, companyRoot: companyRoot)
        try removeRosterChild(name, companyRoot: companyRoot)
        if !lead.isEmpty, lead != name {
            try appendRoster(parent: lead, child: name, companyRoot: companyRoot)
        }
    }

    static func deleteStaff(name: String, team: String, companyRoot: URL) throws {
        let folder = appendRelative(team, to: companyRoot.appendingPathComponent("system/staffs"))
        let file = folder.appendingPathComponent("\(name).md")
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
        try removeAgentRow(name: name, companyRoot: companyRoot)
        try removeRosterRows(name: name, companyRoot: companyRoot)
    }

    private static func soleLead(in folder: URL, excluding name: String) -> String? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let leads = names.compactMap { file -> String? in
            guard file.hasSuffix(".md") else { return nil }
            let stem = (file as NSString).deletingPathExtension
            guard stem != name, stem.hasSuffix("-lead"), stem != "ceo", stem != "holding-ceo" else { return nil }
            return stem
        }
        return leads.count == 1 ? leads[0] : nil
    }

    private static func hopData(_ companyRoot: URL, _ file: String) -> URL {
        companyRoot
            .appendingPathComponent("system/skills/defaults/marlin-hop/data")
            .appendingPathComponent(file)
    }

    private static func appendAgentRow(name: String, lead: String?, companyRoot: URL) throws {
        let url = hopData(companyRoot, "agents.tsv")
        var text = (try? String(contentsOf: url, encoding: .utf8)) ?? "name\ttier\tpermission_mode\tcapability_mode\tskill\tlead\tqc\trouting\tblurb\n"
        if text.split(whereSeparator: \.isNewline).contains(where: { $0.split(separator: "\t").first.map(String.init) == name }) {
            return
        }
        if !text.hasSuffix("\n") { text += "\n" }
        text += "\(name)\tdefault\tdefault\tall\t\t\(lead ?? "")\t\t0\t\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func updateAgentLead(name: String, lead: String, companyRoot: URL) throws {
        try updateAgentColumn(name: name, column: "lead", value: lead, companyRoot: companyRoot)
    }

    private static func updateAgentColumn(name: String, column: String, value: String, companyRoot: URL) throws {
        let url = hopData(companyRoot, "agents.tsv")
        var lines = (try? String(contentsOf: url, encoding: .utf8))?
            .components(separatedBy: .newlines) ?? []
        guard let header = lines.first else { return }
        let keys = header.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard let columnIndex = keys.firstIndex(of: column) else { return }
        var found = false
        for index in lines.indices where index > 0 {
            var cols = lines[index].split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cols.first == name else { continue }
            while cols.count < keys.count { cols.append("") }
            cols[columnIndex] = value
            lines[index] = cols.joined(separator: "\t")
            found = true
            break
        }
        if !found {
            var cols = Array(repeating: "", count: keys.count)
            if let nameIndex = keys.firstIndex(of: "name") { cols[nameIndex] = name }
            cols[columnIndex] = value
            lines.append(cols.joined(separator: "\t"))
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func setFrontmatter(_ file: URL, key: String, value: String) throws {
        var text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        var lines = text.components(separatedBy: "\n")
        guard lines.first == "---" else { return }
        var end = 1
        while end < lines.count, lines[end] != "---" { end += 1 }
        guard end < lines.count else { return }
        var replaced = false
        for index in 1..<end {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(key + ":") {
                lines[index] = "\(key): \(value)"
                replaced = true
                break
            }
        }
        if !replaced { lines.insert("\(key): \(value)", at: end) }
        text = lines.joined(separator: "\n")
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    private static func removeRosterChild(_ name: String, companyRoot: URL) throws {
        let url = hopData(companyRoot, "roster.tsv")
        guard var lines = try? String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines) else { return }
        lines.removeAll { line in
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            return cols.count >= 2 && cols[1] == name
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func removeAgentRow(name: String, companyRoot: URL) throws {
        let url = hopData(companyRoot, "agents.tsv")
        guard var lines = try? String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines) else { return }
        lines.removeAll { $0.split(separator: "\t", omittingEmptySubsequences: false).first.map(String.init) == name }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func appendRoster(parent: String, child: String, companyRoot: URL) throws {
        let url = hopData(companyRoot, "roster.tsv")
        var text = (try? String(contentsOf: url, encoding: .utf8)) ?? "parent\tchild\n"
        let row = "\(parent)\t\(child)"
        if text.contains(row) { return }
        if !text.hasSuffix("\n") { text += "\n" }
        text += row + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func removeRosterRows(name: String, companyRoot: URL) throws {
        let url = hopData(companyRoot, "roster.tsv")
        guard var lines = try? String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines) else { return }
        lines.removeAll { line in
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            return cols.count >= 2 && (cols[0] == name || cols[1] == name)
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func replaceName(_ old: String, with new: String, in url: URL) throws {
        guard var lines = try? String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines) else { return }
        for index in lines.indices {
            var cols = lines[index].split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            var changed = false
            for col in cols.indices where cols[col] == old {
                cols[col] = new
                changed = true
            }
            if changed { lines[index] = cols.joined(separator: "\t") }
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func renameCustomsFolder(team: String, from old: String, to new: String, companyRoot: URL) throws {
        let customs = companyRoot.appendingPathComponent("system/skills/customs")
        let source = appendRelative(team, to: customs).appendingPathComponent(old)
        let destination = appendRelative(team, to: customs).appendingPathComponent(new)
        guard FileManager.default.fileExists(atPath: source.path),
              !FileManager.default.fileExists(atPath: destination.path) else { return }
        try FileManager.default.moveItem(at: source, to: destination)
    }

    private static func renameRouterMatch(from old: String, to new: String, companyRoot: URL) throws {
        let url = companyRoot.appendingPathComponent("system/harness/runtime_router.toml")
        guard var text = try? String(contentsOf: url, encoding: .utf8) else { return }
        text = text.replacingOccurrences(of: "match = \"\(old)\"", with: "match = \"\(new)\"")
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func appendRelative(_ relative: String, to base: URL) -> URL {
        relative.split(separator: "/").filter { !$0.isEmpty }.reduce(base) {
            $0.appendingPathComponent(String($1))
        }
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

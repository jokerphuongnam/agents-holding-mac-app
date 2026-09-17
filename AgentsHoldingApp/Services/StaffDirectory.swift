import Foundation

/// Shared roster + staff detail (agents.tsv, staffs/**, skills/**, SCOPE.md).
struct StaffDirectory {
    func loadTeams(companyRoot: URL) -> [TeamNode] {
        let staffsRoot = companyRoot.appendingPathComponent("system/staffs")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: staffsRoot.path) else {
            return []
        }
        var teams: [TeamNode] = []
        for name in names where !name.hasPrefix(".") {
            let url = staffsRoot.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            teams.append(TeamNode(name: name, staffs: loadStaffNodes(inTeamDir: url, team: name)))
        }
        return teams.sorted { $0.name < $1.name }
    }

    func loadStaffDetail(name: String, team: String, companyRoot: URL) -> StaffDetail? {
        let staffFile = companyRoot
            .appendingPathComponent("system/staffs")
            .appendingPathComponent(team)
            .appendingPathComponent("\(name).md")
        guard FileManager.default.fileExists(atPath: staffFile.path),
              let body = try? String(contentsOf: staffFile, encoding: .utf8)
        else { return nil }

        let agents = loadAgentsTSV(companyRoot: companyRoot)
        let row = agents[name]
        let allNodes = loadTeams(companyRoot: companyRoot).flatMap(\.staffs)
        let node = allNodes.first { $0.name == name && $0.team == team }
            ?? StaffNode(name: name, team: team, blurb: row?.blurb ?? firstBlurb(body) ?? "")

        // Cấp trên = who may Assign/hop to command this staff.
        // agents.tsv `lead` when set; else company `ceo` / holding `holding-ceo` (tops have none).
        let lead = resolveLead(name: name, row: row, agents: agents, companyRoot: companyRoot)
        let reports = allNodes.filter { staff in
            resolveLead(name: staff.name, row: agents[staff.name], agents: agents, companyRoot: companyRoot) == name
        }.sorted { $0.name < $1.name }

        let skillIDs = row?.skillIDs ?? []
        let skills = skillIDs.map { id in resolveSkill(id: id, companyRoot: companyRoot) }

        let (allowed, denied) = parsePathLimits(
            staffBody: body,
            team: team,
            companyRoot: companyRoot
        )

        return StaffDetail(
            node: node,
            tier: row?.tier ?? frontmatter(body, key: "tier") ?? "",
            permissionMode: row?.permissionMode ?? frontmatter(body, key: "permission_mode") ?? "",
            capabilityMode: row?.capabilityMode ?? frontmatter(body, key: "capability_mode") ?? "",
            lead: lead,
            reports: reports,
            skills: skills,
            allowedPaths: allowed,
            deniedHints: denied,
            bodyMarkdown: stripFrontmatter(body),
            companyRoot: companyRoot
        )
    }

    /// Who can hop/Assign orders to `name`.
    private func resolveLead(
        name: String,
        row: AgentRow?,
        agents: [String: AgentRow],
        companyRoot: URL
    ) -> String? {
        let explicit = row?.lead.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicit.isEmpty { return explicit }

        let top = topDispatcher(in: agents, companyRoot: companyRoot)
        if name == top { return nil }

        // Empty lead in TSV usually means “reports to company dispatcher” (ceo / holding-ceo),
        // e.g. qc-lead, game-lead, ba-lead — ceo Assigns them; they Assign their ICs.
        if agents[top] != nil || FileManager.default.fileExists(
            atPath: companyRoot.appendingPathComponent("system/staffs/leadership/\(top).md").path
        ) {
            return top
        }
        return nil
    }

    private func topDispatcher(in agents: [String: AgentRow], companyRoot: URL) -> String {
        if agents["holding-ceo"] != nil
            || FileManager.default.fileExists(
                atPath: companyRoot.appendingPathComponent("system/staffs/leadership/holding-ceo.md").path
            )
        {
            return "holding-ceo"
        }
        return "ceo"
    }

    func loadAgentsTSV(companyRoot: URL) -> [String: AgentRow] {
        let path = companyRoot
            .appendingPathComponent("system/skills/defaults/marlin-hop/data/agents.tsv")
        guard let text = try? String(contentsOf: path, encoding: .utf8) else { return [:] }
        var out: [String: AgentRow] = [:]
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let headerLine = lines.first else { return [:] }
        let headers = headerLine.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        func idx(_ name: String) -> Int? { headers.firstIndex(of: name) }

        for line in lines.dropFirst() where !line.hasPrefix("#") && !line.isEmpty {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let nameIdx = idx("name"), nameIdx < cols.count else { continue }
            let name = cols[nameIdx]
            guard !name.isEmpty else { continue }
            let skillRaw = col(cols, idx("skill"))
            let skillIDs = skillRaw
                .split(whereSeparator: { ",;|".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            out[name] = AgentRow(
                name: name,
                tier: col(cols, idx("tier")),
                permissionMode: col(cols, idx("permission_mode")),
                capabilityMode: col(cols, idx("capability_mode")),
                skillIDs: skillIDs,
                lead: col(cols, idx("lead")),
                qc: col(cols, idx("qc")),
                routing: col(cols, idx("routing")),
                blurb: col(cols, idx("blurb"))
            )
        }
        return out
    }

    private func col(_ cols: [String], _ i: Int?) -> String {
        guard let i, i < cols.count else { return "" }
        return cols[i]
    }

    private func loadStaffNodes(inTeamDir teamDir: URL, team: String) -> [StaffNode] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: teamDir.path) else {
            return []
        }
        return names
            .filter { $0.hasSuffix(".md") && !$0.hasPrefix(".") }
            .map { fileName -> StaffNode in
                let file = teamDir.appendingPathComponent(fileName)
                let name = (fileName as NSString).deletingPathExtension
                let blurb = (try? String(contentsOf: file, encoding: .utf8)).flatMap { firstBlurb($0) } ?? ""
                return StaffNode(name: name, team: team, blurb: blurb)
            }
            .sorted { $0.name < $1.name }
    }

    private func resolveSkill(id: String, companyRoot: URL) -> SkillRef {
        let skillsRoot = companyRoot.appendingPathComponent("system/skills")
        if let url = findSkillFile(named: id, under: skillsRoot) {
            let title = (try? String(contentsOf: url, encoding: .utf8))
                .flatMap { frontmatter($0, key: "name") } ?? id
            return SkillRef(skillID: id, title: title, path: url)
        }
        return SkillRef(skillID: id, title: id, path: nil)
    }

    private func findSkillFile(named id: String, under root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(atPath: root.path) else { return nil }
        while let rel = enumerator.nextObject() as? String {
            // Match …/<id>/SKILL.md
            let parts = rel.split(separator: "/").map(String.init)
            guard parts.count >= 2,
                  parts[parts.count - 1] == "SKILL.md",
                  parts[parts.count - 2] == id
            else { continue }
            return root.appendingPathComponent(rel)
        }
        // Fallback: any path component == id with SKILL.md deeper — already covered
        return nil
    }

    private func parsePathLimits(staffBody: String, team: String, companyRoot: URL) -> (allowed: [String], denied: [String]) {
        var allowed: [String] = []
        var denied: [String] = []

        // From staff markdown: lines with RW / allow / fence backticks or **RW**
        for line in staffBody.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            let lower = t.lowercased()
            if lower.contains("rw product paths") || lower.contains("allow_rw") || lower.contains("**rw") {
                allowed.append(contentsOf: backtickPaths(in: t))
            }
            if lower.contains("do not") || lower.contains("must not") || lower.contains("deny") {
                denied.append(contentsOf: backtickPaths(in: t))
                if backtickPaths(in: t).isEmpty, t.count > 8, t.hasPrefix("-") || t.hasPrefix("**") {
                    denied.append(t.trimmingCharacters(in: CharacterSet(charactersIn: "-* ")))
                }
            }
            // Standalone fence lines: `projects/...`
            if lower.contains("path fence") { continue }
        }
        // Also collect explicit `projects/…` fences near "RW"
        if allowed.isEmpty {
            for line in staffBody.components(separatedBy: .newlines) {
                let lower = line.lowercased()
                if lower.contains("rw") || lower.contains("only") {
                    allowed.append(contentsOf: backtickPaths(in: line))
                }
            }
        }

        // SCOPE.md team table
        let scopeURL = companyRoot.appendingPathComponent("SCOPE.md")
        if let scope = try? String(contentsOf: scopeURL, encoding: .utf8) {
            for line in scope.components(separatedBy: .newlines) {
                guard line.contains("|"), line.lowercased().contains(team.lowercased()) else { continue }
                let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                // rough: path-like cells
                for cell in cells where cell.contains("/") || cell.contains("`") {
                    let paths = backtickPaths(in: cell)
                    if cell.lowercased().contains("must not") || cells.dropFirst().contains(where: { $0.lowercased().contains("must not") }) {
                        // handled below by column position — keep simple:
                    }
                    if !paths.isEmpty { allowed.append(contentsOf: paths) }
                }
            }
            // allow_rw section bullets
            var inAllow = false
            var inDeny = false
            for line in scope.components(separatedBy: .newlines) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.lowercased().hasPrefix("## allow_rw") { inAllow = true; inDeny = false; continue }
                if t.lowercased().hasPrefix("## deny") || t.lowercased().hasPrefix("## allow_ro") {
                    if t.lowercased().hasPrefix("## deny") { inDeny = true; inAllow = false }
                    else { inAllow = false }
                    continue
                }
                if t.hasPrefix("## ") { inAllow = false; inDeny = false; continue }
                if inAllow, t.hasPrefix("-") {
                    let v = t.trimmingCharacters(in: CharacterSet(charactersIn: "- `"))
                    if !v.isEmpty { allowed.append(v) }
                }
                if inDeny, t.hasPrefix("-") {
                    let v = t.trimmingCharacters(in: CharacterSet(charactersIn: "- `"))
                    if !v.isEmpty { denied.append(v) }
                }
            }
        }

        return (uniquePreserveOrder(allowed), uniquePreserveOrder(denied))
    }

    private func backtickPaths(in text: String) -> [String] {
        var out: [String] = []
        var rest = text[...]
        while let start = rest.firstIndex(of: "`") {
            let after = rest.index(after: start)
            guard let end = rest[after...].firstIndex(of: "`") else { break }
            let token = String(rest[after..<end])
            if token.contains("/") || token.contains("*") || token.contains(".agents") {
                out.append(token)
            }
            rest = rest[rest.index(after: end)...]
        }
        return out
    }

    private func uniquePreserveOrder(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for i in items {
            let t = i.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, seen.insert(t).inserted else { continue }
            out.append(t)
        }
        return out
    }

    private func frontmatter(_ text: String, key: String) -> String? {
        guard text.hasPrefix("---") else { return nil }
        let parts = text.components(separatedBy: "---")
        guard parts.count >= 3 else { return nil }
        for line in parts[1].components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix(key + ":") else { continue }
            return t.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private func stripFrontmatter(_ text: String) -> String {
        guard text.hasPrefix("---") else { return text }
        let parts = text.components(separatedBy: "---")
        guard parts.count >= 3 else { return text }
        return parts.dropFirst(2).joined(separator: "---").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstBlurb(_ text: String) -> String? {
        let body = stripFrontmatter(text)
        for line in body.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { continue }
            return String(t.prefix(160))
        }
        return nil
    }
}

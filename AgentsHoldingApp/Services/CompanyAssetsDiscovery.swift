import Foundation

/// Lists skill markdown files and scripts — company-wide vs per-staff.
struct CompanyAssetsDiscovery {
    private let scriptExtensions: Set<String> = [
        "py", "sh", "bash", "zsh", "rb", "js", "mjs", "ts", "tsx", "swift",
        "kt", "go", "rs", "java", "c", "cpp", "cc", "h", "hpp", "cs",
    ]

    /// Truly company-scoped scripts (install / pack), not role hop libraries.
    func loadCompanyWideScripts(companyRoot: URL) -> [CodeFileRef] {
        let roots = [
            companyRoot.appendingPathComponent("system/install"),
        ]
        var out: [CodeFileRef] = []
        for root in roots {
            out.append(contentsOf: scripts(under: root, companyRoot: companyRoot))
        }
        return unique(out).sorted { $0.label < $1.label }
    }

    /// Company-scoped skills only (rare). Role skills live on staff.
    func loadCompanyWideSkills(companyRoot: URL) -> [CodeFileRef] {
        // Keep empty for now — SKILL.md under customs/defaults are staff/role scoped.
        _ = companyRoot
        return []
    }

    /// Skills belonging to a staff: agents.tsv skill ids + customs/<team>/<staff>/…
    func loadStaffSkills(
        staffName: String,
        team: String,
        companyRoot: URL,
        skillIDs: [String]
    ) -> [CodeFileRef] {
        var out: [CodeFileRef] = []
        let skillsRoot = companyRoot.appendingPathComponent("system/skills")

        // 1) customs/<team>/<staffName>/**/SKILL.md
        let roleCustoms = skillsRoot
            .appendingPathComponent("customs")
            .appendingPathComponent(team)
            .appendingPathComponent(staffName)
        out.append(contentsOf: skillFiles(under: roleCustoms, companyRoot: companyRoot))

        // 2) any customs/**/<staffName>/**/SKILL.md
        let customs = skillsRoot.appendingPathComponent("customs")
        if let enumerator = FileManager.default.enumerator(atPath: customs.path) {
            while let rel = enumerator.nextObject() as? String {
                guard rel.hasSuffix("SKILL.md") else { continue }
                let parts = rel.split(separator: "/").map(String.init)
                // …/<staffName>/<skillId>/SKILL.md or …/<staffName>/SKILL.md
                if parts.contains(staffName) {
                    out.append(.make(url: customs.appendingPathComponent(rel), relativeTo: companyRoot))
                }
            }
        }

        // 3) resolve skill ids from agents.tsv anywhere under skills/
        for id in skillIDs {
            if let url = findSkillFile(named: id, under: skillsRoot) {
                out.append(.make(url: url, relativeTo: companyRoot))
            }
        }

        // ceo also owns defaults/marlin-hop as dispatch tooling (optional attach)
        if staffName == "ceo" {
            let hop = skillsRoot.appendingPathComponent("defaults/marlin-hop/SKILL.md")
            if FileManager.default.fileExists(atPath: hop.path) {
                out.append(.make(url: hop, relativeTo: companyRoot))
            }
        }

        return unique(out).sorted { $0.label < $1.label }
    }

    /// Scripts for a staff: scripts/ under that staff's skill folders; ceo also gets hop scripts.
    func loadStaffScripts(
        staffName: String,
        team: String,
        companyRoot: URL,
        skillFiles: [CodeFileRef]
    ) -> [CodeFileRef] {
        var out: [CodeFileRef] = []
        var roots: [URL] = []

        let roleCustoms = companyRoot
            .appendingPathComponent("system/skills/customs")
            .appendingPathComponent(team)
            .appendingPathComponent(staffName)
        roots.append(roleCustoms)

        for skill in skillFiles {
            roots.append(skill.path.deletingLastPathComponent()) // skill dir
            roots.append(skill.path.deletingLastPathComponent().appendingPathComponent("scripts"))
        }

        if staffName == "ceo" {
            roots.append(
                companyRoot.appendingPathComponent("system/skills/defaults/marlin-hop/scripts")
            )
        }

        for root in roots {
            out.append(contentsOf: scripts(under: root, companyRoot: companyRoot))
        }
        return unique(out).sorted { $0.label < $1.label }
    }

    private func skillFiles(under root: URL, companyRoot: URL) -> [CodeFileRef] {
        guard let enumerator = FileManager.default.enumerator(atPath: root.path) else { return [] }
        var out: [CodeFileRef] = []
        while let rel = enumerator.nextObject() as? String {
            guard rel.hasSuffix("SKILL.md") else { continue }
            out.append(.make(url: root.appendingPathComponent(rel), relativeTo: companyRoot))
        }
        return out
    }

    private func scripts(under root: URL, companyRoot: URL) -> [CodeFileRef] {
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(atPath: root.path)
        else { return [] }
        var out: [CodeFileRef] = []
        while let rel = enumerator.nextObject() as? String {
            if rel.contains("/__pycache__/") { continue }
            let url = root.appendingPathComponent(rel)
            let ext = url.pathExtension.lowercased()
            guard scriptExtensions.contains(ext) else { continue }
            out.append(.make(url: url, relativeTo: companyRoot))
        }
        return out
    }

    private func findSkillFile(named id: String, under root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(atPath: root.path) else { return nil }
        while let rel = enumerator.nextObject() as? String {
            let parts = rel.split(separator: "/").map(String.init)
            guard parts.count >= 2,
                  parts[parts.count - 1] == "SKILL.md",
                  parts[parts.count - 2] == id
            else { continue }
            return root.appendingPathComponent(rel)
        }
        return nil
    }

    private func unique(_ files: [CodeFileRef]) -> [CodeFileRef] {
        var seen = Set<String>()
        var out: [CodeFileRef] = []
        for f in files {
            if seen.insert(f.id).inserted { out.append(f) }
        }
        return out
    }
}

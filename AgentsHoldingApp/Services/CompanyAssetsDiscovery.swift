import Foundation

/// Lists skill markdown files and scripts — company-wide vs per-staff.
///
/// Mirror layout (SoT):
///   system/staffs/<team>/<staff>.md
///   system/skills/customs/<team>/<staff>/<skill-id>/SKILL.md
///
/// Prefer `contentsOfDirectory(atPath:)` — URL-based enumeration returns [] on many `.agents` trees.
struct CompanyAssetsDiscovery {
    private let scriptExtensions: Set<String> = [
        "py", "sh", "bash", "zsh", "rb", "js", "mjs", "ts", "tsx", "swift",
        "kt", "go", "rs", "java", "c", "cpp", "cc", "h", "hpp", "cs",
    ]

    func loadCompanyWideScripts(companyRoot: URL) -> [CodeFileRef] {
        let root = companyRoot.appendingPathComponent("system/install")
        return unique(scripts(under: root, companyRoot: companyRoot)).sorted { $0.label < $1.label }
    }

    func loadCompanyWideSkills(companyRoot: URL) -> [CodeFileRef] {
        _ = companyRoot
        return []
    }

    /// Skills for staff = everything under customs/<team>/<staff>/ (+ tsv skill ids + ceo hop).
    func loadStaffSkills(
        staffName: String,
        team: String,
        companyRoot: URL,
        skillIDs: [String]
    ) -> [CodeFileRef] {
        var out: [CodeFileRef] = []
        let skillsRoot = companyRoot.appendingPathComponent("system/skills")
        let customs = skillsRoot.appendingPathComponent("customs")

        // Primary mirror: customs/<team>/<staffName>/
        let mirrored = customs
            .appendingPathComponent(team)
            .appendingPathComponent(staffName)
        out.append(contentsOf: skillMarkdownFiles(under: mirrored, companyRoot: companyRoot))

        // Fallback: any customs/<any-team>/<staffName>/ (team rename / mis-home)
        if out.isEmpty {
            for teamName in directoryNames(at: customs) {
                let candidate = customs.appendingPathComponent(teamName).appendingPathComponent(staffName)
                out.append(contentsOf: skillMarkdownFiles(under: candidate, companyRoot: companyRoot))
            }
        }

        // agents.tsv skill ids → find SKILL.md named folder
        for id in skillIDs where !id.isEmpty {
            if let url = findSkillFile(named: id, under: skillsRoot) {
                out.append(.make(url: url, relativeTo: companyRoot))
            }
        }

        if staffName == "ceo" {
            let hop = skillsRoot.appendingPathComponent("defaults/marlin-hop/SKILL.md")
            if FileManager.default.fileExists(atPath: hop.path) {
                out.append(.make(url: hop, relativeTo: companyRoot))
            }
        }

        return unique(out).sorted { $0.label < $1.label }
    }

    func loadStaffScripts(
        staffName: String,
        team: String,
        companyRoot: URL,
        skillFiles: [CodeFileRef]
    ) -> [CodeFileRef] {
        var out: [CodeFileRef] = []
        let customs = companyRoot.appendingPathComponent("system/skills/customs")
        let mirrored = customs.appendingPathComponent(team).appendingPathComponent(staffName)
        out.append(contentsOf: scripts(under: mirrored, companyRoot: companyRoot))

        for skill in skillFiles {
            let skillDir = skill.path.deletingLastPathComponent()
            out.append(contentsOf: scripts(under: skillDir, companyRoot: companyRoot))
            out.append(contentsOf: scripts(
                under: skillDir.appendingPathComponent("scripts"),
                companyRoot: companyRoot
            ))
        }

        if staffName == "ceo" {
            out.append(contentsOf: scripts(
                under: companyRoot.appendingPathComponent("system/skills/defaults/marlin-hop/scripts"),
                companyRoot: companyRoot
            ))
        }

        return unique(out).sorted { $0.label < $1.label }
    }

    // MARK: - Walk helpers (atPath only)

    private func directoryNames(at url: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path))?
            .filter { name in
                guard !name.hasPrefix(".") else { return false }
                var isDir: ObjCBool = false
                let child = url.appendingPathComponent(name)
                return FileManager.default.fileExists(atPath: child.path, isDirectory: &isDir) && isDir.boolValue
            } ?? []
    }

    private func skillMarkdownFiles(under root: URL, companyRoot: URL) -> [CodeFileRef] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        var out: [CodeFileRef] = []
        for rel in recursiveRelativePaths(under: root) where rel.hasSuffix("SKILL.md") {
            out.append(.make(url: root.appendingPathComponent(rel), relativeTo: companyRoot))
        }
        return out
    }

    private func scripts(under root: URL, companyRoot: URL) -> [CodeFileRef] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        var out: [CodeFileRef] = []
        for rel in recursiveRelativePaths(under: root) {
            if rel.contains("__pycache__") { continue }
            let url = root.appendingPathComponent(rel)
            let ext = url.pathExtension.lowercased()
            guard scriptExtensions.contains(ext) else { continue }
            out.append(.make(url: url, relativeTo: companyRoot))
        }
        return out
    }

    private func recursiveRelativePaths(under root: URL) -> [String] {
        var results: [String] = []
        func walk(_ dir: URL, prefix: String) {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
            for name in names where !name.hasPrefix(".") {
                let child = dir.appendingPathComponent(name)
                let rel = prefix.isEmpty ? name : "\(prefix)/\(name)"
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue {
                    walk(child, prefix: rel)
                } else {
                    results.append(rel)
                }
            }
        }
        walk(root, prefix: "")
        return results
    }

    private func findSkillFile(named id: String, under root: URL) -> URL? {
        for rel in recursiveRelativePaths(under: root) {
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
        for f in files where seen.insert(f.id).inserted {
            out.append(f)
        }
        return out
    }
}

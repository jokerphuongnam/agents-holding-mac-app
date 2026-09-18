import Foundation

/// Lists skill markdown files and executable/source scripts under a Company OS tree.
struct CompanyAssetsDiscovery {
    private let scriptExtensions: Set<String> = [
        "py", "sh", "bash", "zsh", "rb", "js", "mjs", "ts", "tsx", "swift",
        "kt", "go", "rs", "java", "c", "cpp", "cc", "h", "hpp", "cs",
    ]

    func loadSkills(companyRoot: URL) -> [CodeFileRef] {
        let skillsRoot = companyRoot.appendingPathComponent("system/skills")
        guard let enumerator = FileManager.default.enumerator(atPath: skillsRoot.path) else {
            return []
        }
        var out: [CodeFileRef] = []
        while let rel = enumerator.nextObject() as? String {
            guard rel.hasSuffix("/SKILL.md") || rel == "SKILL.md" || rel.hasSuffix("SKILL.md") else {
                continue
            }
            let url = skillsRoot.appendingPathComponent(rel)
            out.append(.make(url: url, relativeTo: companyRoot))
        }
        return out.sorted { $0.label < $1.label }
    }

    func loadScripts(companyRoot: URL) -> [CodeFileRef] {
        let systemRoot = companyRoot.appendingPathComponent("system")
        guard let enumerator = FileManager.default.enumerator(atPath: systemRoot.path) else {
            return []
        }
        var out: [CodeFileRef] = []
        while let rel = enumerator.nextObject() as? String {
            let url = systemRoot.appendingPathComponent(rel)
            let ext = url.pathExtension.lowercased()
            guard scriptExtensions.contains(ext) else { continue }
            // Skip huge caches if any
            if rel.contains("/__pycache__/") || rel.contains("/.git/") { continue }
            out.append(.make(url: url, relativeTo: companyRoot))
        }
        return out.sorted { $0.label < $1.label }
    }
}

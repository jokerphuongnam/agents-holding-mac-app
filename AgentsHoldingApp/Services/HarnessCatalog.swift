import Foundation

/// Discovers vendor harness ids from `system/harness/*.toml` (not hardcoded).
enum HarnessCatalog {
    private static let excluded = Set([
        "runtime_router.toml",
        "readme.toml",
    ])

    /// Harness runtimes available for a company OS root (e.g. grok, claude, codex, deepseek).
    static func vendorHarnesses(in companyRoot: URL) -> [String] {
        let dir = companyRoot.appendingPathComponent("system/harness")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return []
        }
        return names
            .filter { name in
                let lower = name.lowercased()
                guard lower.hasSuffix(".toml") else { return false }
                if excluded.contains(lower) { return false }
                if lower.hasPrefix(".") { return false }
                return true
            }
            .map { String($0.dropLast(5)) } // strip .toml
            .filter { !$0.isEmpty && $0.lowercased() != "runtime_router" }
            .sorted()
    }

    /// Union of harnesses across several company roots (+ optional holding package).
    static func vendorHarnesses(holdingRoot: URL?, companies: [(slug: String, root: URL)]) -> [String] {
        var set = Set<String>()
        if let holdingRoot {
            let package: URL = {
                let nested = holdingRoot.appendingPathComponent("holding")
                if FileManager.default.fileExists(atPath: nested.appendingPathComponent("system/harness").path) {
                    return nested
                }
                return holdingRoot
            }()
            set.formUnion(vendorHarnesses(in: package))
        }
        for c in companies {
            set.formUnion(vendorHarnesses(in: c.root))
        }
        return set.sorted()
    }

    /// Map a free-form model string onto a known harness id when possible.
    static func bucket(_ raw: String, known: [String]) -> String {
        let m = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if m.isEmpty { return "other" }
        if known.contains(m) { return m }

        // Prefer longest harness id contained in the model string (e.g. deepseek-chat → deepseek).
        let ordered = known.sorted { $0.count > $1.count }
        for h in ordered where m == h || m.contains(h) {
            return h
        }

        // Light aliases when the matching harness is installed.
        if known.contains("claude"),
           m.contains("sonnet") || m.contains("opus") || m.contains("haiku") {
            return "claude"
        }
        if known.contains("codex"),
           m.contains("gpt") || m.hasPrefix("o1") || m.hasPrefix("o3") || m.contains("o1-") || m.contains("o3-") {
            return "codex"
        }
        if known.contains("grok"), m.contains("grok") {
            return "grok"
        }
        return "other"
    }
}

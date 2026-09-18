import Foundation

/// Resolves per-mode model/effort for a staff from `system/harness/*.toml`.
struct HarnessProfileService {
    private let modes = ["grok", "claude", "codex", "merge"]

    func profiles(forStaff name: String, tier: String, companyRoot: URL) -> StaffHarnessProfiles {
        let harnessDir = companyRoot.appendingPathComponent("system/harness")
        let effectiveTier = normalizedTier(tier)
        let router = loadRouter(harnessDir: harnessDir)

        var rows: [HarnessModeProfile] = []
        for mode in modes {
            if mode == "merge" {
                rows.append(mergeProfile(
                    staff: name,
                    tier: effectiveTier,
                    harnessDir: harnessDir,
                    router: router
                ))
            } else {
                let (model, effort) = modelEffort(runtime: mode, tier: effectiveTier, harnessDir: harnessDir)
                rows.append(
                    HarnessModeProfile(
                        mode: mode,
                        runtime: mode,
                        model: model.isEmpty ? "—" : model,
                        effort: effort.isEmpty ? "—" : effort,
                        note: L10n.tr("harness_note_full_vendor")
                    )
                )
            }
        }
        return StaffHarnessProfiles(staffName: name, tier: effectiveTier, modes: rows)
    }

    private func mergeProfile(
        staff: String,
        tier: String,
        harnessDir: URL,
        router: RouterConfig
    ) -> HarnessModeProfile {
        if !router.enabled {
            let fallback = router.defaultRuntime.isEmpty ? "grok" : router.defaultRuntime
            let (model, effort) = modelEffort(runtime: fallback, tier: tier, harnessDir: harnessDir)
            return HarnessModeProfile(
                mode: "merge",
                runtime: fallback,
                model: model.isEmpty ? "—" : model,
                effort: effort.isEmpty ? "—" : effort,
                note: L10n.tr("harness_note_merge_off", fallback)
            )
        }
        let runtime = matchRuntime(staff: staff, router: router)
        let (model, effort) = modelEffort(runtime: runtime, tier: tier, harnessDir: harnessDir)
        return HarnessModeProfile(
            mode: "merge",
            runtime: runtime,
            model: model.isEmpty ? "—" : model,
            effort: effort.isEmpty ? "—" : effort,
            note: L10n.tr("harness_note_merge_on", runtime)
        )
    }

    private func modelEffort(runtime: String, tier: String, harnessDir: URL) -> (String, String) {
        let url = harnessDir.appendingPathComponent("\(runtime).toml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ("", "")
        }
        let model = value(in: text, section: "tier_to_model", key: tier)
            ?? value(in: text, section: "tier_to_model", key: "medium")
            ?? ""
        let effort = value(in: text, section: "tier_to_effort", key: tier)
            ?? value(in: text, section: "tier_to_effort", key: "medium")
            ?? ""
        return (model, effort)
    }

    private func normalizedTier(_ tier: String) -> String {
        let t = tier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = ["dispatch", "low", "medium", "high", "xhigh"]
        return allowed.contains(t) ? t : "medium"
    }

    // MARK: - Minimal TOML helpers

    private struct RouterConfig {
        var enabled: Bool
        var defaultRuntime: String
        var roles: [(pattern: String, runtime: String)]
    }

    private func loadRouter(harnessDir: URL) -> RouterConfig {
        let url = harnessDir.appendingPathComponent("runtime_router.toml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return RouterConfig(enabled: false, defaultRuntime: "grok", roles: [])
        }
        let enabled = boolValue(in: text, key: "enabled") ?? false
        let defaultRuntime = sectionValue(in: text, section: "default", key: "runtime") ?? "grok"
        var roles: [(String, String)] = []
        // [[roles]] blocks: match = "ba-*"; runtime = "claude"
        let blocks = text.components(separatedBy: "[[roles]]")
        for block in blocks.dropFirst() {
            let match = inlineValue(in: block, key: "match") ?? ""
            let runtime = inlineValue(in: block, key: "runtime") ?? ""
            if !match.isEmpty, !runtime.isEmpty {
                roles.append((match, runtime))
            }
        }
        return RouterConfig(enabled: enabled, defaultRuntime: defaultRuntime, roles: roles)
    }

    private func matchRuntime(staff: String, router: RouterConfig) -> String {
        for role in router.roles {
            if globMatch(role.pattern, staff) {
                return role.runtime
            }
        }
        return router.defaultRuntime
    }

    private func globMatch(_ pattern: String, _ value: String) -> Bool {
        // Supports *, prefix*, *suffix, exact
        if pattern == "*" { return true }
        if pattern == value { return true }
        if pattern.hasPrefix("*"), pattern.hasSuffix("*"), pattern.count >= 2 {
            let mid = String(pattern.dropFirst().dropLast())
            return value.contains(mid)
        }
        if pattern.hasPrefix("*") {
            return value.hasSuffix(String(pattern.dropFirst()))
        }
        if pattern.hasSuffix("*") {
            return value.hasPrefix(String(pattern.dropLast()))
        }
        return false
    }

    private func value(in text: String, section: String, key: String) -> String? {
        guard let sectionBody = sectionBody(in: text, section: section) else { return nil }
        return inlineValue(in: sectionBody, key: key)
    }

    private func sectionValue(in text: String, section: String, key: String) -> String? {
        value(in: text, section: section, key: key)
    }

    private func sectionBody(in text: String, section: String) -> String? {
        let marker = "[\(section)]"
        guard let start = text.range(of: marker)?.upperBound else { return nil }
        let rest = text[start...]
        if let next = rest.range(of: "\n[", options: []) {
            return String(rest[..<next.lowerBound])
        }
        return String(rest)
    }

    private func inlineValue(in text: String, key: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.hasPrefix("#"), t.hasPrefix(key) else { continue }
            guard let eq = t.firstIndex(of: "=") else { continue }
            var v = String(t[t.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if let hash = v.firstIndex(of: "#") {
                v = String(v[..<hash]).trimmingCharacters(in: .whitespaces)
            }
            v = v.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !v.isEmpty { return v }
        }
        return nil
    }

    private func boolValue(in text: String, key: String) -> Bool? {
        // top-level key before first [section] or anywhere
        guard let v = inlineValue(in: text, key: key)?.lowercased() else { return nil }
        if v == "true" { return true }
        if v == "false" { return false }
        return nil
    }
}

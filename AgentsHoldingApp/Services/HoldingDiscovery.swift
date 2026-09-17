import Foundation

enum HoldingDiscoveryError: LocalizedError {
    case pathNotFound(String)
    case notAHolding(URL)

    var errorDescription: String? {
        switch self {
        case .pathNotFound(let hint):
            return "Holding path not found. Set AGENTS_HOLDING_PATH or configure in Settings. (\(hint))"
        case .notAHolding(let url):
            return "Path does not look like a holding: \(url.path)"
        }
    }
}

/// Resolves sibling/default holding checkout and loads a light P0 snapshot.
struct HoldingDiscovery {
    /// Prefer env, then UserDefaults, then sibling `../agents-holding` next to this repo.
    func resolveHoldingPath() throws -> URL {
        if let env = ProcessInfo.processInfo.environment["AGENTS_HOLDING_PATH"], !env.isEmpty {
            let url = URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw HoldingDiscoveryError.pathNotFound(env)
            }
            return url.standardizedFileURL
        }

        if let saved = UserDefaults.standard.string(forKey: "holdingPath"), !saved.isEmpty {
            let url = URL(fileURLWithPath: (saved as NSString).expandingTildeInPath)
            if FileManager.default.fileExists(atPath: url.path) {
                return url.standardizedFileURL
            }
        }

        // Repo lives at …/Agents/agents-holding-app → sibling …/Agents/agents-holding
        let sibling = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // AgentsHoldingApp
            .deletingLastPathComponent() // agents-holding-app
            .appendingPathComponent("agents-holding")

        if FileManager.default.fileExists(atPath: sibling.path) {
            return sibling.standardizedFileURL
        }

        let homeFallback = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/Agents/agents-holding")
        if FileManager.default.fileExists(atPath: homeFallback.path) {
            return homeFallback.standardizedFileURL
        }

        throw HoldingDiscoveryError.pathNotFound("sibling agents-holding")
    }

    func loadSnapshot(at holdingRoot: URL) throws -> HoldingSnapshot {
        let holdingCompany = holdingRoot.appendingPathComponent("holding")
        let staffsRoot = holdingCompany.appendingPathComponent("system/staffs")
        let childrenRoot = holdingCompany.appendingPathComponent("children")

        // Accept either `holding/` package layout or root-as-company.
        let root: URL
        if FileManager.default.fileExists(atPath: staffsRoot.path) {
            root = holdingCompany
        } else if FileManager.default.fileExists(atPath: holdingRoot.appendingPathComponent("system/staffs").path) {
            root = holdingRoot
        } else {
            throw HoldingDiscoveryError.notAHolding(holdingRoot)
        }

        let staffs = loadStaffs(under: root.appendingPathComponent("system/staffs"))
        let companies = loadCompanies(under: root.appendingPathComponent("children"))

        return HoldingSnapshot(
            path: holdingRoot,
            name: holdingRoot.lastPathComponent,
            staffs: staffs,
            companies: companies
        )
    }

    private func loadStaffs(under staffsDir: URL) -> [StaffNode] {
        guard let enumerator = FileManager.default.enumerator(
            at: staffsDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var out: [StaffNode] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "md" else { continue }
            let name = fileURL.deletingPathExtension().lastPathComponent
            if name == "ORG" { continue }
            let group = fileURL.deletingLastPathComponent().lastPathComponent
            let blurb = firstBlurb(in: fileURL) ?? ""
            out.append(StaffNode(name: name, blurb: blurb, group: group))
        }
        return out.sorted { $0.name < $1.name }
    }

    private func loadCompanies(under childrenDir: URL) -> [CompanyNode] {
        guard FileManager.default.fileExists(atPath: childrenDir.path) else { return [] }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: childrenDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var out: [CompanyNode] = []
        for url in items {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let slug = url.lastPathComponent
            if slug == "README.md" { continue }
            let pointer = url.appendingPathComponent("COMPANY_POINTER.md")
            let meta = url.appendingPathComponent("META.toml")
            out.append(
                CompanyNode(
                    slug: slug,
                    displayName: slug.replacingOccurrences(of: "-company", with: ""),
                    pointerPath: fm.fileExists(atPath: pointer.path) ? pointer : nil,
                    projectRoot: nil
                )
            )
            _ = meta // P0: parse later for project_root
        }
        return out.sorted { $0.slug < $1.slug }
    }

    private func firstBlurb(in fileURL: URL) -> String? {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("---") || t.hasPrefix("#") || t.hasPrefix("name:") { continue }
            if t.hasPrefix("**") || t.count > 24 {
                return String(t.prefix(140))
            }
        }
        return nil
    }
}

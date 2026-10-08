import Foundation

/// Loads one Company OS tree: child companies, teams, staffs-by-team.
struct CompanyDiscovery {
    private let holdingDiscovery = HoldingDiscovery()
    private let staffDirectory = StaffDirectory()
    private let assets = CompanyAssetsDiscovery()

    func loadCompany(from node: CompanyNode, holdingRoot: URL?) throws -> CompanySnapshot {
        guard let companyPath = resolveCompanyPath(node) else {
            return CompanySnapshot(
                node: node,
                children: [],
                teams: [],
                companyRoot: node.companyPath ?? node.projectRoot ?? URL(fileURLWithPath: "/")
            )
        }

        let children = loadChildren(parentCompanyPath: companyPath)
        let teams = staffDirectory.loadTeams(companyRoot: companyPath)
        let skills = assets.loadCompanyWideSkills(companyRoot: companyPath)
        let scripts = assets.loadCompanyWideScripts(companyRoot: companyPath)

        var enriched = node
        if enriched.companyPath == nil {
            enriched.companyPath = companyPath
        }

        return CompanySnapshot(
            node: enriched,
            children: children,
            teams: teams,
            companyRoot: companyPath,
            skills: skills,
            scripts: scripts
        )
    }

    private func resolveCompanyPath(_ node: CompanyNode) -> URL? {
        if let path = node.companyPath, FileManager.default.fileExists(atPath: path.path) {
            return path
        }
        if let pointer = node.pointerPath {
            let meta = pointer.deletingLastPathComponent().appendingPathComponent("META.toml")
            if let fromMeta = parseCompanyPath(fromMETA: meta),
               FileManager.default.fileExists(atPath: fromMeta.path) {
                return fromMeta
            }
        }
        return nil
    }

    // MARK: - Children

    private func loadChildren(parentCompanyPath: URL) -> [CompanyNode] {
        // Read the children folder in-process. Spawning python3 here makes macOS
        // ask Allow on every company open.
        return loadChildrenFromDisk(parentCompanyPath: parentCompanyPath)
    }

    private func loadChildrenFromDisk(parentCompanyPath: URL) -> [CompanyNode] {
        let childrenDir = parentCompanyPath.appendingPathComponent("children")
        // Prefer atPath — URL-based contentsOfDirectory returns [] on some .agents trees.
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: childrenDir.path) else {
            return []
        }

        var out: [CompanyNode] = []
        for name in names where !name.hasPrefix(".") {
            let url = childrenDir.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            let stem = name
            let meta = url.appendingPathComponent("META.toml")
            let pointer = url.appendingPathComponent("COMPANY_POINTER.md")
            let slug = parseString(fromMETA: meta, key: "slug")
                ?? (stem.hasSuffix("-company") ? stem : "\(stem)-company")
            let projectRoot = parseCompanyPath(fromMETA: meta, key: "project_root")
            let companyPath = parseCompanyPath(fromMETA: meta, key: "company_path")
            let budget = parseString(fromMETA: meta, key: "budget") ?? ""
            out.append(
                CompanyNode(
                    slug: slug,
                    projectRoot: projectRoot,
                    companyPath: companyPath,
                    budget: budget,
                    pointerPath: FileManager.default.fileExists(atPath: pointer.path) ? pointer : meta
                )
            )
        }
        return out
    }

    // MARK: - META / helpers

    private func parseCompanyPath(fromMETA meta: URL, key: String = "company_path") -> URL? {
        guard let raw = parseString(fromMETA: meta, key: key) else { return nil }
        return pathURL(raw)
    }

    private func parseString(fromMETA meta: URL, key: String) -> String? {
        guard let text = try? String(contentsOf: meta, encoding: .utf8) else { return nil }
        let prefix = "\(key)"
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix(prefix) else { continue }
            // key = "value" or key = 'value'
            guard let eq = t.firstIndex(of: "=") else { continue }
            var value = String(t[t.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if let hash = value.firstIndex(of: "#") {
                value = String(value[..<hash]).trimmingCharacters(in: .whitespaces)
            }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty { return value }
        }
        return nil
    }

    private func pathURL(_ raw: String) -> URL? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t != "—" else { return nil }
        return URL(fileURLWithPath: (t as NSString).expandingTildeInPath)
    }
}


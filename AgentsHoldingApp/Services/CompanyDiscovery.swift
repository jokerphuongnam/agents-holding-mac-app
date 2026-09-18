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

        let children = loadChildren(parentCompanyPath: companyPath, holdingRoot: holdingRoot)
        let teams = staffDirectory.loadTeams(companyRoot: companyPath)
        let skills = assets.loadSkills(companyRoot: companyPath)
        let scripts = assets.loadScripts(companyRoot: companyPath)

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

    private func loadChildren(parentCompanyPath: URL, holdingRoot: URL?) -> [CompanyNode] {
        // Under one parent, the same child often appears twice: children_registry row
        // (id=hash) + children/<stem>/META.toml pointer (id=slug|root). Dedupe by
        // company_path, then project_root, then slug — prefer registry.
        let registry = loadChildrenFromRegistry(parentCompanyPath: parentCompanyPath, holdingRoot: holdingRoot)
        let disk = loadChildrenFromDisk(parentCompanyPath: parentCompanyPath)
        return dedupeChildren(registryFirst: registry, disk: disk)
    }

    private func dedupeChildren(registryFirst: [CompanyNode], disk: [CompanyNode]) -> [CompanyNode] {
        var out: [CompanyNode] = []
        var seenPath = Set<String>()
        var seenSlug = Set<String>()

        func absorb(_ child: CompanyNode) {
            let pathKey = (child.companyPath?.path ?? child.projectRoot?.path ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !pathKey.isEmpty {
                if seenPath.contains(pathKey) { return }
                seenPath.insert(pathKey)
                seenSlug.insert(child.slug)
                out.append(child)
                return
            }
            if seenSlug.contains(child.slug) { return }
            seenSlug.insert(child.slug)
            out.append(child)
        }

        for child in registryFirst { absorb(child) }
        for child in disk { absorb(child) }

        return out.sorted {
            if $0.slug != $1.slug { return $0.slug < $1.slug }
            return ($0.projectRoot?.path ?? "") < ($1.projectRoot?.path ?? "")
        }
    }

    private func loadChildrenFromRegistry(parentCompanyPath: URL, holdingRoot: URL?) -> [CompanyNode] {
        guard let script = childrenRegistryScript(holdingRoot: holdingRoot) else { return [] }
        guard let output = runPython(
            script,
            arguments: ["--parent", parentCompanyPath.path, "list"]
        ) else { return [] }
        return parseChildrenListTSV(output)
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

    private func childrenRegistryScript(holdingRoot: URL?) -> URL? {
        let candidates: [URL] = [
            holdingRoot?.appendingPathComponent("holding/system/install/children_registry.py"),
            holdingRoot?.appendingPathComponent("system/install/children_registry.py"),
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Documents/Agents/agents-holding/holding/system/install/children_registry.py"),
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".agents/holding/system/install/children_registry.py"),
        ].compactMap { $0 }

        return candidates.first { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    /// children_registry `list` TSV (always prints cols/row when invoked).
    private func parseChildrenListTSV(_ text: String) -> [CompanyNode] {
        var out: [CompanyNode] = []
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cols.first == "row", cols.count >= 8 else { continue }
            // row id slug status budget placement project_root company_path grants_path
            let id = cols[1]
            let slug = cols[2]
            let status = cols[3]
            let budget = cols[4]
            let projectRoot = cols[6]
            let companyPath = cols[7]
            out.append(
                CompanyNode(
                    id: id,
                    slug: slug,
                    projectRoot: pathURL(projectRoot),
                    companyPath: pathURL(companyPath),
                    status: status,
                    budget: budget
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

    private func runPython(_ script: URL, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script.path] + arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}


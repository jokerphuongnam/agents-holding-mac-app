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
///
/// Companies SoT is **not** `holding/children/` folders.
/// Inventory = `holding/system/install/company_registry.py` →
/// local `holding/cache/companies.sqlite` (same as Python staff tools).
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

        // Installed copy
        let homeAgents = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".agents/holding")
        if FileManager.default.fileExists(atPath: homeAgents.appendingPathComponent("system/staffs").path) {
            return homeAgents.deletingLastPathComponent() // ~/.agents (holding package inside)
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

        // Accept either repo layout `agents-holding/holding/…` or installed `~/.agents/holding/…`
        let root: URL
        if FileManager.default.fileExists(atPath: holdingCompany.appendingPathComponent("system/staffs").path) {
            root = holdingCompany
        } else if FileManager.default.fileExists(atPath: holdingRoot.appendingPathComponent("system/staffs").path) {
            root = holdingRoot
        } else {
            throw HoldingDiscoveryError.notAHolding(holdingRoot)
        }

        let staffs = loadStaffs(under: root.appendingPathComponent("system/staffs"))
        var companies = loadCompaniesFromRegistry(holdingPackage: root)

        // If registry empty, fall back to scan (discover on disk without requiring prior register).
        if companies.isEmpty {
            companies = loadCompaniesFromScan(holdingPackage: root)
        }

        // Merge any on-disk children/ pointers (parent→child template layout), by slug.
        let diskChildren = loadCompaniesFromChildrenDir(root.appendingPathComponent("children"))
        companies = mergeCompanies(companies, diskChildren)

        return HoldingSnapshot(
            path: holdingRoot,
            name: holdingRoot.lastPathComponent,
            staffs: staffs,
            companies: companies
        )
    }

    // MARK: - Staffs

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

    // MARK: - Companies (registry SoT)

    private func companyRegistryScript(holdingPackage: URL) -> URL? {
        let candidate = holdingPackage
            .appendingPathComponent("system/install/company_registry.py")
        return FileManager.default.isReadableFile(atPath: candidate.path) ? candidate : nil
    }

    private func loadCompaniesFromRegistry(holdingPackage: URL) -> [CompanyNode] {
        guard let script = companyRegistryScript(holdingPackage: holdingPackage) else { return [] }
        guard let output = runPython(script, arguments: ["list", "--tsv"]) else { return [] }
        return parseRegistryListTSV(output)
    }

    private func loadCompaniesFromScan(holdingPackage: URL) -> [CompanyNode] {
        guard let script = companyRegistryScript(holdingPackage: holdingPackage) else { return [] }
        // Default scan roots: Language tree + Agents tree (where companies usually live).
        let roots = [
            NSHomeDirectory() + "/Documents/Code/Language",
            NSHomeDirectory() + "/Documents/Agents",
        ]
        var found: [CompanyNode] = []
        var seen = Set<String>()
        for root in roots where FileManager.default.fileExists(atPath: root) {
            guard let output = runPython(
                script,
                arguments: ["scan", "--root", root, "--max-depth", "8"]
            ) else { continue }
            for company in parseScanTSV(output) {
                let key = companyIdentityKey(company)
                if seen.insert(key).inserted {
                    found.append(company)
                }
            }
        }
        return found.sorted {
            if $0.slug != $1.slug { return $0.slug < $1.slug }
            return ($0.projectRoot?.path ?? "") < ($1.projectRoot?.path ?? "")
        }
    }

    private func loadCompaniesFromChildrenDir(_ childrenDir: URL) -> [CompanyNode] {
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
            let pointer = url.appendingPathComponent("COMPANY_POINTER.md")
            out.append(
                CompanyNode(
                    slug: slug,
                    companyPath: url,
                    pointerPath: fm.fileExists(atPath: pointer.path) ? pointer : nil
                )
            )
        }
        return out
    }

    private func mergeCompanies(_ primary: [CompanyNode], _ secondary: [CompanyNode]) -> [CompanyNode] {
        // Slug is NOT unique (same slug, different project_root forks). Key by stable id.
        var byID: [String: CompanyNode] = [:]
        for company in primary + secondary {
            let key = companyIdentityKey(company)
            if byID[key] == nil {
                byID[key] = company
            }
        }
        return byID.values.sorted {
            if $0.slug != $1.slug { return $0.slug < $1.slug }
            return ($0.projectRoot?.path ?? "") < ($1.projectRoot?.path ?? "")
        }
    }

    private func companyIdentityKey(_ company: CompanyNode) -> String {
        if company.id != company.slug { return company.id }
        return "\(company.slug)|\(company.projectRoot?.path ?? company.companyPath?.path ?? "")"
    }

    // MARK: - Python bridge

    private func runPython(_ script: URL, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script.path] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging([
            "COMPANY_REGISTRY_TSV": "1",
        ]) { _, new in new }

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    /// `list --tsv`: cols / row / count lines.
    private func parseRegistryListTSV(_ text: String) -> [CompanyNode] {
        var out: [CompanyNode] = []
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cols.first == "row", cols.count >= 9 else { continue }
            // row id slug project_root company_path status budget topology dup hint
            let id = cols[1]
            let slug = cols[2]
            let projectRoot = cols[3]
            let companyPath = cols[4]
            let status = cols[5]
            let budget = cols[6]
            let topology = cols[7]
            out.append(
                CompanyNode(
                    id: id,
                    slug: slug,
                    projectRoot: pathURL(projectRoot),
                    companyPath: pathURL(companyPath),
                    status: status,
                    budget: budget,
                    topology: topology,
                    pointerPath: pointerIfPresent(companyPath: pathURL(companyPath))
                )
            )
        }
        return out
    }

    /// `scan --tsv`: scan lines.
    private func parseScanTSV(_ text: String) -> [CompanyNode] {
        var out: [CompanyNode] = []
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cols.first == "scan", cols.count >= 4 else { continue }
            // scan slug project_root company_path budget topology in_registry registry_status dup action
            let slug = cols[1]
            let projectRoot = cols[2]
            let companyPath = cols[3]
            let budget = cols.count > 4 ? cols[4] : ""
            let topology = cols.count > 5 ? cols[5] : ""
            let status = cols.count > 7 ? (cols[7].isEmpty ? "active" : cols[7]) : "active"
            out.append(
                CompanyNode(
                    slug: slug,
                    projectRoot: pathURL(projectRoot),
                    companyPath: pathURL(companyPath),
                    status: status,
                    budget: budget,
                    topology: topology,
                    pointerPath: pointerIfPresent(companyPath: pathURL(companyPath))
                )
            )
        }
        return out
    }

    private func pathURL(_ raw: String) -> URL? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t != "—" else { return nil }
        return URL(fileURLWithPath: t)
    }

    private func pointerIfPresent(companyPath: URL?) -> URL? {
        guard let companyPath else { return nil }
        let pointer = companyPath.appendingPathComponent("COMPANY_POINTER.md")
        return FileManager.default.fileExists(atPath: pointer.path) ? pointer : nil
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

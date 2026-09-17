import AppKit
import Foundation

enum CompanyInstallError: LocalizedError {
    case cancelled
    case missingHolding
    case missingScript(URL)
    case invalidName(String)
    case processFailed(Int32, String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Cancelled"
        case .missingHolding:
            return "Holding path not set"
        case .missingScript(let url):
            return "Install script not found: \(url.path)"
        case .invalidName(let name):
            return "Invalid company name: \(name)"
        case .processFailed(let code, let output):
            return "Install failed (\(code)): \(output)"
        }
    }
}

struct CompanyInstallRequest: Equatable {
    var projectRoot: URL
    /// Slug without `-company` suffix, e.g. `desk-garden`.
    var name: String
    var budget: String
    /// If true, only `company_registry.py register` (folder already has Company OS).
    var registerOnly: Bool
    /// Optional roster review JSON applied after create (or onto existing company).
    var rosterSpecJSON: Data?
}

/// Folder picker + create-company.sh / registry register.
struct CompanyInstallService {
    func pickProjectFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Chọn folder project để cài / đăng ký company"
        panel.prompt = "Choose"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Detect existing `.agents/<slug>-company` under project root.
    func existingCompanyDirs(in projectRoot: URL) -> [URL] {
        let agents = projectRoot.appendingPathComponent(".agents")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: agents.path) else {
            return []
        }
        return names
            .filter { $0.hasSuffix("-company") && !$0.hasPrefix(".") }
            .map { agents.appendingPathComponent($0) }
            .filter { url in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            }
    }

    func suggestedName(for projectRoot: URL) -> String {
        let existing = existingCompanyDirs(in: projectRoot)
        if let first = existing.first {
            let slug = first.lastPathComponent
            if slug.hasSuffix("-company") {
                return String(slug.dropLast("-company".count))
            }
            return slug
        }
        return projectRoot.lastPathComponent
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }

    func install(
        _ request: CompanyInstallRequest,
        holdingRoot: URL
    ) throws -> String {
        let name = sanitizeName(request.name)
        guard !name.isEmpty else { throw CompanyInstallError.invalidName(request.name) }

        let holdingPackage = resolveHoldingPackage(holdingRoot)
        let installDir = holdingPackage.appendingPathComponent("system/install")

        let companyPath = request.projectRoot
            .appendingPathComponent(".agents")
            .appendingPathComponent("\(name)-company")

        var log: [String] = []

        if request.registerOnly {
            let script = installDir.appendingPathComponent("company_registry.py")
            guard FileManager.default.isReadableFile(atPath: script.path) else {
                throw CompanyInstallError.missingScript(script)
            }
            var args = [
                "register",
                "--slug", "\(name)-company",
                "--project-root", request.projectRoot.path,
                "--budget", request.budget,
            ]
            if FileManager.default.fileExists(atPath: companyPath.path) {
                args += ["--company-path", companyPath.path]
            }
            log.append(try runPython(script, arguments: args))
        } else {
            let script = installDir.appendingPathComponent("create-company.sh")
            guard FileManager.default.isReadableFile(atPath: script.path) else {
                throw CompanyInstallError.missingScript(script)
            }
            let args = [
                "--name", name,
                "--budget", request.budget,
                "--project-root", request.projectRoot.path,
            ]
            log.append(try runBash(script, arguments: args))
        }

        if let specData = request.rosterSpecJSON {
            let apply = installDir.appendingPathComponent("apply_company_roster.py")
            guard FileManager.default.isReadableFile(atPath: apply.path) else {
                throw CompanyInstallError.missingScript(apply)
            }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("roster-\(UUID().uuidString).json")
            try specData.write(to: tmp)
            defer { try? FileManager.default.removeItem(at: tmp) }
            let agentsHome = holdingPackage.deletingLastPathComponent() // …/agents-holding
            let library = agentsHome.appendingPathComponent("templates/skills-library")
            log.append(
                try runPython(
                    apply,
                    arguments: [
                        "--company-path", companyPath.path,
                        "--spec", tmp.path,
                        "--library", library.path,
                    ]
                )
            )
        }

        return log.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private func sanitizeName(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasSuffix("-company") {
            s = String(s.dropLast("-company".count))
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func resolveHoldingPackage(_ holdingRoot: URL) -> URL {
        let nested = holdingRoot.appendingPathComponent("holding")
        if FileManager.default.fileExists(atPath: nested.appendingPathComponent("system/install").path) {
            return nested
        }
        return holdingRoot
    }

    private func runBash(_ script: URL, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments
        process.currentDirectoryURL = script.deletingLastPathComponent()
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let combined = (stdout + "\n" + stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        if process.terminationStatus != 0 {
            throw CompanyInstallError.processFailed(process.terminationStatus, combined)
        }
        return combined
    }

    private func runPython(_ script: URL, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script.path] + arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let combined = (stdout + "\n" + stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        if process.terminationStatus != 0 {
            throw CompanyInstallError.processFailed(process.terminationStatus, combined)
        }
        return combined
    }
}

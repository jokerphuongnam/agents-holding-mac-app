import Foundation

struct TalkLine: Identifiable, Hashable, Sendable {
    var hash: String
    var author: String
    var date: String
    var thread: String
    var message: String

    var id: String { hash }
}

struct StaffWorkState: Identifiable, Hashable {
    var staff: String
    var state: String
    var message: String

    var id: String { staff }
    var isDone: Bool { state == "done" }
}

enum RoomChatService {
    static func rooms(companyRoot: URL) -> [String] {
        let store = companyRoot.appendingPathComponent("cache/work-history")
        var names = Set<String>()
        let heads = store.appendingPathComponent("refs/heads/room")
        if let enumerator = FileManager.default.enumerator(at: heads, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let url as URL in enumerator {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                      !isDirectory.boolValue else { continue }
                let relative = url.path.replacingOccurrences(of: heads.path + "/", with: "")
                if !relative.isEmpty { names.insert(relative) }
            }
        }
        if let packed = try? String(contentsOf: store.appendingPathComponent("packed-refs"), encoding: .utf8) {
            for line in packed.split(separator: "\n") {
                let text = String(line)
                guard let range = text.range(of: "refs/heads/room/") else { continue }
                let name = String(text[range.upperBound...])
                if !name.isEmpty { names.insert(name) }
            }
        }
        return names.sorted()
    }

    static func talk(companyRoot: URL, room: String) -> [TalkLine] {
        let output = python(companyRoot, ["talk", "--company", companyRoot.path, "--room-name", room]).text
        var lines: [TalkLine] = []
        for block in output.components(separatedBy: "\n---\n") {
            var hash = ""
            var author = ""
            var date = ""
            var thread = "ceo"
            var message = ""
            for raw in block.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = String(raw)
                if line.hasPrefix("hash ") { hash = String(line.dropFirst(5)) }
                else if line.hasPrefix("author ") { author = String(line.dropFirst(7)) }
                else if line.hasPrefix("author-date ") { date = String(line.dropFirst(12)) }
                else if line.hasPrefix("body thread ") { thread = String(line.dropFirst(12)).trimmingCharacters(in: .whitespaces) }
                else if line.hasPrefix("message ") { message = String(line.dropFirst(8)) }
            }
            if !hash.isEmpty {
                lines.append(TalkLine(hash: hash, author: author, date: date, thread: thread.isEmpty ? "ceo" : thread, message: message))
            }
        }
        return lines.reversed()
    }

    static func commits(companyRoot: URL, room: String) -> [TalkLine] {
        let store = companyRoot.appendingPathComponent("cache/work-history")
        let result = run([
            "git", "--git-dir", store.path, "log", "-n", "40",
            "--format=hash %H%nauthor %an%nauthor-date %aI%nmessage %s%n",
            "refs/heads/room/\(room)"
        ])
        var lines: [TalkLine] = []
        for block in result.text.components(separatedBy: "\n\n") {
            var hash = ""
            var author = ""
            var date = ""
            var message = ""
            for raw in block.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = String(raw)
                if line.hasPrefix("hash ") { hash = String(line.dropFirst(5)) }
                else if line.hasPrefix("author ") { author = String(line.dropFirst(7)) }
                else if line.hasPrefix("author-date ") { date = String(line.dropFirst(12)) }
                else if line.hasPrefix("message ") { message = String(line.dropFirst(8)) }
            }
            if !hash.isEmpty {
                lines.append(TalkLine(hash: hash, author: author, date: date, thread: "ceo", message: message))
            }
        }
        return lines.reversed()
    }

    /// A file commit is the user message. Staff who own the changed paths are assumed to have done that work.
    /// Spoken lines with no file change, and staff replies, come from the chat cache.
    static func conversation(companyRoot: URL, room: String) async -> [TalkLine] {
        let root = companyRoot
        let name = room
        return await Task.detached(priority: .userInitiated) {
            await assemble(companyRoot: root, room: name)
        }.value
    }

    private static func assemble(companyRoot: URL, room: String) async -> [TalkLine] {
        let routes = loadRoutes(companyRoot)
        let store = companyRoot.appendingPathComponent("cache/work-history")
        let history = commits(companyRoot: companyRoot, room: room)
        async let spoken = Task.detached { talk(companyRoot: companyRoot, room: room) }.value
        async let cache = Task.detached { cachedChat() }.value
        let attributed = await withTaskGroup(of: [TalkLine].self) { group in
            for commit in history {
                let commit = commit
                group.addTask {
                    var chunk = [TalkLine(hash: commit.hash, author: "user", date: commit.date, thread: "ceo", message: commit.message)]
                    var byStaff: [String: [String]] = [:]
                    for file in changedFiles(store: store, commit: commit.hash) {
                        let staff = routeOwner(file, routes)
                        byStaff[staff, default: []].append(file)
                    }
                    for staff in byStaff.keys.sorted() {
                        let shown = (byStaff[staff] ?? []).prefix(4).joined(separator: ", ")
                        chunk.append(TalkLine(
                            hash: "\(commit.hash)-\(staff)",
                            author: staff,
                            date: commit.date,
                            thread: "ceo",
                            message: shown
                        ))
                    }
                    return chunk
                }
            }
            var gathered: [TalkLine] = []
            for await chunk in group {
                gathered.append(contentsOf: chunk)
            }
            return gathered
        }
        var lines = attributed
        lines.append(contentsOf: await spoken)
        lines.append(contentsOf: await cache)
        return lines.sorted { left, right in
            if left.date != right.date { return left.date < right.date }
            let leftUser = left.author == "user"
            let rightUser = right.author == "user"
            if leftUser != rightUser { return leftUser }
            return left.author < right.author
        }
    }

    private static func changedFiles(store: URL, commit: String) -> [String] {
        let output = run([
            "git", "--git-dir", store.path, "diff-tree", "--no-commit-id", "--name-only", "-r", commit
        ]).text
        return output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private static func loadRoutes(_ companyRoot: URL) -> [(String, String)] {
        let file = companyRoot.appendingPathComponent("system/skills/defaults/marlin-hop/data/route.tsv")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        var routes: [(String, String)] = []
        for line in text.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 2, !cols[0].isEmpty, !cols[1].isEmpty else { continue }
            routes.append((cols[0], cols[1]))
        }
        return routes.sorted { $0.0.count > $1.0.count }
    }

    private static func routeOwner(_ path: String, _ routes: [(String, String)]) -> String {
        for route in routes where path.hasPrefix(route.0) {
            return route.1
        }
        return "ceo"
    }

    private static func cachedChat() -> [TalkLine] {
        let sessions = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".grok/sessions")
        guard let enumerator = FileManager.default.enumerator(at: sessions, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }
        var files: [(URL, Date)] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "chat_history.jsonl" else { continue }
            guard url.path.contains("marlin-language") else { continue }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            files.append((url, date))
        }
        files.sort { $0.1 > $1.1 }
        var lines: [TalkLine] = []
        let formatter = ISO8601DateFormatter()
        for (url, modified) in files.prefix(2) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            var offset = 0
            for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = String(raw).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      object["synthetic_reason"] == nil,
                      let kind = object["type"] as? String,
                      let content = object["content"] as? String else { continue }
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let author: String
                if kind == "user" { author = "user" }
                else if kind == "assistant" { author = "ceo" }
                else { continue }
                let date = formatter.string(from: modified.addingTimeInterval(TimeInterval(offset)))
                lines.append(TalkLine(
                    hash: "\(url.lastPathComponent)-\(offset)",
                    author: author,
                    date: date,
                    thread: "ceo",
                    message: String(trimmed.prefix(600))
                ))
                offset += 1
                if offset > 80 { break }
            }
        }
        return lines
    }

    static func states(companyRoot: URL, room: String) -> [StaffWorkState] {
        let store = companyRoot.appendingPathComponent("cache/work-history")
        let output = run(["git", "--git-dir", store.path, "show", "status/\(room):status.tsv"]).text
        return output.split(separator: "\n").compactMap { raw in
            let parts = raw.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3 else { return nil }
            return StaffWorkState(staff: parts[0], state: parts[1], message: parts[2])
        }
    }

    static func say(companyRoot: URL, room: String, who: String, message: String, thread: String) throws {
        let output = python(companyRoot, [
            "say", "--company", companyRoot.path, "--room-name", room,
            "--who", who, "--message", message, "--thread", thread
        ]).text
        if !output.contains("talk ") {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    /// Copies project branches into the company store, then points a room at each one.
    static func mirror(companyRoot: URL, source: URL) -> String? {
        let script = mirrorScript(companyRoot: companyRoot)
        let result = run(["python3", script, "mirror", "--company", companyRoot.path, "--source", source.path])
        if result.code != 0 || !result.text.contains("mirror ") {
            return result.text.isEmpty ? "mirror failed" : result.text
        }
        if result.text.contains("mirror none") {
            return "mirror none"
        }
        publishRooms(companyRoot: companyRoot)
        return nil
    }

    private static func mirrorScript(companyRoot: URL) -> String {
        let holding = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/Agents/agents-holding/holding/system/install/work_history.py")
        if FileManager.default.fileExists(atPath: holding.path) {
            return holding.path
        }
        return companyRoot.appendingPathComponent("system/install/work_history.py").path
    }

    private static func publishRooms(companyRoot: URL) {
        let store = companyRoot.appendingPathComponent("cache/work-history").path
        let listed = run(["git", "--git-dir", store, "for-each-ref", "--format=%(refname:short) %(objectname)", "refs/heads/mirror"])
        for raw in listed.text.split(separator: "\n") {
            let parts = raw.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0].hasPrefix("mirror/") else { continue }
            let room = "room/" + parts[0].dropFirst("mirror/".count)
            let exists = run(["git", "--git-dir", store, "show-ref", "--verify", "--quiet", "refs/heads/\(room)"])
            if exists.code != 0 {
                _ = run(["git", "--git-dir", store, "branch", room, parts[1]])
            }
        }
    }

    private static func python(_ companyRoot: URL, _ args: [String]) -> (text: String, code: Int32) {
        let script = companyRoot.appendingPathComponent("system/install/work_history.py")
        return run(["python3", script.path] + args)
    }

    private static func run(_ command: [String]) -> (text: String, code: Int32) {
        let process = Process()
        let executable = command[0] == "git" ? "/usr/bin/git" : command[0] == "python3" ? "/usr/bin/python3" : command[0]
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(command.dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ("", 1)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "", process.terminationStatus)
    }
}

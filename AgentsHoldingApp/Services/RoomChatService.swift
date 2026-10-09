import Foundation

struct RoomChatError: LocalizedError {
    var text: String
    var errorDescription: String? { text }
}

struct TalkStep: Hashable, Sendable, Identifiable {
    var kind: String
    var detail: String

    var id: String { kind + "\t" + detail }
}

struct TalkLine: Identifiable, Hashable, Sendable {
    var hash: String
    var author: String
    var date: String
    var thread: String
    var message: String
    var steps: [TalkStep]

    var id: String { hash }

    init(hash: String, author: String, date: String, thread: String, message: String, steps: [TalkStep] = []) {
        self.hash = hash
        self.author = author
        self.date = date
        self.thread = thread
        self.message = message
        self.steps = steps
    }
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

    /// A file commit is the user message. Progress lines in a turn are dropped; one closing line remains.
    static func conversation(companyRoot: URL, room: String) async -> [TalkLine] {
        let root = companyRoot
        let name = room
        return await Task.detached(priority: .userInitiated) {
            await assemble(companyRoot: root, room: name)
        }.value
    }

    private static func assemble(companyRoot: URL, room: String) async -> [TalkLine] {
        let history = commits(companyRoot: companyRoot, room: room)
        async let spoken = Task.detached { talk(companyRoot: companyRoot, room: room) }.value
        async let cache = Task.detached { cachedChat() }.value
        let attributed = await withTaskGroup(of: [TalkLine].self) { group in
            for commit in history {
                let commit = commit
                group.addTask {
                    [TalkLine(hash: commit.hash, author: "user", date: commit.date, thread: "ceo", message: commit.message)]
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
            var spoken: [(String, String, [TalkStep])] = []
            var closing = ""
            var steps: [TalkStep] = []
            func note(_ step: TalkStep) {
                if steps.last == step { return }
                steps.append(step)
                if steps.count > 12 { steps.removeFirst(steps.count - 12) }
            }
            func keepClosing() {
                let text = closing.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty || !steps.isEmpty {
                    spoken.append(("ceo", text, steps))
                }
                closing = ""
                steps = []
            }
            for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = String(raw).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      object["synthetic_reason"] == nil,
                      let kind = object["type"] as? String else { continue }
                if kind == "reasoning" {
                    note(TalkStep(kind: "thinking", detail: ""))
                    continue
                }
                let trimmed = Self.visibleChat(Self.plainContent(object["content"]))
                if kind == "user" {
                    keepClosing()
                    guard !trimmed.isEmpty else { continue }
                    spoken.append(("user", trimmed, []))
                } else if kind == "assistant" {
                    if !trimmed.isEmpty { closing = trimmed }
                    for step in Self.activity(object["tool_calls"]) {
                        note(step)
                    }
                }
            }
            keepClosing()
            let recent = spoken.suffix(80)
            for (offset, item) in recent.enumerated() {
                let date = formatter.string(from: modified.addingTimeInterval(TimeInterval(offset)))
                lines.append(TalkLine(
                    hash: "\(url.deletingLastPathComponent().lastPathComponent)-\(offset)",
                    author: item.0,
                    date: date,
                    thread: "ceo",
                    message: String(item.1.prefix(600)),
                    steps: item.2
                ))
            }
        }
        return lines
    }

    /// Tool calls become short activity rows: thinking, writing an edit, reading, searching, running.
    private static func activity(_ value: Any?) -> [TalkStep] {
        guard let calls = value as? [[String: Any]] else { return [] }
        return calls.compactMap { call in
            guard let name = call["name"] as? String else { return nil }
            let arguments = call["arguments"] as? String ?? ""
            let fields = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any]
            let path = (fields?["path"] as? String) ?? (fields?["file_path"] as? String) ?? (fields?["target_file"] as? String) ?? ""
            let file = path.isEmpty ? "" : URL(fileURLWithPath: path).lastPathComponent
            switch name {
            case "search_replace", "write":
                return TalkStep(kind: "edit", detail: file)
            case "read_file":
                return TalkStep(kind: "read", detail: file)
            case "grep", "search_tool":
                return TalkStep(kind: "search", detail: file)
            case "run_terminal_command":
                let command = ((fields?["command"] as? String) ?? "").split(separator: "\n").first.map(String.init) ?? ""
                return TalkStep(kind: "run", detail: String(command.prefix(80)))
            default:
                return TalkStep(kind: "tool", detail: name)
            }
        }
    }

    /// User rows store content as text blocks. Assistant rows store a string.
    private static func plainContent(_ value: Any?) -> String {
        if let text = value as? String { return text }
        guard let blocks = value as? [[String: Any]] else { return "" }
        return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    /// Cache rows wrap the typed message and also carry reminders. Show only the typed message.
    private static func visibleChat(_ raw: String) -> String {
        if let start = raw.range(of: "<user_query>"), let end = raw.range(of: "</user_query>"), start.upperBound <= end.lowerBound {
            return String(raw[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("<system-reminder>") || trimmed.contains("<user_info>") { return "" }
        return trimmed
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
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw RoomChatError(text: detail.isEmpty ? "send failed" : detail)
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
        run(["python3", mirrorScript(companyRoot: companyRoot)] + args)
    }

    private final class TextBox: @unchecked Sendable {
        var text = ""
    }

    private static func run(_ command: [String]) -> (text: String, code: Int32) {
        let process = Process()
        let executable = command[0] == "git" ? "/usr/bin/git" : command[0] == "python3" ? "/usr/bin/python3" : command[0]
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(command.dropFirst())
        let pipe = Pipe()
        let err = Pipe()
        process.standardOutput = pipe
        process.standardError = err
        let outBox = TextBox()
        let errBox = TextBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outBox.text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errBox.text = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            group.leave()
        }
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (error.localizedDescription, 1)
        }
        group.wait()
        return (outBox.text + errBox.text, process.terminationStatus)
    }
}

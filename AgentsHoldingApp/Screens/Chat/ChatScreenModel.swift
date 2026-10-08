import Foundation

enum ChatScreenAction {
    case reload
    case selectRoom(String)
    case chooseThread(String)
    case send
    case mirror
}

@MainActor
final class ChatScreenModel: ActionScreenModel<ChatScreenAction>, ViewModel {
    var companyRoot: URL?
    var projectRoot: URL?
    var mirroring = false
    var rooms: [String] = []
    var room: String?
    var lines: [TalkLine] = []
    var states: [StaffWorkState] = []
    var thread = "ceo"
    var draft = ""
    var failure: String?

    var threads: [String] {
        var names = ["ceo"]
        for line in lines where !names.contains(line.thread) {
            names.append(line.thread)
        }
        return names
    }

    var mirrorSource: URL? {
        if let projectRoot { return projectRoot }
        guard let companyRoot else { return nil }
        let parent = companyRoot.deletingLastPathComponent()
        guard parent.lastPathComponent == ".agents" else { return nil }
        return parent.deletingLastPathComponent()
    }

    var roundIsOpen: Bool {
        !states.isEmpty && states.contains { !$0.isDone }
    }

    func observable(action: ChatScreenAction) -> () -> Void {
        guard let companyRoot else { return {} }
        switch action {
        case .reload:
            rooms = RoomChatService.rooms(companyRoot: companyRoot)
            loadRoom()
        case .selectRoom(let name):
            open(name)
        case .chooseThread(let name):
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { thread = trimmed }
        case .mirror:
            guard let source = mirrorSource, !mirroring else { return {} }
            mirroring = true
            failure = nil
            let company = companyRoot
            Task { @MainActor in
                let problem = await Task.detached(priority: .userInitiated) {
                    RoomChatService.mirror(companyRoot: company, source: source)
                }.value
                self.mirroring = false
                self.failure = problem
                self.rooms = RoomChatService.rooms(companyRoot: company)
            }
            return {}
        case .send:
            guard let room, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return {} }
            do {
                try RoomChatService.say(
                    companyRoot: companyRoot,
                    room: room,
                    who: "user",
                    message: draft.trimmingCharacters(in: .whitespacesAndNewlines),
                    thread: thread
                )
                draft = ""
                failure = nil
                loadRoom()
            } catch {
                failure = error.localizedDescription
            }
        }
        return {}
    }

    func open(_ name: String) {
        room = name
        thread = "ceo"
        loadRoom()
    }

    private func loadRoom() {
        guard let companyRoot, let room else {
            lines = []
            states = []
            return
        }
        let spoken = RoomChatService.talk(companyRoot: companyRoot, room: room)
        let done = RoomChatService.commits(companyRoot: companyRoot, room: room)
        lines = (spoken + done).sorted { $0.date < $1.date }
        states = RoomChatService.states(companyRoot: companyRoot, room: room)
    }
}

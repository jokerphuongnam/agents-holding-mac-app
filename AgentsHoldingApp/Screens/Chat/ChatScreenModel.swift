import ScreenViewModel
import Foundation

enum ChatScreenAction {
    case reload
    case selectRoom(String)
    case chooseThread(String)
    case send
    case mirror
    case mirrorFinished(String?)
    case openFresh(message: String, project: URL)
    case freshOpened(String)
    case freshFailed(message: String, error: String)
    case wakeFailed(String)
    case sent
}

@MainActor
final class ChatScreenModel: ActionScreenModel<ChatScreenAction> {
    var companyRoot: URL?
    var projectRoot: URL?
    var mirroring = false
    var rooms: [String] = []
    var room: String?
    var lines: [TalkLine] = []
    var states: [StaffWorkState] = []
    var thread = "ceo"
    var draft = ""
    var opening = false
    var openedRoom: String?
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

    override func observable(action: ChatScreenAction, cancel _: Cancel) -> Effect<ChatScreenAction> {
        guard let companyRoot else { return .none }
        switch action {
        case .reload:
            rooms = RoomChatService.rooms(companyRoot: companyRoot)
            loadRoom()
        case .selectRoom(let name):
            open(name)
            guard let projectRoot else { return .none }
            let company = companyRoot
            let project = projectRoot
            return .task(.utility, id: "resume-\(name)") { send in
                do {
                    try RoomChatService.resumeRoom(companyRoot: company, projectRoot: project, room: name, message: nil)
                } catch {
                    send(.wakeFailed(error.localizedDescription))
                }
            }
        case .chooseThread(let name):
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { thread = trimmed }
        case .mirror:
            guard let source = mirrorSource, !mirroring else { return .none }
            mirroring = true
            failure = nil
            let company = companyRoot
            return .task(.userInitiated) { send in
                let problem = await Task.detached(priority: .userInitiated) {
                    RoomChatService.mirror(companyRoot: company, source: source)
                }.value
                send(.mirrorFinished(problem))
            }
        case .mirrorFinished(let problem):
            mirroring = false
            failure = problem
            rooms = RoomChatService.rooms(companyRoot: companyRoot)
            return .none
        case .openFresh(let message, let project):
            let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !opening else { return .none }
            opening = true
            failure = nil
            draft = ""
            let company = companyRoot
            return .task(.userInitiated) { send in
                let result: Result<String, Error> = await Task.detached(priority: .userInitiated) {
                    do {
                        return .success(try RoomChatService.startRoom(companyRoot: company, projectRoot: project, message: text))
                    } catch {
                        return .failure(error)
                    }
                }.value
                switch result {
                case .success(let name):
                    send(.freshOpened(name))
                case .failure(let error):
                    send(.freshFailed(message: text, error: error.localizedDescription))
                }
            }
        case .freshOpened(let name):
            opening = false
            rooms = RoomChatService.rooms(companyRoot: companyRoot)
            openedRoom = name
            return .none
        case .freshFailed(let message, let error):
            opening = false
            draft = message
            failure = error
            return .none
        case .send:
            let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let room, let projectRoot, !text.isEmpty, !opening else { return .none }
            opening = true
            failure = nil
            draft = ""
            let company = companyRoot
            let project = projectRoot
            let name = room
            return .task(.userInitiated, id: "send-\(name)") { send in
                do {
                    try RoomChatService.resumeRoom(companyRoot: company, projectRoot: project, room: name, message: text)
                    send(.sent)
                } catch {
                    send(.freshFailed(message: text, error: error.localizedDescription))
                }
            }
        case .sent:
            opening = false
            failure = nil
            loadRoom()
            return .none
        case .wakeFailed(let error):
            failure = error
            return .none
        }
        return .none
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

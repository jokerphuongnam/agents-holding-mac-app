import SwiftUI

struct ChatWindowTarget: Codable, Hashable {
    var companyRoot: String
    var projectRoot: String?
}

private func chatClock(_ raw: String) -> String {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var parsed = iso.date(from: raw)
    if parsed == nil {
        iso.formatOptions = [.withInternetDateTime]
        parsed = iso.date(from: raw)
    }
    guard let parsed else { return raw }
    let clock = DateFormatter()
    clock.locale = Locale(identifier: "en_US_POSIX")
    clock.dateFormat = "HH:mm dd/MM/yyyy"
    return clock.string(from: parsed)
}

private struct ChatCluster: Identifiable {
    let id: String
    let author: String
    let stamp: String
    var lines: [TalkLine]
}

private struct RoomCommitList: View {
    let companyRoot: URL
    let room: String
    @State private var lines: [TalkLine] = []
    @State private var loading = true
    @State private var draft = ""
    @State private var queue: [Outbound] = []
    @State private var inflight: Outbound?
    @State private var sendError: String?
    @State private var loadToken = 0

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(clusters) { cluster in
                    let fromUser = cluster.author == "user"
                    HStack(alignment: .top) {
                        if fromUser { Spacer(minLength: 48) }
                        VStack(alignment: fromUser ? .trailing : .leading, spacing: 6) {
                            if !fromUser {
                                Text(cluster.author)
                                    .font(.headline)
                                Divider()
                                    .frame(width: 160)
                            }
                            ForEach(cluster.lines) { line in
                                VStack(alignment: fromUser ? .trailing : .leading, spacing: 4) {
                                    if !line.steps.isEmpty {
                                        VStack(alignment: .leading, spacing: 3) {
                                            ForEach(Array(line.steps.enumerated()), id: \.offset) { _, step in
                                                HStack(spacing: 6) {
                                                    Image(systemName: phaseSymbol(step.kind))
                                                    Text(phaseTitle(step.kind))
                                                    if !step.detail.isEmpty {
                                                        Text(step.detail)
                                                            .foregroundStyle(.secondary)
                                                            .lineLimit(1)
                                                    }
                                                }
                                                .font(.caption)
                                            }
                                        }
                                        .padding(.bottom, 4)
                                    }
                                    if !line.message.isEmpty {
                                    Text(line.message)
                                        .multilineTextAlignment(fromUser ? .trailing : .leading)
                                    Text(chatClock(line.date))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(12)
                                .background(
                                    fromUser ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .id(line.id)
                            }
                        }
                        if !fromUser { Spacer(minLength: 48) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
        }
        .defaultScrollAnchor(.bottom)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composer
        }
        .onChange(of: lines.last?.id) { _, id in
            guard let id else { return }
            proxy.scrollTo(id, anchor: .bottom)
        }
        }
        .navigationTitle(room)
        .overlay {
            if loading {
                ProgressView()
            }
        }
        .task(id: room) {
            loading = true
            let token = loadToken
            let root = companyRoot
            let name = room
            let loaded = await RoomChatService.conversation(companyRoot: root, room: name)
            guard !Task.isCancelled, token == loadToken else { return }
            lines = loaded
            loading = false
        }
    }

    private func phaseSymbol(_ kind: String) -> String {
        switch kind {
        case "thinking": return "brain"
        case "edit": return "pencil"
        case "read": return "doc.text"
        case "search": return "magnifyingglass"
        case "run": return "terminal"
        default: return "circle"
        }
    }

    private func phaseTitle(_ kind: String) -> String {
        switch kind {
        case "thinking": return L10nLookup("chat_phase_thinking", "Localizable", "Thinking")
        case "edit": return L10nLookup("chat_phase_edit", "Localizable", "Writing edit")
        case "read": return L10nLookup("chat_phase_read", "Localizable", "Reading")
        case "search": return L10nLookup("chat_phase_search", "Localizable", "Searching")
        case "run": return L10nLookup("chat_phase_run", "Localizable", "Running")
        default: return kind
        }
    }

    private var clusters: [ChatCluster] {
        var grouped: [ChatCluster] = []
        for line in lines {
            let stamp = chatClock(line.date)
            if let last = grouped.last, last.author == line.author, last.stamp == stamp {
                grouped[grouped.count - 1].lines.append(line)
            } else {
                grouped.append(ChatCluster(id: line.id, author: line.author, stamp: stamp, lines: [line]))
            }
        }
        return grouped
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let inflight {
                queueRow(inflight, waiting: false, index: nil)
            }
            ForEach(Array(queue.enumerated()), id: \.element.id) { index, item in
                queueRow(item, waiting: true, index: index)
            }
            if let sendError {
                Text(sendError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack(spacing: 8) {
                TextField(L10nLookup("chat_placeholder", "Localizable", "Message"), text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(enqueue)
                Button(L10nLookup("chat_send", "Localizable", "Send"), action: enqueue)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        colors: [.clear, .black, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func queueRow(_ item: Outbound, waiting: Bool, index: Int?) -> some View {
        HStack(spacing: 6) {
            if waiting {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            Text(item.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if waiting, let index {
                Button { moveQueue(index, by: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled(index == 0)
                Button { moveQueue(index, by: 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(index == queue.count - 1)
                Button { queue.remove(at: index) } label: { Image(systemName: "trash") }
                Button(L10nLookup("chat_send_now", "Localizable", "Send now")) { sendNow(index) }
            }
        }
        .font(.callout)
    }

    private func enqueue() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        sendError = nil
        queue.append(Outbound(id: UUID(), text: text))
        pump()
    }

    private func moveQueue(_ index: Int, by offset: Int) {
        let target = index + offset
        guard queue.indices.contains(target) else { return }
        queue.swapAt(index, target)
    }

    private func sendNow(_ index: Int) {
        guard queue.indices.contains(index) else { return }
        let item = queue.remove(at: index)
        Task {
            let failed = await post(item)
            if failed { queue.insert(item, at: 0) }
        }
    }

    private func pump() {
        guard inflight == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        inflight = next
        let root = companyRoot
        let name = room
        Task {
            let failed = await post(next, root: root, name: name)
            inflight = nil
            if failed {
                queue.insert(next, at: 0)
            } else {
                pump()
            }
        }
    }

    @discardableResult
    private func post(_ item: Outbound, root: URL? = nil, name: String? = nil) async -> Bool {
        let root = root ?? companyRoot
        let name = name ?? room
        loadToken += 1
        let stamp = ISO8601DateFormatter().string(from: Date())
        let local = TalkLine(hash: item.id.uuidString, author: "user", date: stamp, thread: "ceo", message: item.text)
        if !lines.contains(where: { $0.hash == local.hash }) {
            lines.append(local)
        }
        let failure: String? = await Task.detached {
            do {
                try RoomChatService.say(companyRoot: root, room: name, who: "user", message: item.text, thread: "ceo")
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        if let failure {
            sendError = failure
            return true
        }
        sendError = nil
        return false
    }
}

private struct Outbound: Identifiable, Equatable {
    let id: UUID
    var text: String
}

struct CompanyChatView: View {
    let companyRoot: URL
    let projectRoot: URL?
    @State private var model = ChatScreenModel()

    var body: some View {
        NavigationStack {
            Group {
                if roomNames.isEmpty {
                    ContentUnavailableView(
                        L10nLookup("chat_rooms", "Localizable", "Rooms"),
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text(L10nLookup("chat_empty", "Localizable", "No rooms yet. Launch this company once to create a room."))
                    )
                } else {
                    List(roomNames, id: \.self) { name in
                        NavigationLink(value: name) {
                            Text(name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                }
            }
            .navigationTitle(L10nLookup("chat_rooms", "Localizable", "Rooms"))
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        model.send(.mirror)
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .help(L10nLookup("chat_mirror", "Localizable", "Mirror git into company history"))
                    .disabled(model.mirrorSource == nil || model.mirroring)
                }
            }
            .navigationDestination(for: String.self) { name in
                RoomCommitList(companyRoot: companyRoot, room: name)
                    .onAppear {
                        model.companyRoot = companyRoot
                        model.projectRoot = projectRoot
                        model.open(name)
                    }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear {
            model.companyRoot = companyRoot
            model.projectRoot = projectRoot
            model.rooms = roomNames
            model.send(.reload)
        }
    }

    private var roomNames: [String] {
        RoomChatService.rooms(companyRoot: companyRoot)
    }

    private var roomTranscript: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.roundIsOpen {
                workingRow
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(model.threads, id: \.self) { thread in
                        threadBox(thread)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            composer
            if let failure = model.failure {
                Text(failure).foregroundStyle(.red).font(.callout)
            }
        }
        .padding(16)
        .navigationTitle(model.room ?? L10nLookup("chat_title", "Localizable", "Chat"))
    }

    private var workingRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10nLookup("chat_working", "Localizable", "Working")).font(.headline)
            ScrollView(.horizontal) {
                HStack {
                    ForEach(model.states) { item in
                        VStack(alignment: .leading) {
                            Text(item.staff).font(.headline)
                            Text(item.state)
                            Text(item.message).font(.caption)
                        }
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func threadBox(_ thread: String) -> some View {
        let spoken = model.lines.filter { $0.thread == thread }
        let title = thread == "ceo" ? L10nLookup("chat_ceo", "Localizable", "CEO") : thread
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ForEach(spoken) { line in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(line.author)  \(line.date)").font(.caption).foregroundStyle(.secondary)
                    Text(line.message)
                    if thread == "ceo", line.author == "user", line.id == spoken.last(where: { $0.author == "user" })?.id, !model.roundIsOpen, !model.states.isEmpty {
                        recap
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(line.author == "user" ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator))
    }

    private var recap: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10nLookup("chat_recap", "Localizable", "Recap")).font(.subheadline.weight(.semibold))
            ScrollView(.horizontal) {
                HStack {
                    ForEach(model.states) { item in
                        Text(item.staff)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
        }
    }

    private var composer: some View {
        HStack {
            TextField(L10nLookup("chat_placeholder", "Localizable", "Message"), text: Binding(
                get: { model.draft },
                set: { model.draft = $0 }
            ))
            .onSubmit { model.send(.send) }
            Button(L10nLookup("chat_send", "Localizable", "Send")) {
                model.send(.send)
            }
            .disabled(model.room == nil || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

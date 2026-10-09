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
    @State private var loadToken = 0

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .defaultScrollAnchor(.bottom)
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
            let root = companyRoot
            let name = room
            while !Task.isCancelled {
                let loaded = await RoomChatService.conversation(companyRoot: root, room: name)
                if Task.isCancelled { return }
                lines = loaded
                loading = false
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
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

}

struct CompanyChatView: View {
    let companyRoot: URL
    let projectRoot: URL?
    @State private var model = ChatScreenModel()
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.rooms.isEmpty {
                    ContentUnavailableView(
                        L10nLookup("chat_rooms", "Localizable", "Rooms"),
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text(L10nLookup("chat_empty", "Localizable", "No rooms yet. Send a message to open a new one."))
                    )
                } else {
                    List(model.rooms, id: \.self) { name in
                        NavigationLink(value: name) {
                            Text(name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                    .contentMargins(.bottom, 72, for: .scrollContent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                roomComposer
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
            model.send(.reload)
        }
        .onChange(of: model.openedRoom) { _, name in
            guard let name else { return }
            path.append(name)
            model.openedRoom = nil
        }
}

    private var roomComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.opening {
                ProgressView()
                    .controlSize(.small)
            }
            if let openError = model.failure {
                Text(openError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack(spacing: 8) {
                TextField(L10nLookup("chat_placeholder", "Localizable", "Message"), text: $model.draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(openFreshRoom)
                Button(L10nLookup("chat_send", "Localizable", "Send"), action: openFreshRoom)
                    .disabled(model.opening || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || projectRoot == nil)
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

    private func openFreshRoom() {
        guard let projectRoot else { return }
        model.projectRoot = projectRoot
        model.send(.openFresh(message: model.draft, project: projectRoot))
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

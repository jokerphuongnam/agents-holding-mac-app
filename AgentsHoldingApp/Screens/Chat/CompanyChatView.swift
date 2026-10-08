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

private struct RoomCommitList: View {
    let companyRoot: URL
    let room: String
    @State private var lines: [TalkLine] = []
    @State private var loading = true

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(lines) { line in
                    let fromUser = line.author == "user"
                    HStack {
                        if fromUser { Spacer(minLength: 48) }
                        VStack(alignment: fromUser ? .trailing : .leading, spacing: 4) {
                            Text(line.author)
                                .font(.headline)
                            Text(line.message)
                                .multilineTextAlignment(fromUser ? .trailing : .leading)
                            Text(chatClock(line.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(
                            fromUser ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        if !fromUser { Spacer(minLength: 48) }
                    }
                    .id(line.id)
                }
            }
            .padding(16)
        }
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
            loading = true
            let root = companyRoot
            let name = room
            let loaded = await RoomChatService.conversation(companyRoot: root, room: name)
            guard !Task.isCancelled else { return }
            lines = loaded
            loading = false
        }
    }
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

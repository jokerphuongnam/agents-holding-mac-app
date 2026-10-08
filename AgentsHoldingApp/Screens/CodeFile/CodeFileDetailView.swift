import AppKit
import MarkdownUI
import SwiftUI

/// Opens a plan or script for editing.
struct CodeFileDetailView: View {
    @Environment(AppModel.self) private var appModel
    @State private var model = CodeFileScreenModel()

    var body: some View {
        let _ = model.attach(appModel)
        Group {
            if let file = appModel.openCodeFile {
                EditableTextFileView(
                    url: file.path,
                    title: file.fileName,
                    subtitle: file.label,
                    badge: file.languageHint,
                    onBack: { model.send(.back) }
                )
            } else {
                ContentUnavailableView(L10n.fileNotFound, systemImage: "doc.questionmark")
            }
        }
    }
}

/// Read a company file, edit it, and write it back in place.
struct EditableTextFileView: View {
    let url: URL
    let title: String
    var subtitle: String = ""
    var badge: String = ""
    /// Staff page already has its own back button and scroll view.
    var embedded: Bool = false
    let onBack: () -> Void

    @State private var text = ""
    @State private var savedText = ""
    @State private var loaded = false
    @State private var missing = false
    @State private var editing = false
    @State private var status = ""
    /// Each entry is one replacement. Undo puts `removed` back. Redo puts `inserted` back.
    @State private var undoStack: [TextEdit] = []
    @State private var redoStack: [TextEdit] = []
    @State private var scrollIndex = 0
    @State private var scrollToken = 0

    private var dirty: Bool { loaded && text != savedText }
    private var isMarkdown: Bool { url.pathExtension.lowercased() == "md" }

    var body: some View {
        Group {
            if missing {
                ContentUnavailableView(L10n.fileNotFound, systemImage: "doc.questionmark")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    HStack(spacing: 8) {
                        if !badge.isEmpty {
                            Text(badge)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }
                        Text(subtitle.isEmpty ? url.path : subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Spacer()
                        if !status.isEmpty {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(status == L10n.saved ? Color.secondary : Color.red)
                        }
                        editButtons
                    }
                    if editing {
                        HistoryTextEditor(text: $text, scrollIndex: scrollIndex, scrollToken: scrollToken) { edit in
                            undoStack.append(edit)
                            redoStack.removeAll()
                        }
                            .frame(minHeight: embedded ? 280 : 320)
                            .frame(maxHeight: embedded ? 480 : .infinity)
                            .padding(8)
                            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                    } else if isMarkdown {
                        preview {
                            Markdown(text)
                                .markdownTheme(.gitHub)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        preview {
                            Text(text)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(embedded ? 0 : 24)
                .frame(maxWidth: .infinity, maxHeight: embedded ? nil : .infinity, alignment: .topLeading)
            }
        }
        .onAppear(perform: load)
        .onChange(of: url) { _, _ in load() }
        .modifier(EditorNavigationBar(embedded: embedded, title: title, onBack: onBack))
    }

    @ViewBuilder
    private func preview<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if embedded {
            content()
        } else {
            ScrollView { content() }
        }
    }

    @ViewBuilder
    private var editButtons: some View {
        if editing {
            Button(action: undo) {
                Image(systemName: "arrow.uturn.backward")
            }
            .help(L10n.undo)
            .disabled(undoStack.isEmpty)
            Button(action: redo) {
                Image(systemName: "arrow.uturn.forward")
            }
            .help(L10n.redo)
            .disabled(redoStack.isEmpty)
            Button(L10n.cancel) {
                text = savedText
                editing = false
                status = ""
                undoStack.removeAll()
                redoStack.removeAll()
            }
            Button(L10n.save, action: save)
                .disabled(!dirty)
        } else {
            Button(L10n.edit) { editing = true }
                .disabled(!loaded)
        }
    }

    private func load() {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            missing = true
            return
        }
        missing = false
        text = raw
        savedText = raw
        loaded = true
        editing = false
        status = ""
        undoStack.removeAll()
        redoStack.removeAll()
    }

    private func undo() {
        guard let edit = undoStack.popLast() else { return }
        guard let updated = edit.reverted(in: text) else { return }
        redoStack.append(edit)
        reveal(updated, at: edit.location)
    }

    private func redo() {
        guard let edit = redoStack.popLast() else { return }
        guard let updated = edit.applied(in: text) else { return }
        undoStack.append(edit)
        reveal(updated, at: edit.location)
    }

    private func reveal(_ updated: String, at index: Int) {
        scrollIndex = index
        scrollToken += 1
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            text = updated
        }
    }

    private func save() {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            savedText = text
            editing = false
            status = L10n.saved
        } catch {
            status = L10n.saveFailed
        }
    }
}

/// One user replacement. `location` is a UTF-16 index, matching `NSTextView` ranges.
private struct TextEdit {
    var location: Int
    var removed: String
    var inserted: String

    func reverted(in source: String) -> String? {
        replace(in: source, length: (inserted as NSString).length, with: removed)
    }

    func applied(in source: String) -> String? {
        replace(in: source, length: (removed as NSString).length, with: inserted)
    }

    private func replace(in source: String, length: Int, with replacement: String) -> String? {
        let ns = source as NSString
        guard location >= 0, location + length <= ns.length else { return nil }
        return ns.replacingCharacters(in: NSRange(location: location, length: length), with: replacement)
    }
}

/// Stable bar: undo and redo stay out of it so those actions do not redraw the title.
private struct EditorNavigationBar: ViewModifier {
    var embedded: Bool
    var title: String
    var onBack: () -> Void

    func body(content: Content) -> some View {
        if embedded {
            content
        } else {
            content
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.back, action: onBack)
                    }
                }
        }
    }
}

/// Plain-text editor that can scroll to a character index after undo or redo.
private struct HistoryTextEditor: NSViewRepresentable {
    @Binding var text: String
    var scrollIndex: Int
    var scrollToken: Int
    /// Called only for a real keystroke or paste, with that one replacement.
    var onUserEdit: (TextEdit) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.drawsBackground = false
        textView.allowsUndo = false
        context.coordinator.ignoreChange = true
        textView.string = text
        context.coordinator.lastScrollToken = scrollToken
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if textView.string != text {
            // The change notice can arrive after this function returns.
            // Keep ignoring until that notice, so undo is not stored as a new edit.
            context.coordinator.ignoreChange = true
            textView.string = text
        }
        guard context.coordinator.lastScrollToken != scrollToken else { return }
        context.coordinator.lastScrollToken = scrollToken
        let length = (text as NSString).length
        let index = min(max(scrollIndex, 0), length)
        let range = NSRange(location: index, length: 0)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HistoryTextEditor
        var lastScrollToken = 0
        var ignoreChange = false
        var pending: [TextEdit] = []

        init(_ parent: HistoryTextEditor) {
            self.parent = parent
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            if ignoreChange { return true }
            let current = textView.string as NSString
            guard affectedCharRange.location >= 0,
                  NSMaxRange(affectedCharRange) <= current.length
            else { return true }
            pending.append(
                TextEdit(
                    location: affectedCharRange.location,
                    removed: current.substring(with: affectedCharRange),
                    inserted: replacementString ?? ""
                )
            )
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if ignoreChange {
                ignoreChange = false
                pending.removeAll()
                return
            }
            let edits = pending
            pending.removeAll()
            for edit in edits {
                parent.onUserEdit(edit)
            }
            parent.text = textView.string
        }
    }
}

struct FileListSection: View {
    let title: String
    let systemImage: String
    let files: [CodeFileRef]
    let emptyText: String
    /// Staff detail lists start closed; company canvas stays open.
    var collapsed: Bool = false
    var createTitle: String = L10n.newFile
    var onCreate: ((String) -> Void)? = nil
    var onDelete: ((CodeFileRef) -> Void)? = nil
    let onOpen: (CodeFileRef) -> Void

    @State private var expanded: Bool
    @State private var newName = ""
    @State private var showingNew = false
    @State private var pendingDelete: CodeFileRef?

    init(
        title: String,
        systemImage: String,
        files: [CodeFileRef],
        emptyText: String,
        collapsed: Bool = false,
        createTitle: String = L10n.newFile,
        onCreate: ((String) -> Void)? = nil,
        onDelete: ((CodeFileRef) -> Void)? = nil,
        onOpen: @escaping (CodeFileRef) -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.files = files
        self.emptyText = emptyText
        self.collapsed = collapsed
        self.createTitle = createTitle
        self.onCreate = onCreate
        self.onDelete = onDelete
        self.onOpen = onOpen
        _expanded = State(initialValue: !collapsed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                guard collapsed else { return }
                expanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Label(title, systemImage: systemImage)
                        .font(.headline)
                    Text("\(files.count)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                    Spacer()
                    if collapsed {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!collapsed)
            .contextMenu {
                if onCreate != nil {
                    Button(createTitle) { showingNew = true }
                }
            }

            if expanded {
                fileRows
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert(createTitle, isPresented: $showingNew) {
            TextField(L10n.fileName, text: $newName)
            Button(L10n.add) {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                newName = ""
                guard !name.isEmpty else { return }
                onCreate?(name)
            }
            Button(L10n.cancel, role: .cancel) { newName = "" }
        }
        .alert(L10n.deleteFile, isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button(L10n.deleteFile, role: .destructive) {
                if let file = pendingDelete {
                    onDelete?(file)
                }
                pendingDelete = nil
            }
            Button(L10n.cancel, role: .cancel) { pendingDelete = nil }
        } message: {
            Text(L10n.deleteFileConfirm(pendingDelete?.fileName ?? ""))
        }
    }

    @ViewBuilder
    private var fileRows: some View {
        if files.isEmpty {
            Text(emptyText)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                    ForEach(files) { file in
                        Button {
                            onOpen(file)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: icon(for: file))
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.fileName)
                                        .font(.system(.body, design: .monospaced))
                                        .fontWeight(.medium)
                                    Text(file.label)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Text(file.languageHint)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(L10n.edit) { onOpen(file) }
                            if onDelete != nil {
                                Button(L10n.deleteFile, role: .destructive) {
                                    pendingDelete = file
                                }
                            }
                        }
                        if file.id != files.last?.id {
                            Divider()
                        }
                    }
                }
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func icon(for file: CodeFileRef) -> String {
        switch file.languageHint {
        case "python": return "chevron.left.forwardslash.chevron.right"
        case "bash", "shell": return "terminal"
        case "markdown": return "doc.richtext"
        default: return "doc.text"
        }
    }
}

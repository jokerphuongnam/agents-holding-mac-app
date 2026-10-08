import MarkdownUI
import SwiftUI

/// Opens a plan or script for editing.
struct CodeFileDetailView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Group {
            if let file = appModel.openCodeFile {
                EditableTextFileView(
                    url: file.path,
                    title: file.fileName,
                    subtitle: file.label,
                    badge: file.languageHint,
                    onBack: { appModel.backFromCodeFile() }
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
    let onBack: () -> Void

    @State private var text = ""
    @State private var savedText = ""
    @State private var loaded = false
    @State private var missing = false
    @State private var editing = false
    @State private var status = ""

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
                    }
                    if editing {
                        TextEditor(text: $text)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                    } else if isMarkdown {
                        ScrollView {
                            Markdown(text)
                                .markdownTheme(.gitHub)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        ScrollView {
                            Text(text)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .navigationTitle(title)
        .onAppear(perform: load)
        .onChange(of: url) { _, _ in load() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.back, action: onBack)
            }
            ToolbarItem(placement: .primaryAction) {
                if editing {
                    Button(L10n.cancel) {
                        text = savedText
                        editing = false
                        status = ""
                    }
                    Button(L10n.save, action: save)
                        .disabled(!dirty)
                } else {
                    Button(L10n.edit) { editing = true }
                        .disabled(!loaded)
                }
            }
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

struct FileListSection: View {
    let title: String
    let systemImage: String
    let files: [CodeFileRef]
    let emptyText: String
    /// Staff detail lists start closed; company canvas stays open.
    var collapsed: Bool = false
    let onOpen: (CodeFileRef) -> Void

    @State private var expanded: Bool

    init(
        title: String,
        systemImage: String,
        files: [CodeFileRef],
        emptyText: String,
        collapsed: Bool = false,
        onOpen: @escaping (CodeFileRef) -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.files = files
        self.emptyText = emptyText
        self.collapsed = collapsed
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

            if expanded {
                fileRows
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

import HighlightSwift
import SwiftUI

/// Opens a script/source file with language-aware syntax highlighting.
struct CodeFileDetailView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Group {
            if let file = appModel.openCodeFile,
               let text = try? String(contentsOf: file.path, encoding: .utf8) {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(file.label)
                            .font(.title3.weight(.semibold))
                        HStack(spacing: 8) {
                            Text(file.languageHint)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                            Text(file.path.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Divider()
                        CodeText(text)
                            .highlightLanguage(highlightLanguage(for: file, source: text))
                            .codeTextColors(.theme(.github))
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(24)
                }
                .navigationTitle(file.fileName)
            } else {
                ContentUnavailableView(L10n.fileNotFound, systemImage: "doc.questionmark")
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.back) { appModel.backFromCodeFile() }
            }
        }
    }

    private func highlightLanguage(for file: CodeFileRef, source: String) -> HighlightLanguage {
        var hint = file.languageHint
        if hint == "plaintext" || hint.isEmpty {
            if source.hasPrefix("#!") {
                let first = source.prefix(80).lowercased()
                if first.contains("python") { hint = "python" }
                else if first.contains("bash") || first.contains("/sh") { hint = "bash" }
                else if first.contains("ruby") { hint = "ruby" }
                else if first.contains("node") { hint = "javascript" }
            }
        }
        switch hint {
        case "python": return .python
        case "bash", "shell", "sh", "zsh": return .bash
        case "ruby": return .ruby
        case "javascript": return .javaScript
        case "typescript": return .typeScript
        case "swift": return .swift
        case "kotlin": return .kotlin
        case "go": return .go
        case "rust": return .rust
        case "java": return .java
        case "c": return .c
        case "cpp": return .cPlusPlus
        case "csharp": return .cSharp
        case "json": return .json
        case "yaml": return .yaml
        case "markdown": return .markdown
        case "toml": return .toml
        default: return .plaintext
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

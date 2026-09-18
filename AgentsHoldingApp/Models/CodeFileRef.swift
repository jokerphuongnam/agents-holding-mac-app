import Foundation

struct CodeFileRef: Identifiable, Hashable {
    var id: String { path.path }
    var path: URL
    var label: String
    var languageHint: String

    var fileName: String { path.lastPathComponent }

    static func language(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "py": return "python"
        case "sh", "bash", "zsh": return "bash"
        case "rb": return "ruby"
        case "js", "mjs", "cjs": return "javascript"
        case "ts", "tsx": return "typescript"
        case "swift": return "swift"
        case "kt", "kts": return "kotlin"
        case "go": return "go"
        case "rs": return "rust"
        case "java": return "java"
        case "c", "h": return "c"
        case "cpp", "cc", "hpp", "cxx": return "cpp"
        case "cs": return "csharp"
        case "md": return "markdown"
        case "json": return "json"
        case "yml", "yaml": return "yaml"
        case "toml": return "ini"
        default:
            // shebang fallback later in viewer
            return "plaintext"
        }
    }

    static func make(url: URL, relativeTo root: URL?) -> CodeFileRef {
        let label: String
        if let root {
            let rp = root.path
            let p = url.path
            if p.hasPrefix(rp + "/") {
                label = String(p.dropFirst(rp.count + 1))
            } else {
                label = url.lastPathComponent
            }
        } else {
            label = url.lastPathComponent
        }
        return CodeFileRef(path: url, label: label, languageHint: language(for: url))
    }
}

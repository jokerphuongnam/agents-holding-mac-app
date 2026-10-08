import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var model = SettingsScreenModel()
    @EnvironmentObject private var languageStore: LanguageStore
    @AppStorage("holdingPath") private var holdingPath: String = ""

    var body: some View {
        let _ = model.attach(appModel)
        Form {
            Section(L10n.languageSection) {
                Picker(L10n.languagePicker, selection: $languageStore.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            }

            Section(L10n.holdingPath) {
                TextField(L10n.holdingPath, text: $holdingPath)
                Text(L10n.holdingPathHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let path = appModel.holdingPath {
                    Text(L10n.activePath(path.path))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
                Button(L10n.useDocumentsHolding) {
                    let p = NSHomeDirectory() + "/Documents/Agents/agents-holding"
                    holdingPath = p
                    model.send(.reload)
                }
                Button(L10n.applyReload) {
                    model.send(.reload)
                }
            }
        }
        .padding()
        .frame(width: 520)
    }
}

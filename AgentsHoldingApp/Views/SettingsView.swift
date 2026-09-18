import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var languageStore: LanguageStore
    @AppStorage("holdingPath") private var holdingPath: String = ""

    var body: some View {
        Form {
            Section(L10n.tr("language_section")) {
                Picker(L10n.tr("language_picker"), selection: $languageStore.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(L10n.tr(lang.displayNameKey)).tag(lang)
                    }
                }
            }

            Section(L10n.tr("holding_path")) {
                TextField(L10n.tr("holding_path"), text: $holdingPath)
                Text(L10n.tr("holding_path_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let path = appModel.holdingPath {
                    Text(L10n.tr("active_path", path.path))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
                Button(L10n.tr("use_documents_holding")) {
                    let p = NSHomeDirectory() + "/Documents/Agents/agents-holding"
                    holdingPath = p
                    appModel.reloadHolding()
                }
                Button(L10n.tr("apply_reload")) {
                    appModel.reloadHolding()
                }
            }
        }
        .padding()
        .frame(width: 520)
    }
}

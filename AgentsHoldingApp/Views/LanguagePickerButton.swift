import SwiftUI

/// Visible language switcher (toolbar / sidebar) — EN / VI / System.
struct LanguagePickerButton: View {
    @EnvironmentObject private var languageStore: LanguageStore

    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    languageStore.language = lang
                } label: {
                    if languageStore.language == lang {
                        Label(lang.displayName, systemImage: "checkmark")
                    } else {
                        Text(lang.displayName)
                    }
                }
            }
        } label: {
            Label {
                Text(shortLabel)
            } icon: {
                Image(systemName: "globe")
            }
        }
        .help(L10n.languagePicker)
        .accessibilityLabel(L10n.languagePicker)
    }

    private var shortLabel: String {
        switch languageStore.language {
        case .system: return "Auto"
        case .english: return "EN"
        case .vietnamese: return "VI"
        }
    }
}

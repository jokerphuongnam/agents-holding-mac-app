import SwiftUI

@main
struct AgentsHoldingAppApp: App {
    @State private var appModel = AppModel()
    @ObservedObject private var languageStore = LanguageStore.shared

    var body: some Scene {
        // `Window` is a single instance. `WindowGroup` restores and duplicates windows.
        Window("Agents Holding", id: "main") {
            RootView()
                .environment(appModel)
                .environmentObject(languageStore)
                .environment(\.locale, languageStore.locale)
                .id(languageStore.revision)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        WindowGroup(id: "company-chat", for: ChatWindowTarget.self) { $target in
            if let target {
                CompanyChatView(
                    companyRoot: URL(fileURLWithPath: target.companyRoot),
                    projectRoot: target.projectRoot.map { URL(fileURLWithPath: $0) }
                )
                .environment(appModel)
                .environmentObject(languageStore)
                .environment(\.locale, languageStore.locale)
                .id(languageStore.revision)
                .frame(minWidth: 640, minHeight: 480)
            }
        }
        .defaultSize(width: 720, height: 560)

        Settings {
            SettingsView()
                .environment(appModel)
                .environmentObject(languageStore)
                .environment(\.locale, languageStore.locale)
                .id(languageStore.revision)
        }
    }
}

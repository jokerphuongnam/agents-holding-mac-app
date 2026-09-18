import SwiftUI

@main
struct AgentsHoldingAppApp: App {
    @StateObject private var appModel = AppModel()
    @ObservedObject private var languageStore = LanguageStore.shared

    var body: some Scene {
        WindowGroup("Agents Holding") {
            RootView()
                .environmentObject(appModel)
                .environmentObject(languageStore)
                .environment(\.locale, languageStore.locale)
                .id(languageStore.revision)
                .frame(minWidth: 960, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(appModel)
                .environmentObject(languageStore)
                .environment(\.locale, languageStore.locale)
                .id(languageStore.revision)
        }
    }
}

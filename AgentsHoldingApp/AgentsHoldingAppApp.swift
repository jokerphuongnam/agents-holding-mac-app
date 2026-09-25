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

        WindowGroup(
            L10nLookup("staffs_tree_window_title", "Localizable", "Staffs tree"),
            id: "staffs-tree",
            for: StaffsTreeWindowID.self
        ) { $windowID in
            if let windowID {
                StaffsTreeWindowView(windowID: windowID)
                    .environmentObject(appModel)
                    .environmentObject(languageStore)
                    .environment(\.locale, languageStore.locale)
                    .id(languageStore.revision)
            } else {
                ContentUnavailableView(
                    L10nLookup("staffs_tree_empty", "Localizable", "No staffs to show in the org tree"),
                    systemImage: "person.3"
                )
            }
        }
        .defaultSize(width: 1100, height: 860)

        Settings {
            SettingsView()
                .environmentObject(appModel)
                .environmentObject(languageStore)
                .environment(\.locale, languageStore.locale)
                .id(languageStore.revision)
        }
    }
}

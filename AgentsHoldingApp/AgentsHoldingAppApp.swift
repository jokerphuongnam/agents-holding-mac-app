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
            L10n.staffsTreeWindowTitle,
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
                    L10n.staffsTreeEmpty,
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

import SwiftUI

@main
struct AgentsHoldingAppApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup("Agents Holding") {
            RootView()
                .environmentObject(appModel)
                .frame(minWidth: 960, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(appModel)
        }
    }
}

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("holdingPath") private var holdingPath: String = ""

    var body: some View {
        Form {
            TextField("Holding path", text: $holdingPath)
            Text("Or set env AGENTS_HOLDING_PATH. Default: sibling ../agents-holding")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Apply & reload") {
                appModel.reloadHolding()
            }
        }
        .padding()
        .frame(width: 480)
    }
}

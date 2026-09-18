import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("holdingPath") private var holdingPath: String = ""

    var body: some View {
        Form {
            TextField("Holding path", text: $holdingPath)
            Text("SoT khuyến nghị: ~/Documents/Agents/agents-holding (không dùng ~/.agents — sqlite inventory khác). Env: AGENTS_HOLDING_PATH.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let path = appModel.holdingPath {
                Text("Active: \(path.path)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            Button("Use Documents/Agents/agents-holding") {
                let p = NSHomeDirectory() + "/Documents/Agents/agents-holding"
                holdingPath = p
                appModel.reloadHolding()
            }
            Button("Apply & reload") {
                appModel.reloadHolding()
            }
        }
        .padding()
        .frame(width: 480)
    }
}

import SwiftUI

/// Dedicated window hosting a full-height staffs org graph.
struct StaffsTreeWindowView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    let windowID: StaffsTreeWindowID

    private var companyRoot: URL {
        URL(fileURLWithPath: windowID.companyRootPath, isDirectory: true)
    }

    var body: some View {
        StaffsTreeView(
            roots: StaffDirectory().buildStaffTree(companyRoot: companyRoot),
            showsHeading: true,
            viewportMaxHeight: nil,
            windowID: nil
        ) { staff in
            appModel.openStaff(staff, companyRoot: companyRoot, inHolding: windowID.inHolding)
        }
        .padding(16)
        .frame(minWidth: 900, minHeight: 640)
        .navigationTitle(windowID.title)
        .task {
            // Drop session-restored / auto-launched copies — only toolbar open is intentional.
            // `.task` runs after the window is in the hierarchy (more reliable than onAppear + dismiss).
            if !StaffsTreeWindowGate.consumeOpenToken() {
                dismissWindow(id: "staffs-tree")
            }
        }
    }
}

/// Placeholder when `WindowGroup` opens with a nil value — close immediately.
struct StaffsTreeWindowDiscardView: View {
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .task { dismissWindow(id: "staffs-tree") }
    }
}

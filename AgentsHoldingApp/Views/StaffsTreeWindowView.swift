import SwiftUI

/// Dedicated window hosting a full-height staffs org graph.
struct StaffsTreeWindowView: View {
    @EnvironmentObject private var appModel: AppModel
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
    }
}

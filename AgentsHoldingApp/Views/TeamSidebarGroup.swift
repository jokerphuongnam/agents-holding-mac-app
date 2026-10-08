import SwiftUI

/// Sidebar team row, including nested `teams/<child>/`.
struct TeamSidebarGroup: View {
    let team: TeamNode
    let onStaff: (StaffNode) -> Void

    var body: some View {
        DisclosureGroup(team.name) {
            ForEach(team.staffs) { staff in
                Button(staff.name) { onStaff(staff) }
            }
            ForEach(team.childTeams) { child in
                TeamSidebarGroup(team: child, onStaff: onStaff)
            }
        }
    }
}

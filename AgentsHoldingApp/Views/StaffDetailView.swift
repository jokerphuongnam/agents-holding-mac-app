import SwiftUI

struct StaffDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    let staffId: String

    var body: some View {
        let staff = appModel.staff(for: staffId)
        Group {
            if let staff {
                Form {
                    LabeledContent("Name", value: staff.name)
                    LabeledContent("Team", value: staff.team)
                    if !staff.blurb.isEmpty {
                        LabeledContent("Blurb") {
                            Text(staff.blurb)
                        }
                    }
                    Section("Later") {
                        Text("Skills, access scope, runtime profiles (grok/codex/claude/merge), worktrees — see plan P0→P2.")
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .navigationTitle(staff.name)
            } else {
                ContentUnavailableView("Staff not found", systemImage: "person.slash")
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Company") {
                    if let company = appModel.openCompany?.node {
                        appModel.selection = .company(company.id)
                    } else {
                        appModel.backToHolding()
                    }
                }
            }
        }
    }
}

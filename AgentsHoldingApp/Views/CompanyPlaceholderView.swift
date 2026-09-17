import SwiftUI

struct CompanyPlaceholderView: View {
    @EnvironmentObject private var appModel: AppModel
    let companyId: String

    var body: some View {
        let company = appModel.holding?.companies.first { $0.id == companyId }
        Group {
            if let company {
                VStack(alignment: .leading, spacing: 16) {
                    Text(company.displayName)
                        .font(.largeTitle.weight(.semibold))
                    Text(company.slug)
                        .foregroundStyle(.secondary)
                    if let pointer = company.pointerPath {
                        Text("Pointer: \(pointer.path)")
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                    Text("P0 placeholder — next: load company staffs canvas, context strip (folder / plan / worktree), CEO chat dock.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle(company.displayName)
            } else {
                ContentUnavailableView("Company not found", systemImage: "building.2.crop.circle")
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Holding") { appModel.backToHolding() }
            }
        }
    }
}

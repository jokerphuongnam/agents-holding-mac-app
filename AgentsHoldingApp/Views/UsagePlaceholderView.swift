import SwiftUI

struct UsagePlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            "Usage",
            systemImage: "chart.bar",
            description: Text("Token stats by staff / model / worktree / day·month — plan P4. Merge traffic attributes to the resolved model.")
        )
        .navigationTitle("Usage")
    }
}

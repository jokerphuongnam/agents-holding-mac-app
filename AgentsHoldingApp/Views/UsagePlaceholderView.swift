import SwiftUI

struct UsagePlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            L10n.usage,
            systemImage: "chart.bar",
            description: Text(L10n.usagePlaceholder)
        )
        .navigationTitle(L10n.usage)
    }
}

import SwiftUI

struct UsagePlaceholderView: View {
    var body: some View {
        ContentUnavailableView(
            L10n.tr("usage"),
            systemImage: "chart.bar",
            description: Text(L10n.tr("usage_placeholder"))
        )
        .navigationTitle(L10n.tr("usage"))
    }
}

import SwiftUI

struct NameEditButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(.quaternary.opacity(0.9), in: Circle())
        }
        .buttonStyle(.plain)
        .help(L10n.edit)
    }
}

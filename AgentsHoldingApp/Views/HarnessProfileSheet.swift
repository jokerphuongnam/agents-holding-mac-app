import SwiftUI

struct HarnessProfileSheet: View {
    let profiles: StaffHarnessProfiles
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.harnessProfilesTitle)
                        .font(.title3.weight(.semibold))
                    Text(L10n.harnessProfilesSubtitle(profiles.staffName, profiles.tier))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.done) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.harnessProfilesHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Header
                    HStack {
                        Text(L10n.harnessColMode).frame(width: 72, alignment: .leading)
                        Text(L10n.harnessColRuntime).frame(width: 72, alignment: .leading)
                        Text(L10n.harnessColModel).frame(maxWidth: .infinity, alignment: .leading)
                        Text(L10n.harnessColEffort).frame(width: 72, alignment: .leading)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    Divider()

                    ForEach(profiles.modes) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.mode)
                                    .fontWeight(.semibold)
                                    .frame(width: 72, alignment: .leading)
                                Text(row.runtime)
                                    .frame(width: 72, alignment: .leading)
                                Text(row.model)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                Text(row.effort)
                                    .frame(width: 72, alignment: .leading)
                            }
                            Text(row.note)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 560, height: 420)
    }
}

import SwiftUI

struct HarnessProfileSheet: View {
    @Environment(AppModel.self) private var appModel
    @State private var model = HarnessScreenModel()
    @Environment(\.dismiss) private var dismiss

    @State private var tier = "medium"
    @State private var routerEnabled = false
    @State private var mergeRuntime = "grok"
    @State private var modes: [HarnessModeProfile] = []
    @State private var models: [String: String] = [:]
    @State private var efforts: [String: String] = [:]
    /// Values last read from disk. Picker changes that match these are reloads, not edits.
    @State private var diskTier = ""
    @State private var diskRouter = false
    @State private var diskRuntime = ""

    private var detail: StaffDetail? { appModel.staffDetail }
    private var vendors: [String] { modes.map(\.mode).filter { $0 != "merge" } }

    var body: some View {
        let _ = model.attach(appModel)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.harnessProfilesTitle)
                        .font(.title3.weight(.semibold))
                    if let detail {
                        Text(L10n.harnessProfilesSubtitle(detail.node.name, tier))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

                    HStack(spacing: 16) {
                        Picker(L10n.harnessTier, selection: $tier) {
                            ForEach(HarnessProfileService.tiers, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 180)
                        Toggle(L10n.harnessRouterToggle, isOn: $routerEnabled)
                    }

                    Text(L10n.harnessSharedTier(tier))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    HStack {
                        Text(L10n.harnessColMode).frame(width: 72, alignment: .leading)
                        Text(L10n.harnessColRuntime).frame(width: 110, alignment: .leading)
                        Text(L10n.harnessColModel).frame(maxWidth: .infinity, alignment: .leading)
                        Text(L10n.harnessColEffort).frame(width: 110, alignment: .leading)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    Divider()

                    ForEach(modes) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.mode)
                                    .fontWeight(.semibold)
                                    .frame(width: 72, alignment: .leading)
                                runtimeControl(row)
                                    .frame(width: 110, alignment: .leading)
                                modelControl(row)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                effortControl(row)
                                    .frame(width: 110, alignment: .leading)
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
        .frame(width: 680, height: 520)
        .onAppear { reload(fromDisk: true) }
        .onDisappear(perform: saveModels)
        .onChange(of: tier) { _, newValue in
            guard let detail, newValue != diskTier else { return }
            diskTier = newValue
            model.send(.setTier(newValue, staffFile: detail.sourceFile, name: detail.node.name, companyRoot: detail.companyRoot))
            reload(fromDisk: false)
        }
        .onChange(of: routerEnabled) { _, newValue in
            guard let detail, newValue != diskRouter else { return }
            diskRouter = newValue
            model.send(.setRouter(newValue, detail.companyRoot))
            reload(fromDisk: false)
        }
        .onChange(of: mergeRuntime) { _, newValue in
            guard let detail, newValue != diskRuntime else { return }
            diskRuntime = newValue
            model.send(.setRuntime(newValue, staff: detail.node.name, companyRoot: detail.companyRoot))
            reload(fromDisk: false)
        }
    }

    @ViewBuilder
    private func runtimeControl(_ row: HarnessModeProfile) -> some View {
        if row.mode == "merge" {
            Picker("", selection: $mergeRuntime) {
                ForEach(vendors, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        } else {
            Text(row.runtime)
        }
    }

    @ViewBuilder
    private func modelControl(_ row: HarnessModeProfile) -> some View {
        if row.mode == "merge" {
            Text(row.model).font(.system(.body, design: .monospaced))
        } else {
            TextField(L10n.harnessColModel, text: modelBinding(row.mode))
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .onSubmit { saveMapping(row.mode) }
        }
    }

    @ViewBuilder
    private func effortControl(_ row: HarnessModeProfile) -> some View {
        if row.mode == "merge" {
            Text(row.effort)
        } else {
            Picker("", selection: effortBinding(row.mode)) {
                ForEach(HarnessProfileService.efforts, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private func modelBinding(_ mode: String) -> Binding<String> {
        Binding(
            get: { models[mode] ?? "" },
            set: { models[mode] = $0 }
        )
    }

    private func effortBinding(_ mode: String) -> Binding<String> {
        Binding(
            get: { efforts[mode] ?? "medium" },
            set: { newValue in
                guard efforts[mode] != newValue else { return }
                efforts[mode] = newValue
                saveMapping(mode)
            }
        )
    }

    private func saveMapping(_ mode: String) {
        guard let detail, mode != "merge" else { return }
        model.send(.setMapping(
            runtime: mode,
            tier: tier,
            model: models[mode] ?? "",
            effort: efforts[mode] ?? "",
            companyRoot: detail.companyRoot
        ))
        reload(fromDisk: false)
    }

    private func saveModels() {
        guard let detail else { return }
        for mode in vendors {
            model.send(.setMapping(
                runtime: mode,
                tier: tier,
                model: models[mode] ?? "",
                effort: efforts[mode] ?? "",
                companyRoot: detail.companyRoot
            ))
        }
    }

    private func reload(fromDisk: Bool) {
        guard let detail else { return }
        let queryTier = fromDisk ? detail.tier : tier
        let profiles = HarnessProfileService().profiles(
            forStaff: detail.node.name,
            tier: queryTier,
            companyRoot: detail.companyRoot
        )
        diskTier = profiles.tier
        diskRouter = profiles.routerEnabled
        diskRuntime = profiles.mergeRuntime
        if tier != profiles.tier { tier = profiles.tier }
        if routerEnabled != profiles.routerEnabled { routerEnabled = profiles.routerEnabled }
        if mergeRuntime != profiles.mergeRuntime { mergeRuntime = profiles.mergeRuntime }
        modes = profiles.modes
        var nextModels: [String: String] = [:]
        var nextEfforts: [String: String] = [:]
        for row in profiles.modes where row.mode != "merge" {
            nextModels[row.mode] = row.model == "—" ? "" : row.model
            nextEfforts[row.mode] = HarnessProfileService.efforts.contains(row.effort) ? row.effort : "medium"
        }
        models = nextModels
        efforts = nextEfforts
    }
}

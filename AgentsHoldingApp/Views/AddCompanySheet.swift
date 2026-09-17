import SwiftUI

struct AddCompanySheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var projectRootPath: String = ""
    @State private var name: String = ""
    @State private var budget: String = "medium"
    @State private var registerOnly: Bool = false
    @State private var existingHint: String = ""
    @State private var isWorking = false
    @State private var log: String = ""
    @State private var localError: String?

    private let budgets = ["low", "medium", "high"]
    private let installer = CompanyInstallService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add company")
                .font(.title2.weight(.semibold))
            Text("Chọn folder project trên máy → cài Company OS (hoặc chỉ đăng ký nếu đã có `.agents/*-company`).")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(projectRootPath.isEmpty ? "Chưa chọn" : projectRootPath)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(3)
                }
                Spacer()
                Button("Browse…") { browse() }
                    .keyboardShortcut("o", modifiers: [.command])
            }

            TextField("Company name (slug, không cần -company)", text: $name)
                .textFieldStyle(.roundedBorder)

            Picker("Budget", selection: $budget) {
                ForEach(budgets, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)

            Toggle("Chỉ register (folder đã có Company OS)", isOn: $registerOnly)
            if !existingHint.isEmpty {
                Text(existingHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let localError {
                Text(localError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            if !log.isEmpty {
                ScrollView {
                    Text(log)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 160)
                .padding(8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isWorking ? "Working…" : "Add") {
                    Task { await add() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking || projectRootPath.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            if projectRootPath.isEmpty {
                browse()
            }
        }
    }

    private func browse() {
        guard let url = installer.pickProjectFolder() else { return }
        projectRootPath = url.path
        name = installer.suggestedName(for: url)
        let existing = installer.existingCompanyDirs(in: url)
        if !existing.isEmpty {
            registerOnly = true
            existingHint = "Phát hiện: \(existing.map(\.lastPathComponent).joined(separator: ", ")) — nên Register only."
        } else {
            registerOnly = false
            existingHint = "Chưa có Company OS → sẽ chạy create-company.sh vào folder này."
        }
        localError = nil
    }

    @MainActor
    private func add() async {
        localError = nil
        log = ""
        isWorking = true
        defer { isWorking = false }

        guard let holding = appModel.holdingPath else {
            localError = CompanyInstallError.missingHolding.localizedDescription
            return
        }
        let root = URL(fileURLWithPath: projectRootPath)
        let request = CompanyInstallRequest(
            projectRoot: root,
            name: name,
            budget: budget,
            registerOnly: registerOnly
        )
        do {
            let output = try installer.install(request, holdingRoot: holding)
            log = output.isEmpty ? "OK" : output
            appModel.reloadHolding()
            // Brief pause so user can see log, then close
            try? await Task.sleep(nanoseconds: 400_000_000)
            dismiss()
        } catch {
            localError = error.localizedDescription
            log = error.localizedDescription
        }
    }
}

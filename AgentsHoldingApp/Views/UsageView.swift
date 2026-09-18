import SwiftUI

struct UsageView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var report: UsageReport?
    @State private var scopeCompany: Bool = true

    private let ledger = UsageLedgerService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let report, report.eventCount > 0 {
                    summaryCards(report)
                    periodTable(
                        title: L10n.usageTableSummary,
                        rows: [report.allTime, report.today]
                    )
                    periodTable(
                        title: L10n.usageTableByDay,
                        rows: report.byDay
                    )
                    ledgerFooter(report)
                } else {
                    emptyState
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(L10n.usage)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L10n.reload) { reload() }
            }
        }
        .onAppear { reload() }
        .onChange(of: appModel.openCompany?.node.id) { _, _ in reload() }
        .onChange(of: scopeCompany) { _, _ in reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.usage)
                .font(.title2.weight(.semibold))
            Text(L10n.usageHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(L10n.usageScope, selection: $scopeCompany) {
                Text(L10n.usageScopeHolding).tag(false)
                Text(L10n.usageScopeCompany).tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            if scopeCompany, let company = appModel.openCompany?.node {
                Text(company.slug)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func summaryCards(_ report: UsageReport) -> some View {
        HStack(spacing: 12) {
            metricCard(L10n.usageAllTime, report.allTime.total)
            metricCard(L10n.usageToday, report.today.total)
            metricCard(L10n.usageEvents, report.eventCount)
        }
    }

    private func metricCard(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.formatted())
                .font(.title3.weight(.semibold).monospacedDigit())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }

    private func periodTable(title: String, rows: [UsagePeriodRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            if rows.isEmpty {
                Text(L10n.usageNoRows)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text(L10n.usageColPeriod).fontWeight(.semibold)
                        Text(L10n.usageColTotal).fontWeight(.semibold)
                        Text("grok").fontWeight(.semibold)
                        Text("claude").fontWeight(.semibold)
                        Text("codex").fontWeight(.semibold)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Divider().gridCellColumns(5)
                    ForEach(rows) { row in
                        GridRow {
                            Text(displayPeriod(row.label))
                            Text(row.total.formatted()).monospacedDigit()
                            Text(token(row, "grok")).monospacedDigit()
                            Text(token(row, "claude")).monospacedDigit()
                            Text(token(row, "codex")).monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            ContentUnavailableView(
                L10n.usageEmptyTitle,
                systemImage: "chart.bar.doc.horizontal",
                description: Text(L10n.usageEmptyBody)
            )
            .frame(maxWidth: .infinity)

            Text(L10n.usageSchemaHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(schemaExample)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func ledgerFooter(_ report: UsageReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.usageLedgerPaths)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(report.ledgerPaths, id: \.path) { url in
                Text(url.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
    }

    private var schemaExample: String {
        """
        # <company|holding>/cache/usage/events.jsonl
        {"timestamp":"2026-09-18T10:00:00Z","company":"desk-garden-company","staff":"ceo","model":"grok","launch_mode":"grok","input_tokens":100,"output_tokens":20,"total_tokens":120}
        {"timestamp":"2026-09-18T11:00:00Z","company":"desk-garden-company","staff":"ba-user","model":"claude","launch_mode":"merge","total_tokens":50}
        """
    }

    private func reload() {
        let companyRoot = scopeCompany ? appModel.openCompany?.companyRoot : nil
        let slug = scopeCompany ? appModel.openCompany?.node.slug : nil
        report = ledger.loadReport(
            holdingRoot: appModel.holdingPath,
            companyRoot: companyRoot,
            companySlug: slug
        )
    }

    private func token(_ row: UsagePeriodRow, _ model: String) -> String {
        (row.byModel.first { $0.model == model }?.tokens ?? 0).formatted()
    }

    private func displayPeriod(_ label: String) -> String {
        switch label {
        case "all-time": return L10n.usageAllTime
        case "today": return L10n.usageToday
        default: return label
        }
    }
}

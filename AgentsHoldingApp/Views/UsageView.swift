import Charts
import SwiftUI

struct UsageView: View {
    @EnvironmentObject private var appModel: AppModel

    @State private var scopeCompany = true
    @State private var worktreeSelection: String = "" // "" = all
    @State private var rangeStart: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var rangeEnd: Date = Date()
    @State private var bucket: UsageBucket = .day

    @State private var rawEvents: [UsageEvent] = []
    @State private var ledgerPaths: [URL] = []
    @State private var report: UsageReport?

    private let ledger = UsageLedgerService()
    private let chartModels = ["grok", "claude", "codex"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                filters
                if let report, report.filteredCount > 0 || report.eventCount > 0 {
                    summaryCards(report)
                    modelShareChart(report)
                    timelineChart(report)
                    periodTable(title: L10n.usageTableSummary, rows: [report.rangeTotal])
                    periodTable(title: bucketTableTitle, rows: report.buckets)
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
                Button(L10n.reload) { reloadRaw() }
            }
        }
        .onAppear { reloadRaw() }
        .onChange(of: appModel.openCompany?.node.id) { _, _ in reloadRaw() }
        .onChange(of: scopeCompany) { _, _ in reloadRaw() }
        .onChange(of: worktreeSelection) { _, _ in reaggregate() }
        .onChange(of: rangeStart) { _, _ in reaggregate() }
        .onChange(of: rangeEnd) { _, _ in reaggregate() }
        .onChange(of: bucket) { _, _ in reaggregate() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.usage)
                .font(.title2.weight(.semibold))
            Text(L10n.usageHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.usageFilters)
                .font(.headline)

            Picker(L10n.usageScope, selection: $scopeCompany) {
                Text(L10n.usageScopeHolding).tag(false)
                Text(L10n.usageScopeCompany).tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            if scopeCompany {
                if let company = appModel.openCompany?.node {
                    Text(company.slug)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L10n.usageOpenCompanyHint)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                DatePicker(L10n.usageFrom, selection: $rangeStart, displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: 160)
                Text("→").foregroundStyle(.secondary)
                DatePicker(L10n.usageTo, selection: $rangeEnd, displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: 160)
                Spacer()
            }

            HStack(spacing: 8) {
                Text(L10n.usageFrom).font(.caption).foregroundStyle(.secondary)
                Spacer().frame(width: 120)
                Text(L10n.usageTo).font(.caption).foregroundStyle(.secondary)
            }

            Picker(L10n.usageBucket, selection: $bucket) {
                Text(L10n.usageBucketDay).tag(UsageBucket.day)
                Text(L10n.usageBucketWeek).tag(UsageBucket.week)
                Text(L10n.usageBucketMonth).tag(UsageBucket.month)
                Text(L10n.usageBucketYear).tag(UsageBucket.year)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 480)

            Picker(L10n.usageWorktree, selection: $worktreeSelection) {
                Text(L10n.usageWorktreeAll).tag("")
                ForEach(report?.availableWorktrees ?? distinctWorktrees(), id: \.self) { wt in
                    Text(wt).tag(wt)
                }
            }
            .frame(maxWidth: 420)

            HStack {
                Button(L10n.usagePreset7d) { applyPreset(days: 7) }
                Button(L10n.usagePreset30d) { applyPreset(days: 30) }
                Button(L10n.usagePreset90d) { applyPreset(days: 90) }
                Button(L10n.usagePresetAll) { applyAllDataRange() }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
    }

    private var bucketTableTitle: String {
        switch bucket {
        case .day: return L10n.usageTableByDay
        case .week: return L10n.usageTableByWeek
        case .month: return L10n.usageTableByMonth
        case .year: return L10n.usageTableByYear
        }
    }

    private func summaryCards(_ report: UsageReport) -> some View {
        HStack(spacing: 12) {
            metricCard(L10n.usageRangeTotal, report.rangeTotal.total)
            metricCard(L10n.usageEvents, report.filteredCount)
            metricCard(L10n.usageEventsLoaded, report.eventCount)
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

    /// Pie/sector share of models in the selected range.
    private func modelShareChart(_ report: UsageReport) -> some View {
        let slices = report.rangeTotal.byModel.filter { chartModels.contains($0.model) }
        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.usageChartModels)
                .font(.headline)
            if report.rangeTotal.total == 0 {
                Text(L10n.usageNoRows)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value(L10n.usageColTotal, slice.tokens),
                        innerRadius: .ratio(0.45),
                        angularInset: 1.5
                    )
                    .foregroundStyle(by: .value(L10n.usageColModel, slice.model))
                    .cornerRadius(3)
                }
                .chartForegroundStyleScale([
                    "grok": Color.orange,
                    "claude": Color.purple,
                    "codex": Color.blue,
                ])
                .frame(height: 220)
                .padding(12)
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    /// Stacked bars over buckets (day/week/month/year).
    private func timelineChart(_ report: UsageReport) -> some View {
        let points: [UsageChartPoint] = report.buckets.reversed().flatMap { row in
            chartModels.map { model in
                UsageChartPoint(
                    period: displayPeriod(row.label),
                    model: model,
                    tokens: row.byModel.first { $0.model == model }?.tokens ?? 0
                )
            }
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.usageChartTimeline)
                .font(.headline)
            if report.buckets.isEmpty {
                Text(L10n.usageNoRows)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart(points) { point in
                    BarMark(
                        x: .value(L10n.usageColPeriod, point.period),
                        y: .value(L10n.usageColTotal, point.tokens)
                    )
                    .foregroundStyle(by: .value(L10n.usageColModel, point.model))
                }
                .chartForegroundStyleScale([
                    "grok": Color.orange,
                    "claude": Color.purple,
                    "codex": Color.blue,
                ])
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 260)
                .padding(12)
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
            }
        }
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
            if report.ledgerPaths.isEmpty {
                Text(L10n.noneEmdash)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
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
        # cache/usage/events.jsonl
        {"timestamp":"2026-09-18T10:00:00Z","company":"desk-garden-company","staff":"ceo","worktree":"feat-x","model":"grok","launch_mode":"grok","total_tokens":120}
        {"timestamp":"2026-09-18T11:00:00Z","company":"desk-garden-company","staff":"ba-user","worktree":"feat-x","model":"claude","launch_mode":"merge","total_tokens":50}
        """
    }

    private func reloadRaw() {
        let companyRoot = scopeCompany ? appModel.openCompany?.companyRoot : nil
        let slug = scopeCompany ? appModel.openCompany?.node.slug : nil
        let loaded = ledger.loadRawEvents(
            holdingRoot: appModel.holdingPath,
            companyRoot: companyRoot,
            companySlug: slug
        )
        rawEvents = loaded.events
        ledgerPaths = loaded.paths
        if let min = loaded.events.map(\.timestamp).min(),
           let max = loaded.events.map(\.timestamp).max(),
           rangeStart == Calendar.current.date(byAdding: .day, value: -30, to: Date()) {
            // keep user range unless still default-ish; still ok to leave
            _ = min
            _ = max
        }
        // Drop worktree filter if no longer present
        let wts = Set(loaded.events.compactMap(\.worktree).filter { !$0.isEmpty })
        if !worktreeSelection.isEmpty, !wts.contains(worktreeSelection) {
            worktreeSelection = ""
        }
        reaggregate()
    }

    private func reaggregate() {
        let slug = scopeCompany ? (appModel.openCompany?.node.slug ?? "company") : "holding"
        var start = rangeStart
        var end = rangeEnd
        if start > end { swap(&start, &end) }
        let query = UsageQuery(
            scopeCompany: scopeCompany,
            worktree: worktreeSelection.isEmpty ? nil : worktreeSelection,
            rangeStart: start,
            rangeEnd: end,
            bucket: bucket
        )
        report = ledger.report(
            events: rawEvents,
            ledgerPaths: ledgerPaths,
            scopeLabel: slug,
            query: query
        )
    }

    private func applyPreset(days: Int) {
        rangeEnd = Date()
        rangeStart = Calendar.current.date(byAdding: .day, value: -days, to: rangeEnd) ?? rangeEnd
    }

    private func applyAllDataRange() {
        if let min = rawEvents.map(\.timestamp).min(),
           let max = rawEvents.map(\.timestamp).max() {
            rangeStart = min
            rangeEnd = max
        }
    }

    private func distinctWorktrees() -> [String] {
        Array(Set(rawEvents.compactMap(\.worktree).filter { !$0.isEmpty })).sorted()
    }

    private func token(_ row: UsagePeriodRow, _ model: String) -> String {
        (row.byModel.first { $0.model == model }?.tokens ?? 0).formatted()
    }

    private func displayPeriod(_ label: String) -> String {
        if label == "range" { return L10n.usageRangeTotal }
        return label
    }
}

private struct UsageChartPoint: Identifiable {
    var id: String { "\(period)|\(model)" }
    var period: String
    var model: String
    var tokens: Int
}

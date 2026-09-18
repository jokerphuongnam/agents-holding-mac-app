import Charts
import SwiftUI

struct UsageView: View {
    @EnvironmentObject private var appModel: AppModel

    @State private var worktreeSelection: String = "" // "" = all → adds worktree column/rows
    @State private var modelSelection: String = "" // "" = all → adds model columns
    @State private var rangeStart: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var rangeEnd: Date = Date()
    @State private var bucket: UsageBucket = .day
    @State private var chartKind: UsageChartKind = .donut

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
                    chartSection(report)
                    dynamicTable(report.table)
                    ledgerFooter(report)
                } else {
                    emptyState
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(usageTitle)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.back) { appModel.backFromUsage() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(L10n.reload) { reloadRaw() }
            }
        }
        .onAppear { reloadRaw() }
        .onChange(of: appModel.usageScope) { _, _ in reloadRaw() }
        .onChange(of: appModel.openCompany?.node.id) { _, _ in reloadRaw() }
        .onChange(of: worktreeSelection) { _, _ in reaggregate() }
        .onChange(of: modelSelection) { _, _ in reaggregate() }
        .onChange(of: rangeStart) { _, _ in reaggregate() }
        .onChange(of: rangeEnd) { _, _ in reaggregate() }
        .onChange(of: bucket) { _, _ in reaggregate() }
        .onChange(of: modelSelection) { _, _ in ensureChartKindFits() }
        .onChange(of: worktreeSelection) { _, _ in ensureChartKindFits() }
    }

    private var usageTitle: String {
        if let staff = appModel.usageScope.staffName {
            return "\(L10n.usage) · \(staff)"
        }
        switch appModel.usageScope {
        case .holdingAll: return "\(L10n.usage) · \(L10n.holding)"
        case .companySubtree: return "\(L10n.usage) · \(appModel.openCompany?.node.displayName ?? L10n.companies)"
        case .staff: return L10n.usage
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(usageTitle)
                .font(.title2.weight(.semibold))
            Text(scopeHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(L10n.usageHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var scopeHelpText: String {
        switch appModel.usageScope {
        case .holdingAll:
            return L10n.usageScopeHoldingHelp
        case .companySubtree:
            return L10n.usageScopeCompanyHelp
        case .staff(let name, let inHolding):
            return inHolding
                ? L10n.usageScopeStaffHoldingHelp(name)
                : L10n.usageScopeStaffCompanyHelp(name)
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.usageFilters)
                .font(.headline)

            // Time range
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.usageFrom).font(.caption).foregroundStyle(.secondary)
                    DatePicker("", selection: $rangeStart, displayedComponents: .date)
                        .labelsHidden()
                }
                Text("→").padding(.top, 16)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.usageTo).font(.caption).foregroundStyle(.secondary)
                    DatePicker("", selection: $rangeEnd, displayedComponents: .date)
                        .labelsHidden()
                }
                Spacer()
            }

            // Bucket — one tap switches table row grain
            Text(L10n.usageBucket).font(.caption).foregroundStyle(.secondary)
            Picker("", selection: $bucket) {
                Text(L10n.usageBucketDay).tag(UsageBucket.day)
                Text(L10n.usageBucketWeek).tag(UsageBucket.week)
                Text(L10n.usageBucketMonth).tag(UsageBucket.month)
                Text(L10n.usageBucketYear).tag(UsageBucket.year)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 480)

            // Worktree — All adds worktree column/rows; one value filters
            Picker(L10n.usageWorktree, selection: $worktreeSelection) {
                Text(L10n.usageWorktreeAll).tag("")
                ForEach(report?.availableWorktrees ?? distinctWorktrees(), id: \.self) { wt in
                    Text(wt).tag(wt)
                }
            }
            .frame(maxWidth: 420)

            // Model — All adds model columns; one value filters + single model column
            Picker(L10n.usageColModel, selection: $modelSelection) {
                Text(L10n.usageModelAll).tag("")
                Text("grok").tag("grok")
                Text("claude").tag("claude")
                Text("codex").tag("codex")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            HStack {
                Button(L10n.usagePreset7d) { applyPreset(days: 7) }
                Button(L10n.usagePreset30d) { applyPreset(days: 30) }
                Button(L10n.usagePreset90d) { applyPreset(days: 90) }
                Button(L10n.usagePresetAll) { applyAllDataRange() }
            }
            .buttonStyle(.borderless)

            Text(tableShapeHint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
    }

    private var tableShapeHint: String {
        var parts: [String] = [L10n.usageHintRowsPeriod]
        if worktreeSelection.isEmpty {
            parts.append(L10n.usageHintRowsWorktree)
        }
        if modelSelection.isEmpty {
            parts.append(L10n.usageHintColsModels)
        } else {
            parts.append(L10n.usageHintColsOneModel(modelSelection))
        }
        return parts.joined(separator: " · ")
    }

    private func summaryCards(_ report: UsageReport) -> some View {
        HStack(spacing: 12) {
            metricCard(L10n.usageRangeTotal, report.rangeTotal)
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

    // MARK: - Charts (follow same filters; kind switches)

    private var availableChartKinds: [UsageChartKind] {
        var kinds: [UsageChartKind] = [.bar, .line, .table]
        // Round/fan charts need a categorical share breakdown
        if modelSelection.isEmpty || worktreeSelection.isEmpty {
            kinds.insert(.donut, at: 0)
            kinds.insert(.pie, at: 1)
        }
        return kinds
    }

    private func ensureChartKindFits() {
        let allowed = availableChartKinds
        if !allowed.contains(chartKind) {
            chartKind = allowed.first ?? .bar
        }
    }

    private func chartSection(_ report: UsageReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.usageChart)
                .font(.headline)
            Text(L10n.usageChartHelp)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(L10n.usageChartKind, selection: $chartKind) {
                ForEach(availableChartKinds) { kind in
                    Text(chartKindTitle(kind)).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 520)

            Group {
                switch chartKind {
                case .donut:
                    shareChart(report, innerRatio: 0.48)
                case .pie:
                    shareChart(report, innerRatio: 0)
                case .bar:
                    timelineBarChart(report)
                case .line:
                    timelineLineChart(report)
                case .table:
                    Text(L10n.usageChartTableHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
        }
        .onAppear { ensureChartKindFits() }
    }

    private func chartKindTitle(_ kind: UsageChartKind) -> String {
        switch kind {
        case .donut: return L10n.usageChartDonut
        case .pie: return L10n.usageChartPie
        case .bar: return L10n.usageChartBar
        case .line: return L10n.usageChartLine
        case .table: return L10n.usageChartTable
        }
    }

    /// Donut/pie from active share dimension (models if All models; else worktrees if All worktrees).
    private func shareChart(_ report: UsageReport, innerRatio: CGFloat) -> some View {
        let slices: [UsageModelBreakdown] = {
            if modelSelection.isEmpty {
                return chartModels.map {
                    UsageModelBreakdown(model: $0, tokens: report.rangeByModel[$0] ?? 0)
                }
            }
            // Single model + all worktrees → share by worktree using table rows
            if worktreeSelection.isEmpty {
                return report.table.rows.map {
                    UsageModelBreakdown(
                        model: $0.cells["worktree"] ?? $0.id,
                        tokens: $0.numeric["total"] ?? 0
                    )
                }
            }
            return [
                UsageModelBreakdown(model: modelSelection, tokens: report.rangeTotal),
            ]
        }()

        let filtered = slices.filter { $0.tokens > 0 }
        return Chart(filtered) { slice in
            SectorMark(
                angle: .value(L10n.usageColTotal, slice.tokens),
                innerRadius: .ratio(innerRatio),
                angularInset: innerRatio == 0 ? 0.8 : 1.5
            )
            .foregroundStyle(by: .value(L10n.usageColModel, slice.model))
            .cornerRadius(innerRatio == 0 ? 0 : 3)
        }
        .applyModelColorScale(isModelShare: modelSelection.isEmpty)
        .frame(height: 240)
    }

    private func timelinePoints(_ report: UsageReport) -> [UsageChartPoint] {
        let models = modelSelection.isEmpty ? chartModels : [modelSelection]
        return report.chartBuckets.flatMap { bucket in
            models.map { model in
                UsageChartPoint(
                    period: bucket.period,
                    model: model,
                    tokens: bucket.byModel[model] ?? 0
                )
            }
        }
    }

    private func timelineBarChart(_ report: UsageReport) -> some View {
        Chart(timelinePoints(report)) { point in
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
        .frame(height: 260)
    }

    private func timelineLineChart(_ report: UsageReport) -> some View {
        Chart(timelinePoints(report)) { point in
            LineMark(
                x: .value(L10n.usageColPeriod, point.period),
                y: .value(L10n.usageColTotal, point.tokens)
            )
            .foregroundStyle(by: .value(L10n.usageColModel, point.model))
            .interpolationMethod(.catmullRom)
            PointMark(
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
        .frame(height: 260)
    }

    // MARK: - Single dynamic table

    private func dynamicTable(_ table: UsageDynamicTable) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.usageTable)
                .font(.headline)
            Text(L10n.usageTableHelp)
                .font(.caption)
                .foregroundStyle(.secondary)

            if table.rows.isEmpty {
                Text(L10n.usageNoRows)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow {
                            ForEach(table.columns) { col in
                                Text(columnTitle(col))
                                    .fontWeight(.semibold)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Divider().gridCellColumns(max(table.columns.count, 1))

                        ForEach(table.rows) { row in
                            GridRow {
                                ForEach(table.columns) { col in
                                    let raw = row.cells[col.key] ?? "—"
                                    if col.key == "period" || col.key == "worktree" {
                                        Text(raw)
                                    } else {
                                        Text((Int(raw) ?? 0).formatted()).monospacedDigit()
                                    }
                                }
                            }
                            .font(.callout)
                        }
                    }
                    .padding(12)
                }
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func columnTitle(_ col: UsageTableColumn) -> String {
        switch col.key {
        case "period": return L10n.usageColPeriod
        case "worktree": return L10n.usageWorktree
        case "total": return L10n.usageColTotal
        default: return col.title
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
        {"timestamp":"2026-09-18T10:00:00Z","company":"demo-analytics-lab-company","staff":"ceo","worktree":"feat-x","model":"grok","total_tokens":120}
        """
    }

    private func reloadRaw() {
        let companies = appModel.usageCompanyRoots()
        let includeHoldingLedger: URL? = {
            switch appModel.usageScope {
            case .holdingAll, .staff(_, true): return appModel.holdingPath
            case .companySubtree, .staff(_, false): return nil
            }
        }()
        let loaded = ledger.loadRawEvents(
            holdingRoot: includeHoldingLedger,
            companies: companies,
            staffName: appModel.usageScope.staffName
        )
        rawEvents = loaded.events
        ledgerPaths = loaded.paths
        let wts = Set(loaded.events.compactMap(\.worktree).filter { !$0.isEmpty })
        if !worktreeSelection.isEmpty, !wts.contains(worktreeSelection) {
            worktreeSelection = ""
        }
        reaggregate()
    }

    private func reaggregate() {
        let slug: String = {
            switch appModel.usageScope {
            case .holdingAll: return "holding"
            case .companySubtree: return appModel.openCompany?.node.slug ?? "company"
            case .staff(let name, _): return name
            }
        }()
        var start = rangeStart
        var end = rangeEnd
        if start > end { swap(&start, &end) }
        let query = UsageQuery(
            worktree: worktreeSelection.isEmpty ? nil : worktreeSelection,
            model: modelSelection.isEmpty ? nil : modelSelection,
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
}

private struct UsageChartPoint: Identifiable {
    var id: String { "\(period)|\(model)" }
    var period: String
    var model: String
    var tokens: Int
}

private extension View {
    @ViewBuilder
    func applyModelColorScale(isModelShare: Bool) -> some View {
        if isModelShare {
            self.chartForegroundStyleScale([
                "grok": Color.orange,
                "claude": Color.purple,
                "codex": Color.blue,
            ])
        } else {
            self
        }
    }
}

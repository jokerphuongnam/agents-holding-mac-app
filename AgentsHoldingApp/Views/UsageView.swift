import Charts
import SwiftUI

struct UsageView: View {
    @EnvironmentObject private var appModel: AppModel

    @State private var worktreeSelection: String = "" // "" = all worktrees (sum)
    /// Ticked models shown as rows (Sum always first). Empty until first load.
    @State private var selectedModels: Set<String> = []
    @State private var rangeStart: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var rangeEnd: Date = Date()
    @State private var bucket: UsageBucket = .day
    @State private var chartKind: UsageChartKind = .donut

    @State private var rawEvents: [UsageEvent] = []
    @State private var ledgerPaths: [URL] = []
    @State private var report: UsageReport?
    /// 0 → 1; chart values animate from zero to target.
    @State private var chartProgress: CGFloat = 0

    private let ledger = UsageLedgerService()
    /// Harness catalog (stable order); checklist uses models present in scope.
    @State private var harnessModels: [String] = []
    private let chartAnimation = Animation.easeOut(duration: 0.85)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                // Chart → Table → Filter (filters last so data is read first).
                if let report, report.filteredCount > 0 || report.eventCount > 0 {
                    summaryCards(report)
                    chartSection(report)
                    dynamicTable(report.table)
                    ledgerFooter(report)
                } else {
                    emptyState
                }
                filters
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
        .onChange(of: worktreeSelection) { _, _ in
            syncModelSelectionToScope(selectAllPresent: true)
            reaggregate()
            ensureChartKindFits()
        }
        .onChange(of: selectedModels) { _, _ in
            reaggregate()
            ensureChartKindFits()
        }
        .onChange(of: rangeStart) { _, _ in
            syncModelSelectionToScope(selectAllPresent: false)
            reaggregate()
        }
        .onChange(of: rangeEnd) { _, _ in
            syncModelSelectionToScope(selectAllPresent: false)
            reaggregate()
        }
        .onChange(of: bucket) { _, _ in reaggregate() }
        .onChange(of: chartKind) { _, _ in replayChartAnimation() }
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

            // Bucket grain — large segment chips (day / week / month / year)
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.usageBucket)
                    .font(.subheadline.weight(.semibold))
                bucketSegment
            }

            // Time range + presets
            VStack(alignment: .leading, spacing: 8) {
                Text("\(L10n.usageFrom) → \(L10n.usageTo)")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.usageFrom).font(.caption).foregroundStyle(.secondary)
                        DatePicker("", selection: $rangeStart, displayedComponents: .date)
                            .labelsHidden()
                            .controlSize(.large)
                    }
                    Text("→").padding(.top, 16)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.usageTo).font(.caption).foregroundStyle(.secondary)
                        DatePicker("", selection: $rangeEnd, displayedComponents: .date)
                            .labelsHidden()
                            .controlSize(.large)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 8) {
                        Button(L10n.usagePreset7d) { applyPreset(days: 7) }
                        Button(L10n.usagePreset30d) { applyPreset(days: 30) }
                        Button(L10n.usagePreset90d) { applyPreset(days: 90) }
                        Button(L10n.usagePresetAll) { applyAllDataRange() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Worktree — All = sum across worktrees; one value filters models to that worktree
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.usageWorktree)
                    .font(.subheadline.weight(.semibold))
                Picker("", selection: $worktreeSelection) {
                    Text(L10n.usageWorktreeAll).tag("")
                    ForEach(report?.availableWorktrees ?? distinctWorktrees(), id: \.self) { wt in
                        Text(wt).tag(wt)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 420, alignment: .leading)
            }

            // Models — multi-tick; rows = Sum + ticked models
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L10n.usageColModel)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(L10n.usageModelSelectAll) {
                        selectedModels = Set(modelsInCurrentScope)
                    }
                    .buttonStyle(.borderless)
                    .disabled(modelsInCurrentScope.isEmpty)
                    Button(L10n.usageModelClear) {
                        selectedModels = []
                    }
                    .buttonStyle(.borderless)
                    .disabled(selectedModels.isEmpty)
                }
                if modelsInCurrentScope.isEmpty {
                    Text(L10n.usageModelNoneInScope)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    FlowModelTicks(
                        models: modelsInCurrentScope,
                        selected: $selectedModels
                    )
                }
            }

            Text(tableShapeHint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
    }

    /// Big, readable Day / Week / Month / Year chips (segment-style).
    private var bucketSegment: some View {
        HStack(spacing: 0) {
            ForEach(UsageBucket.allCases) { option in
                let selected = bucket == option
                Button {
                    bucket = option
                } label: {
                    Text(bucketTitle(option))
                        .font(.body.weight(selected ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(selected ? Color.accentColor : Color.primary)
                        .background(selected ? Color.accentColor.opacity(0.18) : Color.clear)
                }
                .buttonStyle(.plain)
                if option != UsageBucket.allCases.last {
                    Divider().frame(height: 28)
                }
            }
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .frame(maxWidth: 520)
    }

    private func bucketTitle(_ bucket: UsageBucket) -> String {
        switch bucket {
        case .day: return L10n.usageBucketDay
        case .week: return L10n.usageBucketWeek
        case .month: return L10n.usageBucketMonth
        case .year: return L10n.usageBucketYear
        }
    }

    /// Models that appear under current worktree + date range (before tick filter).
    private var modelsInCurrentScope: [String] {
        if let report, !report.availableModels.isEmpty {
            return report.availableModels
        }
        return modelsPresentInRawScope()
    }

    private var tableShapeHint: String {
        let wt = worktreeSelection.isEmpty ? L10n.usageWorktreeAll : worktreeSelection
        let n = selectedModels.count
        return L10n.usageHintTableShape(wt, n)
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
        // Donut/pie when more than one model is ticked (share breakdown).
        if selectedModels.count > 1 {
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
            .animation(chartAnimation, value: chartProgress)
            .animation(chartAnimation, value: chartKind)
        }
        .onAppear {
            ensureChartKindFits()
            replayChartAnimation()
        }
    }

    private func replayChartAnimation() {
        chartProgress = 0
        // Next runloop so Charts sees the zero frame before animating up.
        DispatchQueue.main.async {
            withAnimation(chartAnimation) {
                chartProgress = 1
            }
        }
    }

    private func animatedTokens(_ value: Int) -> Double {
        Double(value) * Double(chartProgress)
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

    /// Donut/pie = share across ticked models.
    private func shareChart(_ report: UsageReport, innerRatio: CGFloat) -> some View {
        let models = orderedSelectedModels()
        let slices = models.map {
            UsageModelBreakdown(model: $0, tokens: report.rangeByModel[$0] ?? 0)
        }
        let filtered = slices.filter { $0.tokens > 0 }
        return Chart(filtered) { slice in
            SectorMark(
                angle: .value(L10n.usageColTotal, animatedTokens(slice.tokens)),
                innerRadius: .ratio(innerRatio),
                angularInset: innerRatio == 0 ? 0.8 : 1.5
            )
            .foregroundStyle(by: .value(L10n.usageColModel, slice.model))
            .cornerRadius(innerRatio == 0 ? 0 : 3)
        }
        .applyModelColorScale(isModelShare: true)
        .frame(height: 240)
    }

    private func timelinePoints(_ report: UsageReport) -> [UsageChartPoint] {
        let models = orderedSelectedModels()
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

    private func orderedSelectedModels() -> [String] {
        let scope = modelsInCurrentScope
        let picked = selectedModels
        let ordered = scope.filter { picked.contains($0) }
        if !ordered.isEmpty { return ordered }
        return Array(picked).sorted()
    }

    private func timelineBarChart(_ report: UsageReport) -> some View {
        let points = timelinePoints(report)
        let periodCount = Set(points.map(\.period)).count
        return Chart(points) { point in
            BarMark(
                x: .value(L10n.usageColPeriod, point.period),
                y: .value(L10n.usageColTotal, animatedTokens(point.tokens))
            )
            .foregroundStyle(by: .value(L10n.usageColModel, point.model))
        }
        .readableCategoryXAxis(periodCount: periodCount)
        .chartScrollableAxes(periodCount > 10 ? .horizontal : [])
        .chartXVisibleDomain(length: periodCount > 10 ? min(periodCount, 12) : periodCount)
        .frame(height: 320)
        .padding(.bottom, 8)
    }

    private func timelineLineChart(_ report: UsageReport) -> some View {
        let points = timelinePoints(report)
        let periodCount = Set(points.map(\.period)).count
        return Chart(points) { point in
            LineMark(
                x: .value(L10n.usageColPeriod, point.period),
                y: .value(L10n.usageColTotal, animatedTokens(point.tokens))
            )
            .foregroundStyle(by: .value(L10n.usageColModel, point.model))
            .interpolationMethod(.catmullRom)
            PointMark(
                x: .value(L10n.usageColPeriod, point.period),
                y: .value(L10n.usageColTotal, animatedTokens(point.tokens))
            )
            .foregroundStyle(by: .value(L10n.usageColModel, point.model))
        }
        .readableCategoryXAxis(periodCount: periodCount)
        .chartScrollableAxes(periodCount > 10 ? .horizontal : [])
        .chartXVisibleDomain(length: periodCount > 10 ? min(periodCount, 12) : periodCount)
        .frame(height: 320)
        .padding(.bottom, 8)
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
                                    cellView(row: row, column: col)
                                }
                            }
                            .font(row.id == "sum" ? .callout.weight(.semibold) : .callout)
                        }
                    }
                    .padding(12)
                }
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private func cellView(row: UsageTableRow, column: UsageTableColumn) -> some View {
        let raw = row.cells[column.key] ?? "—"
        switch column.key {
        case "label":
            Text(row.id == "sum" ? L10n.usageRowSum : raw)
        case "range_start", "range_end":
            Text(raw)
                .foregroundStyle(.secondary)
        default:
            Text((Int(raw) ?? 0).formatted()).monospacedDigit()
        }
    }

    private func columnTitle(_ col: UsageTableColumn) -> String {
        switch col.key {
        case "label": return L10n.usageColModel
        case "total": return L10n.usageColTotal
        case "range_start": return L10n.usageColRangeStart
        case "range_end": return L10n.usageColRangeEnd
        default:
            if col.key.hasPrefix("p:") {
                return String(col.key.dropFirst(2))
            }
            return col.title
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
        harnessModels = HarnessCatalog.vendorHarnesses(
            holdingRoot: includeHoldingLedger,
            companies: companies
        )
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
        syncModelSelectionToScope(selectAllPresent: selectedModels.isEmpty)
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
        let ordered = orderedSelectedModels()
        let query = UsageQuery(
            worktree: worktreeSelection.isEmpty ? nil : worktreeSelection,
            selectedModels: ordered,
            rangeStart: start,
            rangeEnd: end,
            bucket: bucket,
            availableModels: harnessModels
        )
        report = ledger.report(
            events: rawEvents,
            ledgerPaths: ledgerPaths,
            scopeLabel: slug,
            query: query
        )
        replayChartAnimation()
    }

    /// Models present for current worktree + date range from raw events.
    private func modelsPresentInRawScope() -> [String] {
        let cal = Calendar.current
        var start = rangeStart
        var end = rangeEnd
        if start > end { swap(&start, &end) }
        let dayStart = cal.startOfDay(for: start)
        let endExclusive = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end)) ?? end
        let known = harnessModels
        var models = Set<String>()
        for var e in rawEvents {
            e.rebucket(knownHarnesses: known)
            guard e.timestamp >= dayStart, e.timestamp < endExclusive else { continue }
            if !worktreeSelection.isEmpty, (e.worktree ?? "") != worktreeSelection { continue }
            models.insert(e.model)
        }
        // Prefer harness order, then leftovers.
        let ordered = known.filter { models.contains($0) }
        let rest = models.subtracting(known).sorted()
        return ordered + rest
    }

    /// When worktree changes → select all present. When range changes → keep ticks that still exist.
    private func syncModelSelectionToScope(selectAllPresent: Bool) {
        let present = modelsPresentInRawScope()
        let presentSet = Set(present)
        if selectAllPresent || selectedModels.isEmpty {
            selectedModels = presentSet
        } else {
            let kept = selectedModels.intersection(presentSet)
            selectedModels = kept.isEmpty ? presentSet : kept
        }
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

/// Checkbox chips for multi-select models.
private struct FlowModelTicks: View {
    let models: [String]
    @Binding var selected: Set<String>

    var body: some View {
        // Simple wrapping via LazyVGrid — stable for a handful of harness ids.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 110), spacing: 8)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(models, id: \.self) { model in
                Toggle(isOn: Binding(
                    get: { selected.contains(model) },
                    set: { on in
                        if on { selected.insert(model) } else { selected.remove(model) }
                    }
                )) {
                    Text(model)
                        .font(.callout)
                }
                .toggleStyle(.checkbox)
            }
        }
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

    /// Rotate / thin X labels so period columns stay readable.
    func readableCategoryXAxis(periodCount: Int) -> some View {
        let desired = periodCount <= 8 ? periodCount : min(periodCount, 10)
        return self.chartXAxis {
            AxisMarks(values: .automatic(desiredCount: max(desired, 1))) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label)
                            .font(.caption2)
                            .lineLimit(1)
                            .rotationEffect(.degrees(-55), anchor: .topTrailing)
                            .offset(x: -4, y: 10)
                            .frame(width: 64, alignment: .trailing)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.padding(.bottom, 36)
        }
    }
}

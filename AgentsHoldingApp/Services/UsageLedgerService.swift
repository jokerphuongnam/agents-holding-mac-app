import Foundation

/// Reads usage ledgers and builds **one** dynamic table from active filters.
///
/// Table shape:
/// - Rows: Sum (first) + one row per selected model
/// - Columns: Model | Total | Range start | …buckets… | Range end
struct UsageLedgerService {
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private let rangeLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = .current
        f.timeZone = .current
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    func loadRawEvents(
        holdingRoot: URL?,
        companies: [(slug: String, root: URL)],
        staffName: String?
    ) -> (events: [UsageEvent], paths: [URL]) {
        var paths: [URL] = []
        var events: [UsageEvent] = []

        if let holdingRoot {
            let package = holdingPackage(from: holdingRoot)
            let files = ledgerFiles(under: package.appendingPathComponent("cache/usage"))
            paths.append(contentsOf: files)
            for path in files {
                events.append(contentsOf: loadFile(path, defaultCompany: nil))
            }
        }

        for company in companies {
            let files = ledgerFiles(under: company.root.appendingPathComponent("cache/usage"))
            paths.append(contentsOf: files)
            for path in files {
                events.append(contentsOf: loadFile(path, defaultCompany: company.slug))
            }
        }

        if let staffName, !staffName.isEmpty {
            events = events.filter { ($0.staff ?? "") == staffName }
        }

        return (events, paths)
    }

    func report(
        events allEvents: [UsageEvent],
        ledgerPaths: [URL],
        scopeLabel: String,
        query: UsageQuery
    ) -> UsageReport {
        let cal = Calendar.current
        let start = cal.startOfDay(for: query.rangeStart)
        let endExclusive = cal.date(
            byAdding: .day,
            value: 1,
            to: cal.startOfDay(for: query.rangeEnd)
        ) ?? query.rangeEnd

        let known = query.availableModels.isEmpty
            ? Array(Set(allEvents.map(\.model))).sorted()
            : query.availableModels

        var normalized = allEvents
        for i in normalized.indices {
            normalized[i].rebucket(knownHarnesses: known)
        }

        let dataStart = normalized.map(\.timestamp).min()
        let dataEnd = normalized.map(\.timestamp).max()
        let worktrees = Set(normalized.compactMap { $0.worktree }.filter { !$0.isEmpty }).sorted()

        var filtered = normalized.filter { $0.timestamp >= start && $0.timestamp < endExclusive }
        if let wt = query.worktree, !wt.isEmpty {
            filtered = filtered.filter { ($0.worktree ?? "") == wt }
        }

        let selected = query.selectedModels
        let selectedSet = Set(selected)
        if !selectedSet.isEmpty {
            filtered = filtered.filter { selectedSet.contains($0.model) }
        } else {
            filtered = []
        }

        // Models present under current worktree+range (before model tick filter) for UI checklist.
        var scopeFiltered = normalized.filter { $0.timestamp >= start && $0.timestamp < endExclusive }
        if let wt = query.worktree, !wt.isEmpty {
            scopeFiltered = scopeFiltered.filter { ($0.worktree ?? "") == wt }
        }
        let modelsInScope = Array(Set(scopeFiltered.map(\.model))).sorted()

        let table = buildTable(
            events: filtered,
            selectedModels: selected,
            bucket: query.bucket,
            rangeStart: start,
            rangeEndInclusive: cal.startOfDay(for: query.rangeEnd),
            endExclusive: endExclusive,
            calendar: cal
        )

        let chartBuckets = buildChartBuckets(events: filtered, bucket: query.bucket, calendar: cal)
        var rangeByModel: [String: Int] = [:]
        var rangeTotal = 0
        for e in filtered {
            rangeTotal += e.totalTokens
            rangeByModel[e.model, default: 0] += e.totalTokens
        }

        return UsageReport(
            scopeLabel: scopeLabel,
            eventCount: allEvents.count,
            filteredCount: filtered.count,
            availableWorktrees: worktrees,
            availableModels: modelsInScope.isEmpty ? known : modelsInScope,
            dataStart: dataStart,
            dataEnd: dataEnd,
            table: table,
            chartBuckets: chartBuckets,
            rangeByModel: rangeByModel,
            rangeTotal: rangeTotal,
            ledgerPaths: ledgerPaths
        )
    }

    // MARK: - Dynamic table (Sum + models × time buckets)

    private func buildTable(
        events: [UsageEvent],
        selectedModels: [String],
        bucket: UsageBucket,
        rangeStart: Date,
        rangeEndInclusive: Date,
        endExclusive: Date,
        calendar: Calendar
    ) -> UsageDynamicTable {
        let periods = periodKeys(
            from: rangeStart,
            to: endExclusive,
            bucket: bucket,
            calendar: calendar
        )
        let startLabel = rangeLabelFormatter.string(from: rangeStart)
        let endLabel = rangeLabelFormatter.string(from: rangeEndInclusive)

        var columns: [UsageTableColumn] = [
            UsageTableColumn(key: "label", title: "model"),
            UsageTableColumn(key: "total", title: "total"),
            UsageTableColumn(key: "range_start", title: "range_start"),
        ]
        for p in periods {
            columns.append(UsageTableColumn(key: "p:\(p)", title: p))
        }
        columns.append(UsageTableColumn(key: "range_end", title: "range_end"))

        // Aggregate: model → period → tokens
        var byModelPeriod: [String: [String: Int]] = [:]
        var byModelTotal: [String: Int] = [:]
        var sumByPeriod: [String: Int] = [:]
        var sumTotal = 0

        for e in events {
            let p = bucketKey(for: e.timestamp, bucket: bucket, calendar: calendar)
            byModelPeriod[e.model, default: [:]][p, default: 0] += e.totalTokens
            byModelTotal[e.model, default: 0] += e.totalTokens
            sumByPeriod[p, default: 0] += e.totalTokens
            sumTotal += e.totalTokens
        }

        func makeRow(id: String, label: String, total: Int, periodMap: [String: Int]) -> UsageTableRow {
            var cells: [String: String] = [
                "label": label,
                "total": "\(total)",
                "range_start": startLabel,
                "range_end": endLabel,
            ]
            var numeric: [String: Int] = ["total": total]
            for p in periods {
                let key = "p:\(p)"
                let n = periodMap[p] ?? 0
                cells[key] = "\(n)"
                numeric[key] = n
            }
            return UsageTableRow(id: id, cells: cells, sortKey: id, numeric: numeric)
        }

        var rows: [UsageTableRow] = [
            makeRow(id: "sum", label: "Sum", total: sumTotal, periodMap: sumByPeriod),
        ]
        for model in selectedModels {
            rows.append(
                makeRow(
                    id: "m:\(model)",
                    label: model,
                    total: byModelTotal[model] ?? 0,
                    periodMap: byModelPeriod[model] ?? [:]
                )
            )
        }

        return UsageDynamicTable(columns: columns, rows: rows)
    }

    /// Every bucket key from range start through end (inclusive of last day).
    private func periodKeys(
        from start: Date,
        to endExclusive: Date,
        bucket: UsageBucket,
        calendar: Calendar
    ) -> [String] {
        var keys: [String] = []
        var seen = Set<String>()
        var cursor = start
        // Cap walks so a huge range cannot freeze the UI.
        var steps = 0
        let maxSteps = 3700
        while cursor < endExclusive, steps < maxSteps {
            let key = bucketKey(for: cursor, bucket: bucket, calendar: calendar)
            if seen.insert(key).inserted {
                keys.append(key)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            steps += 1
        }
        return keys
    }

    private func buildChartBuckets(
        events: [UsageEvent],
        bucket: UsageBucket,
        calendar: Calendar
    ) -> [UsageChartBucket] {
        var map: [String: [UsageEvent]] = [:]
        for e in events {
            let k = bucketKey(for: e.timestamp, bucket: bucket, calendar: calendar)
            map[k, default: []].append(e)
        }
        return map.keys.sorted().map { key in
            var byModel: [String: Int] = [:]
            var total = 0
            for e in map[key] ?? [] {
                total += e.totalTokens
                byModel[e.model, default: 0] += e.totalTokens
            }
            return UsageChartBucket(period: key, byModel: byModel, total: total)
        }
    }

    private func bucketKey(for date: Date, bucket: UsageBucket, calendar: Calendar) -> String {
        switch bucket {
        case .day:
            return dayFormatter.string(from: date)
        case .week:
            let week = calendar.component(.weekOfYear, from: date)
            let year = calendar.component(.yearForWeekOfYear, from: date)
            return String(format: "%04d-W%02d", year, week)
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: date)
            return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
        case .year:
            return String(format: "%04d", calendar.component(.year, from: date))
        }
    }

    // MARK: - Load files

    private func holdingPackage(from holdingRoot: URL) -> URL {
        let nested = holdingRoot.appendingPathComponent("holding")
        if FileManager.default.fileExists(atPath: nested.appendingPathComponent("cache").path)
            || FileManager.default.fileExists(atPath: nested.appendingPathComponent("system").path) {
            return nested
        }
        return holdingRoot
    }

    private func ledgerFiles(under dir: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: dir.path),
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return [] }
        return names
            .filter { $0.hasSuffix(".jsonl") || $0 == "usage.json" || $0.hasSuffix(".json") }
            .map { dir.appendingPathComponent($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func loadFile(_ url: URL, defaultCompany: String?) -> [UsageEvent] {
        guard let data = FileManager.default.contents(atPath: url.path),
              let text = String(data: data, encoding: .utf8)
        else { return [] }

        if url.pathExtension == "jsonl" || url.lastPathComponent.hasSuffix(".jsonl") {
            return text.split(whereSeparator: \.isNewline).compactMap { line -> UsageEvent? in
                let s = String(line).trimmingCharacters(in: .whitespaces)
                guard !s.isEmpty, let d = s.data(using: .utf8),
                      var event = try? JSONDecoder().decode(UsageEvent.self, from: d)
                else { return nil }
                if event.company == nil { event.company = defaultCompany }
                return event
            }
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let total = intValue(obj["totalTokens"] ?? obj["total_tokens"]) ?? 0
        let input = intValue(obj["inputTokens"] ?? obj["input_tokens"]) ?? 0
        let output = intValue(obj["outputTokens"] ?? obj["output_tokens"]) ?? 0
        guard total > 0 || input + output > 0 else { return [] }
        let model = stringValue(obj["model"]) ?? stringValue(obj["vendor"]) ?? "grok"
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return [
            UsageEvent(
                timestamp: mtime,
                company: defaultCompany ?? stringValue(obj["company"]),
                staff: stringValue(obj["role"]) ?? stringValue(obj["staff"]),
                worktree: stringValue(obj["worktree"]),
                model: model,
                launchMode: stringValue(obj["launch_mode"]),
                inputTokens: input,
                outputTokens: output,
                totalTokens: total > 0 ? total : input + output
            ),
        ]
    }

    private func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) }
        return nil
    }

    private func stringValue(_ any: Any?) -> String? {
        if let s = any as? String, !s.isEmpty { return s }
        return nil
    }
}

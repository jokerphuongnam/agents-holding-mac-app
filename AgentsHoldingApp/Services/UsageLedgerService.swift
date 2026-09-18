import Foundation

/// Reads usage ledgers and builds **one** dynamic table from active filters.
struct UsageLedgerService {
    private let primaryModels = ["grok", "claude", "codex"]

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
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

        let dataStart = allEvents.map(\.timestamp).min()
        let dataEnd = allEvents.map(\.timestamp).max()
        let worktrees = Set(allEvents.compactMap { $0.worktree }.filter { !$0.isEmpty }).sorted()

        var filtered = allEvents.filter { $0.timestamp >= start && $0.timestamp < endExclusive }
        if let wt = query.worktree, !wt.isEmpty {
            filtered = filtered.filter { ($0.worktree ?? "") == wt }
        }
        if let model = query.model, !model.isEmpty {
            filtered = filtered.filter { $0.model == model }
        }

        let splitWorktree = query.worktree == nil || query.worktree?.isEmpty == true
        let splitModelColumns = query.model == nil || query.model?.isEmpty == true

        let table = buildTable(
            events: filtered,
            bucket: query.bucket,
            splitWorktree: splitWorktree,
            splitModelColumns: splitModelColumns,
            singleModel: query.model,
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
            dataStart: dataStart,
            dataEnd: dataEnd,
            table: table,
            chartBuckets: chartBuckets,
            rangeByModel: rangeByModel,
            rangeTotal: rangeTotal,
            ledgerPaths: ledgerPaths
        )
    }

    // MARK: - Dynamic table

    private func buildTable(
        events: [UsageEvent],
        bucket: UsageBucket,
        splitWorktree: Bool,
        splitModelColumns: Bool,
        singleModel: String?,
        calendar: Calendar
    ) -> UsageDynamicTable {
        var columns: [UsageTableColumn] = [
            UsageTableColumn(key: "period", title: "period"),
        ]
        if splitWorktree {
            columns.append(UsageTableColumn(key: "worktree", title: "worktree"))
        }
        columns.append(UsageTableColumn(key: "total", title: "total"))
        if splitModelColumns {
            for m in primaryModels {
                columns.append(UsageTableColumn(key: m, title: m))
            }
        } else if let m = singleModel, !m.isEmpty {
            columns.append(UsageTableColumn(key: m, title: m))
        }

        // Group key → events
        var groups: [String: [UsageEvent]] = [:]
        for e in events {
            let period = bucketKey(for: e.timestamp, bucket: bucket, calendar: calendar)
            let wt = splitWorktree ? ((e.worktree?.isEmpty == false) ? (e.worktree ?? "") : "(none)") : ""
            let key = splitWorktree ? "\(period)|\(wt)" : period
            groups[key, default: []].append(e)
        }

        var rows: [UsageTableRow] = []
        for key in groups.keys.sorted(by: >) {
            let evs = groups[key] ?? []
            let period: String
            let worktree: String
            if splitWorktree, let bar = key.firstIndex(of: "|") {
                period = String(key[..<bar])
                worktree = String(key[key.index(after: bar)...])
            } else {
                period = key
                worktree = ""
            }

            var byModel: [String: Int] = [:]
            var total = 0
            for e in evs {
                total += e.totalTokens
                byModel[e.model, default: 0] += e.totalTokens
            }

            var cells: [String: String] = [
                "period": period,
                "total": "\(total)",
            ]
            var numeric: [String: Int] = ["total": total]
            if splitWorktree {
                cells["worktree"] = worktree
            }
            if splitModelColumns {
                for m in primaryModels {
                    let n = byModel[m] ?? 0
                    cells[m] = "\(n)"
                    numeric[m] = n
                }
            } else if let m = singleModel, !m.isEmpty {
                let n = byModel[m] ?? total
                cells[m] = "\(n)"
                numeric[m] = n
            }

            rows.append(
                UsageTableRow(
                    id: key,
                    cells: cells,
                    sortKey: key,
                    numeric: numeric
                )
            )
        }

        rows.sort { $0.sortKey > $1.sortKey }
        return UsageDynamicTable(columns: columns, rows: rows)
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

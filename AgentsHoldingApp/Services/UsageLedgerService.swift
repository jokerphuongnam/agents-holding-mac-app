import Foundation

/// Reads usage ledgers and aggregates by date range, worktree, and bucket.
struct UsageLedgerService {
    private let modelsOrder = ["grok", "claude", "codex", "merge", "other"]

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
        companyRoot: URL?,
        companySlug: String?
    ) -> (events: [UsageEvent], paths: [URL]) {
        var paths: [URL] = []
        var events: [UsageEvent] = []

        if let holdingRoot {
            let package = holdingPackage(from: holdingRoot)
            paths.append(contentsOf: ledgerFiles(under: package.appendingPathComponent("cache/usage")))
        }
        if let companyRoot {
            paths.append(contentsOf: ledgerFiles(under: companyRoot.appendingPathComponent("cache/usage")))
        }

        for path in paths {
            events.append(contentsOf: loadFile(path, defaultCompany: companySlug))
        }

        if let companySlug {
            events = events.filter { event in
                guard let c = event.company, !c.isEmpty else { return true }
                return c == companySlug || c == companySlug.replacingOccurrences(of: "-company", with: "")
            }
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

        var worktrees = Set(allEvents.compactMap { $0.worktree }.filter { !$0.isEmpty })
        worktrees = Set(worktrees.map { $0 })

        var filtered = allEvents.filter { $0.timestamp >= start && $0.timestamp < endExclusive }
        if let wt = query.worktree, !wt.isEmpty {
            filtered = filtered.filter { ($0.worktree ?? "") == wt }
        }

        let rangeTotal = periodRow(label: "range", events: filtered)
        let buckets = bucketRows(events: filtered, bucket: query.bucket, calendar: cal)

        return UsageReport(
            scopeLabel: scopeLabel,
            eventCount: allEvents.count,
            filteredCount: filtered.count,
            availableWorktrees: worktrees.sorted(),
            dataStart: dataStart,
            dataEnd: dataEnd,
            rangeTotal: rangeTotal,
            buckets: buckets,
            ledgerPaths: ledgerPaths
        )
    }

    // MARK: - Bucketing

    private func bucketRows(events: [UsageEvent], bucket: UsageBucket, calendar: Calendar) -> [UsagePeriodRow] {
        var map: [String: [UsageEvent]] = [:]
        for e in events {
            let key = bucketKey(for: e.timestamp, bucket: bucket, calendar: calendar)
            map[key, default: []].append(e)
        }
        return map.keys.sorted(by: >).map { periodRow(label: $0, events: map[$0] ?? []) }
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
            let year = calendar.component(.year, from: date)
            return String(format: "%04d", year)
        }
    }

    private func periodRow(label: String, events: [UsageEvent]) -> UsagePeriodRow {
        var buckets: [String: Int] = [:]
        var total = 0
        for e in events {
            total += e.totalTokens
            buckets[e.model, default: 0] += e.totalTokens
        }
        let ensured: [UsageModelBreakdown] = ["grok", "claude", "codex"].map { m in
            UsageModelBreakdown(model: m, tokens: buckets[m] ?? 0)
        } + modelsOrder
            .filter { !["grok", "claude", "codex"].contains($0) }
            .compactMap { m in
                let n = buckets[m] ?? 0
                return n > 0 ? UsageModelBreakdown(model: m, tokens: n) : nil
            }
        return UsagePeriodRow(label: label, total: total, byModel: ensured)
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

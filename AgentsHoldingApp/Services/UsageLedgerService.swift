import Foundation

/// Reads usage ledgers from holding / company `cache/usage/`.
///
/// Expected files (any that exist are merged):
/// - `cache/usage/events.jsonl` — one JSON object per line (`UsageEvent`)
/// - `cache/usage/*.jsonl`
/// - `cache/usage/usage.json` — single cumulative snapshot (optional)
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

    func loadReport(
        holdingRoot: URL?,
        companyRoot: URL?,
        companySlug: String?
    ) -> UsageReport {
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

        let scope = companySlug ?? "holding"
        return aggregate(events: events, scopeLabel: scope, ledgerPaths: paths)
    }

    // MARK: - Load

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

        // Single usage.json snapshot → one synthetic event (today / file mtime).
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

    // MARK: - Aggregate

    private func aggregate(events: [UsageEvent], scopeLabel: String, ledgerPaths: [URL]) -> UsageReport {
        let cal = Calendar.current
        let todayKey = dayFormatter.string(from: Date())

        let allTime = periodRow(label: "all-time", events: events)
        let todayEvents = events.filter { dayFormatter.string(from: $0.timestamp) == todayKey }
        let today = periodRow(label: "today", events: todayEvents)

        var byDayMap: [String: [UsageEvent]] = [:]
        for e in events {
            let k = dayFormatter.string(from: e.timestamp)
            byDayMap[k, default: []].append(e)
        }
        let byDay = byDayMap.keys.sorted(by: >).map { key in
            periodRow(label: key, events: byDayMap[key] ?? [])
        }

        return UsageReport(
            scopeLabel: scopeLabel,
            eventCount: events.count,
            allTime: allTime,
            today: today,
            byDay: byDay,
            ledgerPaths: ledgerPaths
        )
    }

    private func periodRow(label: String, events: [UsageEvent]) -> UsagePeriodRow {
        var buckets: [String: Int] = [:]
        var total = 0
        for e in events {
            total += e.totalTokens
            buckets[e.model, default: 0] += e.totalTokens
        }
        let breakdown = modelsOrder.compactMap { model -> UsageModelBreakdown? in
            let n = buckets[model] ?? 0
            guard n > 0 || modelsOrder.prefix(3).contains(model) else { return nil }
            return UsageModelBreakdown(model: model, tokens: n)
        }
        // Always show grok/claude/codex columns even if 0
        let ensured: [UsageModelBreakdown] = ["grok", "claude", "codex"].map { m in
            UsageModelBreakdown(model: m, tokens: buckets[m] ?? 0)
        } + breakdown.filter { !["grok", "claude", "codex"].contains($0.model) && $0.tokens > 0 }

        return UsagePeriodRow(label: label, total: total, byModel: ensured)
    }
}

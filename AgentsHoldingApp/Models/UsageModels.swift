import Foundation

/// One usage event in `cache/usage/events.jsonl` (company or holding).
struct UsageEvent: Hashable, Codable {
    var timestamp: Date
    var company: String?
    var staff: String?
    var worktree: String?
    var model: String
    var launchMode: String?
    var inputTokens: Int
    var outputTokens: Int
    var totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case timestamp, company, staff, worktree, model
        case launchMode = "launch_mode"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }

    init(
        timestamp: Date,
        company: String? = nil,
        staff: String? = nil,
        worktree: String? = nil,
        model: String,
        launchMode: String? = nil,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        totalTokens: Int
    ) {
        self.timestamp = timestamp
        self.company = company
        self.staff = staff
        self.worktree = worktree
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.launchMode = launchMode
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens > 0 ? totalTokens : (inputTokens + outputTokens)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .timestamp) {
            timestamp = ISO8601DateFormatter().date(from: s)
                ?? ISO8601DateFormatter.fractional.date(from: s)
                ?? Date()
        } else if let t = try? c.decode(Double.self, forKey: .timestamp) {
            timestamp = Date(timeIntervalSince1970: t)
        } else {
            timestamp = Date()
        }
        company = try c.decodeIfPresent(String.self, forKey: .company)
        staff = try c.decodeIfPresent(String.self, forKey: .staff)
        worktree = try c.decodeIfPresent(String.self, forKey: .worktree)
        // Keep raw-ish model; re-bucket later with discovered harness list.
        model = (try c.decodeIfPresent(String.self, forKey: .model) ?? "other")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        launchMode = try c.decodeIfPresent(String.self, forKey: .launchMode)
        inputTokens = try c.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        outputTokens = try c.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        let total = try c.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
        totalTokens = total > 0 ? total : (inputTokens + outputTokens)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ISO8601DateFormatter.fractional.string(from: timestamp), forKey: .timestamp)
        try c.encodeIfPresent(company, forKey: .company)
        try c.encodeIfPresent(staff, forKey: .staff)
        try c.encodeIfPresent(worktree, forKey: .worktree)
        try c.encode(model, forKey: .model)
        try c.encodeIfPresent(launchMode, forKey: .launchMode)
        try c.encode(inputTokens, forKey: .inputTokens)
        try c.encode(outputTokens, forKey: .outputTokens)
        try c.encode(totalTokens, forKey: .totalTokens)
    }

    mutating func rebucket(knownHarnesses: [String]) {
        model = HarnessCatalog.bucket(model, known: knownHarnesses)
    }
}

enum UsageBucket: String, CaseIterable, Identifiable {
    case day, week, month, year
    var id: String { rawValue }
}

/// Chart presentation — switches with filters; only suitable kinds are offered.
enum UsageChartKind: String, CaseIterable, Identifiable {
    case donut // tròn
    case pie // quạt
    case bar
    case line
    case table

    var id: String { rawValue }
}

/// "" = all models
typealias UsageModelFilter = String

struct UsageQuery: Equatable {
    var worktree: String? // nil/"" = all → split rows by worktree
    var model: String? // nil/"" = all → add model columns
    var rangeStart: Date
    var rangeEnd: Date
    var bucket: UsageBucket
    /// Discovered from system/harness/*.toml — drives columns & filters.
    var availableModels: [String]
}

struct UsageModelBreakdown: Hashable, Identifiable {
    var id: String { model }
    var model: String
    var tokens: Int
}

struct UsageTableColumn: Hashable, Identifiable {
    var id: String { key }
    var key: String
    var title: String
}

struct UsageTableRow: Hashable, Identifiable {
    var id: String
    /// Display cells keyed by column.key (period, worktree, total, grok, …)
    var cells: [String: String]
    var sortKey: String
    var numeric: [String: Int]
}

struct UsageDynamicTable: Hashable {
    var columns: [UsageTableColumn]
    var rows: [UsageTableRow]
}

struct UsageChartBucket: Hashable, Identifiable {
    var id: String { period }
    var period: String
    var byModel: [String: Int]
    var total: Int
}

struct UsageReport: Hashable {
    var scopeLabel: String
    var eventCount: Int
    var filteredCount: Int
    var availableWorktrees: [String]
    /// Harness ids discovered for this scope (not hardcoded).
    var availableModels: [String]
    var dataStart: Date?
    var dataEnd: Date?
    var table: UsageDynamicTable
    /// For charts (same filtered events, bucketed by time only).
    var chartBuckets: [UsageChartBucket]
    var rangeByModel: [String: Int]
    var rangeTotal: Int
    var ledgerPaths: [URL]
}

extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

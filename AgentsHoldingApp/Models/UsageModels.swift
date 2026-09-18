import Foundation

/// One usage event in `cache/usage/events.jsonl` (company or holding).
struct UsageEvent: Hashable, Codable {
    var timestamp: Date
    var company: String?
    var staff: String?
    var worktree: String?
    /// Vendor bucket: grok | claude | codex | merge | other
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
        self.model = Self.normalizeModel(model)
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
        model = Self.normalizeModel(try c.decodeIfPresent(String.self, forKey: .model) ?? "other")
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

    static func normalizeModel(_ raw: String) -> String {
        let m = raw.lowercased()
        if m.contains("grok") { return "grok" }
        if m.contains("claude") || m.contains("sonnet") || m.contains("opus") || m.contains("haiku") {
            return "claude"
        }
        if m.contains("codex") || m.contains("gpt") || m.contains("o1") || m.contains("o3") {
            return "codex"
        }
        if m == "merge" { return "merge" }
        return "other"
    }
}

enum UsageBucket: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }
}

struct UsageQuery: Equatable {
    var scopeCompany: Bool
    /// nil = all worktrees
    var worktree: String?
    var rangeStart: Date
    var rangeEnd: Date
    var bucket: UsageBucket
}

struct UsageModelBreakdown: Hashable, Identifiable {
    var id: String { model }
    var model: String
    var tokens: Int
}

struct UsagePeriodRow: Hashable, Identifiable {
    var id: String { label }
    var label: String
    var total: Int
    var byModel: [UsageModelBreakdown]
}

struct UsageReport: Hashable {
    var scopeLabel: String
    var eventCount: Int
    var filteredCount: Int
    var availableWorktrees: [String]
    /// Min/max timestamps in loaded ledgers (for default range).
    var dataStart: Date?
    var dataEnd: Date?
    var rangeTotal: UsagePeriodRow
    var buckets: [UsagePeriodRow]
    var ledgerPaths: [URL]
}

extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

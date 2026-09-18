# Usage ledger schema

The Usage screen reads JSONL (and optional snapshot JSON) from:

- `<holding>/cache/usage/*.jsonl` (or `usage.json`)
- `<company>/.agents/<slug>/cache/usage/*.jsonl`

## `events.jsonl` (preferred)

One JSON object per line:

```json
{"timestamp":"2026-09-18T10:00:00Z","company":"desk-garden-company","staff":"ceo","model":"grok","launch_mode":"grok","input_tokens":100,"output_tokens":20,"total_tokens":120}
{"timestamp":"2026-09-18T11:00:00Z","company":"desk-garden-company","staff":"ba-user","model":"claude","launch_mode":"merge","total_tokens":50}
```

| Field | Notes |
| --- | --- |
| `timestamp` | ISO-8601 |
| `company` | Company slug (optional for holding-wide) |
| `staff` | Staff role name |
| `model` | Normalized to `grok` / `claude` / `codex` / `other` (substring match) |
| `launch_mode` | Optional: `grok` / `claude` / `codex` / `merge` |
| `total_tokens` | If omitted, `input_tokens + output_tokens` |

## UI tables

1. **All time** — sum since first event (+ columns grok / claude / codex)
2. **Today** — calendar day in local timezone
3. **By day** — one row per `yyyy-MM-dd`

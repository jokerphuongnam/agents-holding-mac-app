# Usage ledger schema

The Usage screen reads JSONL (and optional snapshot JSON) from:

- `<holding>/cache/usage/*.jsonl` (or `usage.json`)
- `<company>/.agents/<slug>/cache/usage/*.jsonl`

## `events.jsonl` (preferred)

One JSON object per line:

```json
{"timestamp":"2026-09-18T10:00:00Z","company":"desk-garden-company","staff":"ceo","worktree":"feat-x","model":"grok","launch_mode":"grok","input_tokens":100,"output_tokens":20,"total_tokens":120}
{"timestamp":"2026-09-18T11:00:00Z","company":"desk-garden-company","staff":"ba-user","worktree":"feat-x","model":"claude","launch_mode":"merge","total_tokens":50}
```

| Field | Notes |
| --- | --- |
| `timestamp` | ISO-8601 |
| `company` | Company slug (optional for holding-wide) |
| `staff` | Staff role name |
| `worktree` | Worktree name (optional; filterable in UI) |
| `model` | Bucketed against **discovered** `system/harness/*.toml` ids (e.g. grok, claude, codex, deepseek); unknown → `other` |
| `launch_mode` | Optional: `grok` / `claude` / `codex` / `merge` |
| `total_tokens` | If omitted, `input_tokens + output_tokens` |

## UI analytics

Filters (combinable):

- **Scope** — holding vs open company  
- **From / To** — inclusive calendar date range  
- **Worktree** — one worktree or all  
- **Bucket** — day / week / month / year  

Tables:

1. **Range total** — sum in the selected range (+ grok / claude / codex)  
2. **Bucket table** — one row per day/week/month/year in range (+ model columns)  

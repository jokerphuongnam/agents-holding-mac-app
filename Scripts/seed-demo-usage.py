#!/usr/bin/env python3
"""Seed a virtual multi-day usage ledger for a company (no live LLM calls).

Simulates CEO → BA / PO / QC / CTO / git hops across worktrees and models.

  python3 Scripts/seed-demo-usage.py \\
    --company-path ~/Documents/Agents/demo-analytics-lab/.agents/demo-analytics-lab-company

Writes: <company>/cache/usage/events.jsonl
"""

from __future__ import annotations

import argparse
import json
import random
from datetime import datetime, timedelta, timezone
from pathlib import Path

# staff → preferred models (merge resolves to these vendors)
STAFF_MODELS: dict[str, list[tuple[str, str]]] = {
    # (model, launch_mode)
    "ceo": [("grok", "grok"), ("grok", "merge")],
    "cto": [("claude", "claude"), ("claude", "merge")],
    "ba-lead": [("codex", "codex"), ("claude", "merge")],
    "ba-user": [("claude", "claude"), ("claude", "merge"), ("grok", "merge")],
    "po-lead": [("codex", "codex"), ("codex", "merge")],
    "po-new": [("codex", "codex"), ("codex", "merge")],
    "qc-lead": [("claude", "claude"), ("grok", "merge")],
    "git": [("codex", "codex"), ("grok", "grok")],
}

WORKTREES = [
    "feat-onboarding",
    "feat-usage-charts",
    "fix-login-race",
    "chore-deps",
]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--company-path", required=True, type=Path)
    ap.add_argument("--days", type=int, default=45)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--company-slug", default="demo-analytics-lab-company")
    args = ap.parse_args()

    company = args.company_path.expanduser().resolve()
    if not company.is_dir():
        print(f"error: missing company {company}", flush=True)
        return 1

    rng = random.Random(args.seed)
    out_dir = company / "cache" / "usage"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "events.jsonl"

    # Discover staffs from agents.tsv if present
    agents_tsv = company / "system/skills/defaults/marlin-hop/data/agents.tsv"
    staffs = list(STAFF_MODELS.keys())
    if agents_tsv.is_file():
        lines = agents_tsv.read_text(encoding="utf-8").splitlines()
        if lines:
            header = lines[0].split("\t")
            if "name" in header:
                idx = header.index("name")
                names = [ln.split("\t")[idx] for ln in lines[1:] if ln.strip()]
                staffs = [n for n in names if n in STAFF_MODELS] or names

    now = datetime.now(timezone.utc).replace(hour=12, minute=0, second=0, microsecond=0)
    events: list[dict] = []

    for day_i in range(args.days):
        day = now - timedelta(days=args.days - 1 - day_i)
        # Weekend quieter
        weekend = day.weekday() >= 5
        sessions = rng.randint(2, 4) if weekend else rng.randint(6, 14)
        for _ in range(sessions):
            staff = rng.choice(staffs)
            models = STAFF_MODELS.get(staff) or [("grok", "grok")]
            model, launch = rng.choice(models)
            worktree = rng.choice(WORKTREES)
            # Token volume by role
            base = {
                "ceo": (8_000, 25_000),
                "ba-user": (5_000, 18_000),
                "ba-lead": (3_000, 10_000),
                "po-new": (10_000, 40_000),
                "po-lead": (4_000, 12_000),
                "cto": (6_000, 22_000),
                "qc-lead": (4_000, 15_000),
                "git": (1_000, 4_000),
            }.get(staff, (2_000, 8_000))
            total = rng.randint(*base)
            if weekend:
                total = int(total * 0.45)
            inp = int(total * rng.uniform(0.82, 0.93))
            out = max(1, total - inp)
            hour = rng.randint(1, 22)
            minute = rng.randint(0, 59)
            ts = day.replace(hour=hour, minute=minute)
            events.append(
                {
                    "timestamp": ts.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "company": args.company_slug,
                    "staff": staff,
                    "worktree": worktree,
                    "model": model,
                    "launch_mode": launch,
                    "input_tokens": inp,
                    "output_tokens": out,
                    "total_tokens": total,
                    "note": "virtual hop session (seed-demo-usage)",
                }
            )

    events.sort(key=lambda e: e["timestamp"])
    out_path.write_text(
        "".join(json.dumps(e, ensure_ascii=False) + "\n" for e in events),
        encoding="utf-8",
    )
    by_model: dict[str, int] = {}
    for e in events:
        by_model[e["model"]] = by_model.get(e["model"], 0) + e["total_tokens"]
    print(f"wrote\t{out_path}")
    print(f"events\t{len(events)}")
    print(f"days\t{args.days}")
    print(f"staffs\t{','.join(staffs)}")
    for m, n in sorted(by_model.items()):
        print(f"model\t{m}\t{n}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

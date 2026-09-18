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

# staff → models (weighted). Keep roughly balanced across grok/claude/codex overall.
# (model, launch_mode, weight)
STAFF_MODELS: dict[str, list[tuple[str, str, int]]] = {
    "ceo": [("grok", "grok", 3), ("claude", "merge", 1), ("codex", "merge", 1)],
    "cto": [("claude", "claude", 3), ("grok", "merge", 1), ("codex", "merge", 1)],
    "ba-lead": [("claude", "claude", 2), ("codex", "codex", 2), ("grok", "merge", 1)],
    "ba-user": [("claude", "claude", 2), ("grok", "merge", 2), ("codex", "merge", 1)],
    "po-lead": [("codex", "codex", 2), ("claude", "merge", 2), ("grok", "merge", 1)],
    "po-new": [("codex", "codex", 2), ("claude", "claude", 2), ("grok", "merge", 1)],
    "qc-lead": [("claude", "claude", 2), ("grok", "grok", 2), ("codex", "merge", 1)],
    "git": [("grok", "grok", 2), ("codex", "codex", 2), ("claude", "merge", 1)],
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
            choices = STAFF_MODELS.get(staff) or [("grok", "grok", 1)]
            # weighted pick
            bag: list[tuple[str, str]] = []
            for model, launch, w in choices:
                bag.extend([(model, launch)] * max(1, w))
            model, launch = rng.choice(bag)
            worktree = rng.choice(WORKTREES)
            # Token volume by role (keep po-* from dominating the pie)
            base = {
                "ceo": (8_000, 22_000),
                "ba-user": (6_000, 18_000),
                "ba-lead": (4_000, 12_000),
                "po-new": (7_000, 20_000),
                "po-lead": (5_000, 14_000),
                "cto": (7_000, 20_000),
                "qc-lead": (5_000, 15_000),
                "git": (2_000, 6_000),
            }.get(staff, (3_000, 10_000))
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

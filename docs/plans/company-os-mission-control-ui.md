# Company OS — Mission Control UI (Paperclip-inspired)

Status: **draft plan** (not PO-locked).  
**UI repo:** [`agents-holding-mac-app`](https://github.com/jokerphuongnam/agents-holding-mac-app) (macOS SwiftUI) — companion to [`agents-holding`](https://github.com/jokerphuongnam/agents-holding).  
Scope: **company OS mission control** — not Desk Garden product gameplay.

Inspired by [Paperclip](https://paperclip.ing/) (org canvas / manage a company of agents), adapted to Marlin **holding + company OS** (staffs, child companies, harnesses, plans, worktrees, user channels).

## Goal

macOS app to **control holding / company via org diagram + chat in company context**, instead of opening a terminal by hand.

User opens the app → **Holding (org canvas)** → click **staff** or **company** → detail / enter company → inside company: diagram + **CEO chat** (same worktree) → when CEO calls BA, **auto-open BA panel**, then **return to CEO**.  
Also a **dedicated token usage screen** (by staff / model / worktree / time).

## Product shape

| Decision | Choice |
| --- | --- |
| Code home | **[`agents-holding-mac-app`](https://github.com/jokerphuongnam/agents-holding-mac-app)** — companion of [`agents-holding`](https://github.com/jokerphuongnam/agents-holding) |
| Stack | **macOS SwiftUI** (native FS, windowing, polish motion) |
| Data SoT | Read (later write policies) from **`agents-holding`** path — never vendor staff SoT into the app repo |
| Entry | App **discovers Holding path** (`AGENTS_HOLDING_PATH` / Settings / sibling `../agents-holding`) |
| Primary UI | **Paperclip-style org diagram** — not a bare list as the main surface |
| Chat entry | **Always start chat inside a company** (not from the terminal) |
| Terminal | Runtime under the hood only (CLI/API harness); user does not enter via terminal |
| Usage | **Dedicated screen** — token stats table (not embedded in the org canvas) |
| Motion | **Polish only** — small → large scale when opening holding / company / child / staff to soften hard page jumps; not a product feature |

## Non-goals

- Do not replace Desk Garden game UI / plant-water / host-shell product AC  
- Do not clone Paperclip 1:1 (ticket / budget / heartbeat → later phase if needed)  
- Do not edit `system/staffs/**` when the user only changes the merge map  
- Do not require `runtime_router.enabled = true` by default (opt-in)  
- ICs that are not user channels (`game-engineer`, …) **must not** auto-open chat with the user

---

## Information architecture

### 1. Holding home (entry canvas)

Opening Holding = **diagram / inventory of companies only** (do not list holding staffs on home).

| Click | Result |
| --- | --- |
| **Company** | **Open that company** (child companies + teams + staffs) |

Holding context: holding path + company registry (`company_registry.py`).

### 2. Company view (after opening a company)

Inside a company show:

- **Child companies** (click → open child company / external SoT)  
- **Teams** (`system/staffs/<team>/`)  
- **Staffs nested under team** (not a flat company-wide list)  
- Click **staff** → staff detail (includes team field)  
- Click **child company** → drill into that company  

**Company context strip** (header):

| Field | Meaning | Approximate SoT |
| --- | --- | --- |
| Slug / name | e.g. `desk-garden-company` | folder + `META.toml` |
| Parent | **Holding** if top-level child; **parent company** if nested | `parent_slug`, pointer |
| Folder / `project_root` | Package cwd the company works in | `META.toml` `project_root` / `company_path` |
| Plan(s) | Related plan files | `cache/plans/`, repo `docs/plans/` |
| Worktree(s) | Worktrees bound to sessions | `.company-worktrees/`, launch `--worktree-name` |

### 3. Staff detail (holding or company)

**Principle:** a staff **does not** read / work the whole project. They only get:

1. **Narrow skills / duties** — e.g. `devops` → CLI/pack/mpm; `git` → git gate; eng → matching skill tree  
2. **Path fence** — allowed files/folders (team RW + SCOPE / staff md)  
3. **Org** — lead (superior) + reports (people they manage)

Staff detail UI must make those two limit layers clear (task/skill + filesystem), and must not imply “full repo access”.

| Section | Content |
| --- | --- |
| Identity | name, description/blurb, tier, permission / capability |
| Org | lead (parent staff), direct reports (may be empty) |
| Skills | skill id list — **tap to read** `SKILL.md` (this is the duty boundary) |
| Access scope | allowed / must-not files/folders (SCOPE + staff fence) |
| Worktrees | attached / active worktrees (P0 may be thin; P3 ledger complete) |
| Runtime profiles | grok / codex / claude / **merge** table (below) |

### 4. Runtime profiles — invariant

**Staff SoT does not change.** Only **how** the staff runs changes by launch mode.

| Launch | UI shows | Behavior |
| --- | --- | --- |
| **grok** / **codex** / **claude** | model + effort from that harness × staff tier | Session is **full** that vendor |
| **merge** | **resolved**: runtime (CLI) + model + effort | Overlay `runtime_router.toml`; model/effort come from the mapped runtime harness. Staff card/skills/tier unchanged |

Merge example: CEO → grok; `ba-user` → claude. CEO hop BA = **CLI bridge**, does not spawn BA as an agent inside the grok session.

Script SoT (holding):

```bash
python3 …/runtime_router.py resolve --role ba-user --session grok
python3 …/runtime_router.py hop --from ceo --to ba-user --session grok --goal '…'
```

### 5. Session / chat (starts inside company)

Chat **does not** start outside a company or from a user-facing terminal.

**In company view:**

1. Pick or create a **worktree** (if none yet).  
2. **Default chat = `ceo`** for that worktree (user channel).  
3. Harness: grok | codex | claude | merge (merge uses router default / map).  

**CEO call BA (user-facing handoff):**

```text
[Company] CEO chat (worktree W)
    → CEO calls ba-user
[Company] Auto-open BA-user panel/session (same W)
    → User ↔ ba-user
    → BA done / handback
[Company] Close or archive BA panel → focus CEO chat again (same W)
```

Rules:

- Same **worktree name** end-to-end — do not create a new worktree only for BA.  
- Only **`ba-user`** (and if policy allows: `backend-ba`) auto-opens a user chat surface.  
- Lead hop to other ICs = internal handoff, **does not** open user chat.  
- Merge: BA panel may use a different CLI/model; show runtime badge on the panel.  
- Optional: paste BA brief back into the CEO thread on handback.

“Terminal” = session panel (chat + log), with CLI simulated underneath.

### 6. Usage / token stats (**dedicated screen**)

A standalone **Usage** screen (own nav), not a replacement for the org canvas.

**Goal:** know how many tokens staff / model / worktree burned — including when run through **merge**.

#### Attribution rules

| Dimension | Rule |
| --- | --- |
| **Staff** | Tokens attach to the **staff role** that ran (`ceo`, `ba-user`, …), not to “session owner” unless that staff is the one |
| **Model** | Attach to the **actual model invoked** (e.g. `grok-4.6`, `sonnet`). Launch = `merge` but router chose grok for the staff → **count in the grok model bucket** (optional secondary column `launch_mode=merge`) |
| **Runtime / vendor** | grok / claude / codex (CLI that was invoked) |
| **Worktree** | By session worktree name / path |
| **Company / holding** | Scope filter: holding-wide vs one company |

#### Time & slice filters (table + chart)

- All time  
- By **day** / **month** (and custom range)  
- By **one worktree** / all worktrees  
- By **one staff** / all staff  
- By **model** (and/or vendor)

#### Views on the screen

1. **Summary cards** — total tokens (holding or filtered company)  
2. **By staff** — total tokens per staff (all-time / period)  
3. **By model** — grok vs claude vs … (merge is not its own bucket once model is resolved; optional `direct` vs `via_merge` breakdown)  
4. **By worktree** — tokens per worktree; drill-down staff×model inside a worktree  
5. **Staff drill-down** — from staff detail, “Usage” link → prefilter that staff  

#### Metering SoT (required so the UI does not invent numbers)

Company OS **does not yet** have a full token ledger across the dimensions above → the Usage phase needs:

- Collector on session/hop/`--execute` (and chat UI) writing events:  
  `timestamp, company, worktree, staff, launch_mode, runtime, model, effort, input_tokens, output_tokens, total_tokens, source`  
- Store: SQLite/JSONL under holding or company `cache/usage/` (lock at implement time)  
- UI **only reads** the ledger; missing meter → clear empty state (“no usage events yet”)

---

## Screens

1. **Holding org canvas** — staffs + companies (Paperclip-style)  
2. **Company org canvas** — staffs (+ nested companies) + context strip  
3. **Staff detail** — shared drawer from holding or company  
4. **Company chat dock** — CEO (default); BA panel when CEO calls BA  
5. **Merge policy / hop preview** (optional tab) — role → runtime; native vs cli  
6. **Usage (token stats)** — **dedicated screen**: table/filters by staff, model, worktree, day/month/all-time  

List/table is right for Usage; org still uses the **diagram** as the primary surface.

### Motion / transitions (scale-up) — polish

Only so navigation **feels less abrupt**. No new product behavior; do not block ship if missing (P0 still passes when clicks open the right screen).

Suggestion (shared-element / hero zoom):

| Gesture | Suggested motion |
| --- | --- |
| Click **Holding** / **company** / **child company** | Node/card **scale small → large**, fill viewport |
| Click **staff** | Staff panel/node **zoom up** → detail |
| Back / close | **Reverse scale** to the node position on the canvas |
| Usage | Light fade/slide is fine |

Reduced-motion → disable scale; fall back to fade/instant.

---

## Phases

| Phase | Deliverable |
| --- | --- |
| **P0** | UI repo + discover Holding; **org canvas** for holding (staff + company nodes); click → staff detail / open company; company canvas read-only + context strip. **Add company wizard** (catalog-only): folder → select **template staffs** → select **library skills** → `create-company.sh` + `apply_company_roster.py`. **Do not** invent empty staff/skill in the app (add SoT to holding templates first). Scale-up = polish. |
| **P1** | **Chat inside company** with CEO (worktree-bound); harness picker; wire launch/session under the hood |
| **P1.5** | **CEO → BA channel switch**: auto-open BA panel on same worktree; handback closes BA → CEO |
| **P2** | Runtime profile table + merge resolve/hop preview; optional edit `[[roles]]` / enable + regen adapters |
| **P3** | Worktree/plan live binding + handoff/worktree history per staff; cleaner access-scope SoT |
| **P4** | **Usage ledger + Usage screen** (filters staff/model/worktree/day/month/all-time; merge→model attribution) |
| **P5** | Paperclip extras (tickets, budgets-as-caps, heartbeats) if still needed — budgets may read the same Usage ledger |

## Acceptance

### P0 — canvas

1. Open app → Holding canvas (user is not forced to open a terminal first).  
2. Holding shows **both staff and company** as a diagram (not list-only).  
3. Click staff → detail; click company → enter company canvas.  
4. Company shows correct parent (holding vs parent company) + `project_root`.  
5. Company canvas: click staff → detail; click child company (if any) → open next.  
5b. *(Polish)* Small→large scale / back scale-down for holding·company·staff — encouraged, does not fail P0 if missing.  

### P1 — chat in company

6. Inside company: can chat with **CEO** on a worktree.  
7. User is not required to run `launch.sh` outside the UI.  

### P1.5 — BA handoff UX

8. When CEO calls BA: UI **auto-opens** `ba-user` panel on the same worktree.  
9. When BA finishes: BA panel closes/hides → **return to CEO**.  
10. Non-user IC **does not** open user chat.  

### Runtime invariant (P2+)

11. Merge column/panel = overlay resolve; **does not** imply the staff file changed.  
12. Hop preview `ceo@grok → ba-user@claude` = mode `cli`.  

### Usage (P4)

13. There is a **dedicated Usage screen** (nav), not only a canvas widget.  
14. Filters work: all-time / day / month / range; by staff; by worktree; by model.  
15. Tokens via **merge** but model resolves to grok → **count toward grok model stats** (and still know `launch_mode=merge` if needed).  
16. Empty state when there are no ledger events yet.  

## Open questions

- UI repo stack (local web / Electron / IDE panel)?  
- Discover Holding: single config path vs multi-holding switcher?  
- Edit merge in UI vs deep-link toml at P2?  
- Canonical access-scope SoT (GRANTS vs `scope_guard`)?  
- Does `backend-ba` get the same auto-panel as `ba-user`?  
- Usage store: holding-global vs per-company files? Which vendor CLI/API is the source of truth for tokens?  
- Scale-up: full-screen route vs overlay layer on the same canvas? Duration / easing from the design system?

## References

- Paperclip: https://paperclip.ing/  
- Holding hop script: `runtime_router.py` (`resolve`, `hop`) — agents-holding  
- Company launch: `launch.sh <grok|claude|codex|merge> [--worktree-name] [--agent ceo|ba-user]`  
- User channels: `ceo`, `ba-user` (same worktree)  

## Next

1. PO lock this plan (or design-lead wireframe P0 canvas).  
2. **P0 in this repo:** real org diagram layout (not only grid cards); parse `META.toml` / `COMPANY_POINTER` for `project_root`; open company staffs canvas.  
3. Desk Garden host-shell / product plans **track separately** — do not fold into this plan.  
4. Optional: add GitHub remote when ready (`gh repo create`).  

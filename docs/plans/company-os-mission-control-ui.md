# Company OS — Mission Control UI (Paperclip-inspired)

Status: **draft plan** (not PO-locked).  
**UI repo:** `agents-holding-app` (macOS SwiftUI) — sibling of `agents-holding` under `Documents/Agents/`.  
Scope: **company OS mission control** — not Desk Garden product gameplay.

Inspired by [Paperclip](https://paperclip.ing/) (org canvas / manage a company of agents), adapted to Marlin **holding + company OS** (staffs, child companies, harnesses, plans, worktrees, user channels).

## Goal

macOS app để **điều khiển holding / company bằng sơ đồ + chat trong context company**, thay vì mở terminal thủ công.

User mở app → **Holding (org canvas)** → click **staff** hoặc **company** → detail / vào company → trong company: sơ đồ + **chat CEO** (cùng worktree) → CEO call BA thì **tự mở panel BA**, xong **trả về CEO**.  
Ngoài ra có **screen thống kê token riêng** (theo staff / model / worktree / thời gian).

## Product shape

| Decision | Choice |
| --- | --- |
| Code home | **`agents-holding-app`** — sibling ngang cấp `agents-holding` (không nằm trong holding hay marlin-language) |
| Stack | **macOS SwiftUI** (native FS, windowing, polish motion) |
| Data SoT | Read (later write policies) from **`agents-holding`** path — never vendor staff SoT into the app repo |
| Entry | App **tự tìm path Holding** (`AGENTS_HOLDING_PATH` / Settings / sibling `../agents-holding`) |
| Primary UI | **Sơ đồ org kiểu Paperclip** — không lấy list khô làm mặt chính |
| Chat entry | **Bắt đầu chat luôn trong company** (không bắt đầu từ terminal) |
| Terminal | Chỉ runtime phía dưới (CLI/API harness); user không lấy terminal làm cửa vào |
| Usage | **Screen riêng** — bảng thống kê token (không nhét vào org canvas) |
| Motion | **Polish only** — scale nhỏ → lớn khi mở holding / company / child / staff cho đỡ nhảy trang thô; không phải feature nghiệp vụ |

## Non-goals

- Không thay Desk Garden game UI / plant-water / host-shell product AC  
- Không clone Paperclip 1:1 (ticket / budget / heartbeat → phase sau nếu cần)  
- Không sửa `system/staffs/**` khi user chỉ đổi merge map  
- Không bắt buộc `runtime_router.enabled = true` mặc định (opt-in)  
- IC không phải user channel (`game-engineer`, …) **không** auto-mở chat với user

---

## Information architecture

### 1. Holding home (entry canvas)

Mở Holding = **sơ đồ / inventory companies only** (không liệt kê staff holding trên home).

| Click | Result |
| --- | --- |
| **Company** | **Mở company đó** (child companies + teams + staffs) |

Holding context: path holding + registry companies (`company_registry.py`).

### 2. Company view (sau khi bấm vào một company)

Trong company hiện:

- **Child companies** (click → mở company con / external SoT)  
- **Teams** (`system/staffs/<team>/`)  
- **Staffs nested under team** (không flat list toàn company)  
- Click **staff** → staff detail (có field team)  
- Click **child company** → drill vào company đó  

**Company context strip** (header):

| Field | Meaning | SoT gần đúng |
| --- | --- | --- |
| Slug / name | e.g. `desk-garden-company` | folder + `META.toml` |
| Parent | **Holding** nếu top-level child; **parent company** nếu nested | `parent_slug`, pointer |
| Folder / `project_root` | Package cwd company làm việc | `META.toml` `project_root` / `company_path` |
| Plan(s) | Plan files liên quan | `cache/plans/`, repo `docs/plans/` |
| Worktree(s) | Worktree đang gắn session | `.company-worktrees/`, launch `--worktree-name` |

### 3. Staff detail (holding hoặc company)

| Section | Content |
| --- | --- |
| Identity | name, mô tả/blurb, tier, permission / capability |
| Org | lead (parent staff), direct reports (có hoặc không) |
| Skills | skill column / customs + defaults |
| Access scope | files/folders được phép (GRANTS / hop scope — P0 best-effort nếu SoT còn rời) |
| Worktrees | worktree đã/đang gắn (P0 có thể mỏng; P3 ledger đủ) |
| Runtime profiles | bảng grok / codex / claude / **merge** (dưới) |

### 4. Runtime profiles — invariant

**Staff SoT không đổi.** Chỉ cách **chạy** staff đổi theo launch mode.

| Launch | UI shows | Behavior |
| --- | --- | --- |
| **grok** / **codex** / **claude** | model + effort từ harness đó × tier staff | Session **full** vendor đó |
| **merge** | **resolved**: runtime (CLI) + model + effort | Overlay `runtime_router.toml`; model/effort lấy từ harness của runtime được map. Staff card/skills/tier không đổi |

Ví dụ merge: CEO → grok; `ba-user` → claude. CEO hop BA = **CLI bridge**, không spawn BA như agent trong session grok.

Script SoT (holding):

```bash
python3 …/runtime_router.py resolve --role ba-user --session grok
python3 …/runtime_router.py hop --from ceo --to ba-user --session grok --goal '…'
```

### 5. Session / chat (bắt đầu trong company)

Chat **không** bắt đầu ngoài company hay từ terminal user-facing.

**Trong company view:**

1. Chọn hoặc tạo **worktree** (nếu chưa có).  
2. **Chat mặc định = `ceo`** của worktree đó (user channel).  
3. Harness: grok | codex | claude | merge (merge dùng router default / map).  

**CEO call BA (user-facing handoff):**

```text
[Company] Chat CEO (worktree W)
    → CEO call ba-user
[Company] Tự mở panel/session BA-user (cùng W)
    → User ↔ ba-user
    → BA done / handback
[Company] Đóng hoặc archive panel BA → focus lại chat CEO (cùng W)
```

Quy tắc:

- Cùng **worktree name** xuyên suốt — không tạo worktree mới chỉ vì BA.  
- Chỉ **`ba-user`** (và nếu có policy: `backend-ba`) được auto-mở user chat surface.  
- Lead hop IC khác = handoff nội bộ, **không** mở chat user.  
- Merge: panel BA có thể khác CLI/model; badge runtime trên panel.  
- Optional: brief BA dán lại thread CEO khi handback.

“Terminal” = session panel (chat + log), mô phỏng CLI phía dưới.

### 6. Usage / token stats (**screen riêng**)

Một màn **Usage** độc lập (nav riêng), không thay org canvas.

**Mục tiêu:** biết staff / model / worktree đã đốt bao nhiêu token — kể cả khi chạy qua **merge**.

#### Attribution rules

| Dimension | Rule |
| --- | --- |
| **Staff** | Token gắn **staff role** đang chạy (`ceo`, `ba-user`, …), không gắn “session owner” trừ khi chính staff đó |
| **Model** | Gắn **model thật đã gọi** (vd. `grok-4.6`, `sonnet`). Launch = `merge` nhưng router chọn grok cho staff → **tính vào bucket model grok** (và có thể có cột secondary `launch_mode=merge`) |
| **Runtime / vendor** | grok / claude / codex (CLI đã invoke) |
| **Worktree** | Theo worktree name / path của session |
| **Company / holding** | Scope filter: holding-wide vs một company |

#### Time & slice filters (bảng + chart)

- Toàn thời gian  
- Theo **ngày** / **tháng** (và range custom)  
- Theo **một worktree** / tất cả worktree  
- Theo **một staff** / tất cả staff  
- Theo **model** (và/hoặc vendor)

#### Views trên screen

1. **Summary cards** — total tokens (holding hoặc company đang filter)  
2. **By staff** — tổng token mỗi staff (all-time / period)  
3. **By model** — grok vs claude vs … (merge không tách bucket riêng nếu model đã resolve; optional breakdown `direct` vs `via_merge`)  
4. **By worktree** — token per worktree; drill-down staff×model trong worktree  
5. **Staff drill-down** — từ staff detail có link “Usage” → prefilter staff đó  

#### Metering SoT (cần có để UI không bịa số)

Hiện company OS **chưa** có ledger token chuẩn đủ các chiều trên → phase Usage cần:

- Collector khi session/hop/`--execute` (và chat UI) ghi event:  
  `timestamp, company, worktree, staff, launch_mode, runtime, model, effort, input_tokens, output_tokens, total_tokens, source`  
- Store: SQLite/JSONL dưới holding hoặc company `cache/usage/` (chốt lúc implement)  
- UI **chỉ đọc** ledger; thiếu meter → empty state rõ (“chưa có usage events”)

---

## Screens

1. **Holding org canvas** — staffs + companies (Paperclip-style)  
2. **Company org canvas** — staffs (+ nested companies) + context strip  
3. **Staff detail** — shared drawer từ holding hoặc company  
4. **Company chat dock** — CEO (default); BA panel khi CEO call BA  
5. **Merge policy / hop preview** (optional tab) — role → runtime; native vs cli  
6. **Usage (token stats)** — **screen riêng**: bảng/filter theo staff, model, worktree, ngày/tháng/all-time  

List/table cho Usage là đúng chỗ; org vẫn lấy **sơ đồ** làm mặt chính.

### Motion / transitions (scale-up) — polish

Chỉ để navigation **đỡ thô cứng**. Không thêm nghiệp vụ, không block ship nếu chưa có (P0 vẫn nhận nếu click đúng mở đúng màn).

Gợi ý (shared-element / hero zoom):

| Gesture | Motion gợi ý |
| --- | --- |
| Click **Holding** / **company** / **child company** | Node/card **scale nhỏ → lớn**, fill viewport |
| Click **staff** | Panel/node staff **phóng to** → detail |
| Back / đóng | **Scale ngược** về vị trí node trên canvas |
| Usage | Fade/slide nhẹ cũng được |

Reduced-motion → tắt scale, fallback fade/instant.

---

## Phases

| Phase | Deliverable |
| --- | --- |
| **P0** | Repo UI + discover Holding; **org canvas** holding (staff + company nodes); click → staff detail / open company; company canvas read-only + context strip. Scale-up motion = **nice-to-have polish** (không chặn P0) |
| **P1** | **Chat trong company** với CEO (worktree-bound); harness picker; wire launch/session dưới hood |
| **P1.5** | **CEO → BA channel switch**: auto mở BA panel cùng worktree; handback đóng BA → CEO |
| **P2** | Runtime profile table + merge resolve/hop preview; optional edit `[[roles]]` / enable + regen adapters |
| **P3** | Worktree/plan live binding + handoff/worktree history per staff; access scope SoT sạch hơn |
| **P4** | **Usage ledger + Usage screen** (filters staff/model/worktree/day/month/all-time; merge→model attribution) |
| **P5** | Paperclip extras (tickets, budgets-as-caps, heartbeats) nếu vẫn cần — budgets có thể đọc cùng ledger Usage |

## Acceptance

### P0 — canvas

1. Mở app → Holding canvas (không bắt user mở terminal trước).  
2. Holding hiện **cả staff lẫn company** dạng sơ đồ (không chỉ list).  
3. Click staff → detail; click company → vào company canvas.  
4. Company hiện parent đúng (holding vs parent company) + `project_root`.  
5. Company canvas: click staff → detail; click child company (nếu có) → mở tiếp.  
5b. *(Polish)* Scale nhỏ→lớn / back scale-down cho holding·company·staff — khuyến khích, không fail P0 nếu thiếu.  

### P1 — chat in company

6. Trong company: chat được với **CEO** trên một worktree.  
7. Không yêu cầu user tự chạy `launch.sh` ngoài UI.  

### P1.5 — BA handoff UX

8. Khi CEO call BA: UI **tự mở** panel `ba-user` cùng worktree.  
9. Khi BA xong: panel BA đóng/ẩn → **quay lại CEO**.  
10. IC non-user **không** mở chat user.  

### Runtime invariant (P2+)

11. Cột/panel merge = overlay resolve; **không** imply staff file đổi.  
12. Preview hop `ceo@grok → ba-user@claude` = mode `cli`.  

### Usage (P4)

13. Có **screen Usage riêng** (nav), không chỉ widget trên canvas.  
14. Filter được: all-time / day / month / range; theo staff; theo worktree; theo model.  
15. Token qua **merge** nhưng model resolve = grok → **cộng vào thống kê model grok** (và vẫn biết `launch_mode=merge` nếu cần).  
16. Empty state khi chưa có ledger events.  

## Open questions

- Stack repo UI (web local / Electron / IDE panel)?  
- Discover Holding: single config path vs multi-holding switcher?  
- Edit merge trong UI vs deep-link toml ở P2?  
- Access scope SoT canonical (GRANTS vs `scope_guard`)?  
- `backend-ba` có cùng auto-panel như `ba-user` không?  
- Usage store: holding-global vs per-company files? Lấy token từ vendor CLI/API nào làm nguồn sự thật?  
- Scale-up: full-screen route vs overlay layer trên cùng canvas? Duration / easing chuẩn design-system?

## References

- Paperclip: https://paperclip.ing/  
- Holding hop script: `runtime_router.py` (`resolve`, `hop`) — agents-holding  
- Company launch: `launch.sh <grok|claude|codex|merge> [--worktree-name] [--agent ceo|ba-user]`  
- User channels: `ceo`, `ba-user` (cùng worktree)  

## Next

1. PO lock plan này (hoặc design-lead wireframe P0 canvas).  
2. **P0 in this repo:** real org diagram layout (not only grid cards); parse `META.toml` / `COMPANY_POINTER` for `project_root`; open company staffs canvas.  
3. Desk Garden host-shell / product plans **track riêng** — không gộp vào plan này.  
4. Optional: add GitHub remote when ready (`gh repo create`).  

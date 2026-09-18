# agents-holding-mac-app

macOS **SwiftUI** mission-control UI for [agents-holding](../agents-holding) (Paperclip-inspired org canvas + in-company CEO/BA chat + Usage).

Sibling of `agents-holding` under `Documents/Agents/` — **not** inside the holding git tree.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/jokerphuongnam/agents-holding-mac-app/main/install.sh | bash
```

Clones/updates into `~/Documents/Agents/agents-holding-mac-app`, runs `Scripts/generate.sh` (SwiftGen + XcodeGen via SPM), then opens Xcode.

Re-run the same command anytime after you push updates.

```bash
curl -fsSL …/install.sh | bash -s -- --dest ~/Documents/Agents/agents-holding-mac-app
curl -fsSL …/install.sh | bash -s -- --from-local /path/to/clone
curl -fsSL …/install.sh | bash -s -- --no-open
```

## Plan

See [`docs/plans/company-os-mission-control-ui.md`](docs/plans/company-os-mission-control-ui.md).

## Requirements

- macOS 14+
- **Only:** Swift / Xcode (no Homebrew for codegen)
- Network once to resolve SPM (app + `BuildTools/`: SwiftGen, XcodeGen)

## Setup (from a clone)

```bash
cd ~/Documents/Agents/agents-holding-mac-app
./Scripts/generate.sh
open AgentsHoldingApp.xcodeproj
```

Gitignored: `AgentsHoldingApp.xcodeproj/`, `AgentsHoldingApp/Generated/`, `BuildTools/.build/`.

Xcode **Run** pre-build: `SKIP_XCODEGEN=1 ./Scripts/generate.sh` (SwiftGen only).

Holding path resolution (first match wins):

1. Env `AGENTS_HOLDING_PATH`
2. Settings / `UserDefaults` key `holdingPath`
3. Sibling `../agents-holding`
4. `~/Documents/Agents/agents-holding`

## P0 scaffold status

- [x] macOS SwiftUI app target
- [x] Discover holding + list staffs / child companies
- [x] Navigate holding → staff detail / company placeholder / Usage placeholder
- [ ] Paperclip-style graph layout + scale-up polish
- [ ] Company canvas + CEO chat + BA handoff
- [ ] Usage ledger screen

## License

Private — same org as agents-holding.

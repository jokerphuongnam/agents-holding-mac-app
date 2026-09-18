# agents-holding-mac-app

macOS **SwiftUI** mission-control UI for [agents-holding](https://github.com/jokerphuongnam/agents-holding) (Paperclip-inspired org canvas + in-company CEO/BA chat + Usage).

Companion app for the holding Company OS — **not** inside the [agents-holding](https://github.com/jokerphuongnam/agents-holding) git tree.

## Install (prebuilt DMG)

```bash
curl -fsSL https://raw.githubusercontent.com/jokerphuongnam/agents-holding-mac-app/main/install.sh | bash
```

Downloads **`AgentsHolding-mac.dmg`** from the latest [GitHub Release](https://github.com/jokerphuongnam/agents-holding-mac-app/releases), installs the `.app` into `~/Applications`, and launches it — **no clone, no local build**.

```bash
curl -fsSL …/install.sh | bash -s -- --tag v0.1.0
curl -fsSL …/install.sh | bash -s -- --dir /Applications
curl -fsSL …/install.sh | bash -s -- --no-open
```

### Publish a DMG (maintainers)

```bash
./Scripts/package-dmg.sh          # → dist/AgentsHolding-mac.dmg
gh release create v0.1.0 dist/AgentsHolding-mac.dmg --title "v0.1.0"
```

### Dev from source

```bash
git clone git@github.com:jokerphuongnam/agents-holding-mac-app.git
cd agents-holding-mac-app && ./Scripts/generate.sh && open AgentsHoldingApp.xcodeproj
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
3. Sibling checkout `../agents-holding` (local clone of [agents-holding](https://github.com/jokerphuongnam/agents-holding))
4. `~/Documents/Agents/agents-holding`

## P0 scaffold status

- [x] macOS SwiftUI app target
- [x] Discover holding + list staffs / child companies
- [x] Navigate holding → staff detail / company placeholder / Usage placeholder
- [ ] Paperclip-style graph layout + scale-up polish
- [ ] Company canvas + CEO chat + BA handoff
- [ ] Usage ledger screen

## License

Private — same org as [agents-holding](https://github.com/jokerphuongnam/agents-holding).

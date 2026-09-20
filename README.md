# agents-holding-mac-app

macOS **SwiftUI** mission-control UI for [agents-holding](https://github.com/jokerphuongnam/agents-holding) (org canvas + staff tree + Usage).

Companion app for the holding Company OS — **not** inside the [agents-holding](https://github.com/jokerphuongnam/agents-holding) git tree.

## Install (one command)

```bash
curl -fsSL https://raw.githubusercontent.com/jokerphuongnam/agents-holding-mac-app/main/install.sh | bash
```

That single command:

1. Downloads **`AgentsHolding-mac.dmg`** from the latest [GitHub Release](https://github.com/jokerphuongnam/agents-holding-mac-app/releases)
2. Installs the `.app` into **`/Applications`**
3. Opens the app

No clone, no Xcode, no Homebrew. macOS may ask for an admin password to write `/Applications`.

Optional flags:

```bash
curl -fsSL https://raw.githubusercontent.com/jokerphuongnam/agents-holding-mac-app/main/install.sh | bash -s -- --tag v1.0.1
curl -fsSL https://raw.githubusercontent.com/jokerphuongnam/agents-holding-mac-app/main/install.sh | bash -s -- --dir "$HOME/Applications"
curl -fsSL https://raw.githubusercontent.com/jokerphuongnam/agents-holding-mac-app/main/install.sh | bash -s -- --no-open
```

### Publish a DMG (maintainers)

```bash
./Scripts/package-dmg.sh          # → dist/AgentsHolding-mac.dmg
gh release create v1.0.1 dist/AgentsHolding-mac.dmg --title "v1.0.1" --latest
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
- **Install path:** only `curl` + network (prebuilt DMG)
- **From source:** Swift / Xcode (no Homebrew for codegen); SPM resolves once (`BuildTools/`: SwiftGen, XcodeGen)

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

## Demo company (real product + virtual usage)

```bash
# product
cd ~/Documents/Agents/demo-analytics-lab
PYTHONPATH=src python3 -m labkit.cli summary data/sample_events.csv

# re-seed virtual hop usage
python3 Scripts/seed-demo-usage.py \
  --company-path ~/Documents/Agents/demo-analytics-lab/.agents/demo-analytics-lab-company
```

Then open **demo-analytics-lab** in the app → Usage.

## License

Private — same org as [agents-holding](https://github.com/jokerphuongnam/agents-holding).

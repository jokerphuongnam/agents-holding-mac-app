# agents-holding-app

macOS **SwiftUI** mission-control UI for [agents-holding](../agents-holding) (Paperclip-inspired org canvas + in-company CEO/BA chat + Usage).

Sibling of `agents-holding` under `Documents/Agents/` — **not** inside the holding git tree.

## Plan

See [`docs/plans/company-os-mission-control-ui.md`](docs/plans/company-os-mission-control-ui.md).

## Requirements

- macOS 14+
- Xcode 15+ (tested with Xcode 27 / Swift 6 toolchain)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Setup

```bash
cd ~/Documents/Agents/agents-holding-app
xcodegen generate
open AgentsHoldingApp.xcodeproj
```

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

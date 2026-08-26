# Squarely (App target)

The SwiftUI iOS app shell. Scaffolded on Windows (no Xcode available there), so
this needs a first real build pass on macOS — see "Known gaps" below.

## Setup (macOS)

```bash
brew install xcodegen        # one-time
cd App
xcodegen generate
open Squarely.xcodeproj
```

`Squarely.xcodeproj` is generated from `project.yml` and is gitignored — never
edit it directly; edit `project.yml` and regenerate instead.

Before running, set a real backend URL in `Squarely/AppConfig.swift`
(`apiBaseURL` currently points at a placeholder). Use `http://localhost:8787/`
for local `wrangler dev` testing per `DESIGN.md` §11 once the Worker exists.

## Structure

```
Squarely/
├── SquarelyApp.swift       # @main entry point
├── AppConfig.swift         # apiBaseURL placeholder
├── AppRoute.swift          # navigation state: start / createGroup / joinGroup / group
├── RootView.swift          # switches on AppRoute, handles onOpenURL deep links
├── Screens/                # StartView, CreateGroupView, JoinGroupView, GroupHomeView
├── ViewModels/             # GroupViewModel — fetch-on-load/refetch, no optimistic UI
└── Components/             # BalanceHeroView, MemberBalanceRow, ActivityRow, MoneyFormat
```

All domain logic (models, balances, debt simplification, validation, network
client, identity storage) lives in `SquareKit`, referenced as a local Swift
package. This target should stay thin — views and view models only.

## Known gaps (flagged honestly, not verified against a real Xcode build)

- Never built. Written and reasoned through carefully, but there was no Xcode
  on hand to compile it — treat the first `xcodegen generate` + build in Xcode
  as the real verification step, not a formality.
- No app icon / accent color asset catalog yet (Phase 6 polish).
- Universal Links need an Associated Domains entitlement + hosted
  apple-app-site-association once there's a production domain; only the
  `squarely://g/:groupId` dev scheme is wired for now.
- `MoneyFormat` assumes 2 decimal minor units for every currency (true for
  INR/USD/EUR/GBP, not for e.g. JPY) — fine for the currencies in the v1
  picker, worth revisiting if more are added.

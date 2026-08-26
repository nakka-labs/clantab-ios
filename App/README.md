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
├── AppConfig.swift         # apiBaseURL placeholder + groupShareURL(groupId:)
├── AppRoute.swift          # navigation state: start / createGroup / joinGroup / group
├── RootView.swift          # switches on AppRoute, handles onOpenURL deep links
├── Screens/                # StartView, CreateGroupView, JoinGroupView, GroupHomeView,
│                           # AddExpenseView, SettleUpView
├── ViewModels/             # GroupViewModel — fetch-on-load/refetch, no optimistic UI
└── Components/             # BalanceHeroView, MemberBalanceRow, ActivityRow, MoneyFormat,
                            # ClientErrorMessage, ExportFile (temp-file writer for ShareLink)
```

CSV/JSON serialization itself lives in `SquareKit.Export` (pure functions, tested
on Windows) — this target only writes the result to a temp file for `ShareLink`.

All domain logic (models, balances, debt simplification, validation, network
client, identity storage) lives in `SquareKit`, referenced as a local Swift
package. This target should stay thin — views and view models only.

## Known gaps (flagged honestly, not verified against a real Xcode build)

- Never built. Written and reasoned through carefully, but there was no Xcode
  on hand to compile it — treat the first `xcodegen generate` + build in Xcode
  as the real verification step, not a formality. This now spans Phases 3-6.
- No app icon / accent color asset catalog yet.
- Universal Links need an Associated Domains entitlement + hosted
  apple-app-site-association once there's a production domain; only the
  `squarely://g/:groupId` dev scheme is wired for now.
- `MoneyFormat` assumes 2 decimal minor units for every currency (true for
  INR/USD/EUR/GBP, not for e.g. JPY) — fine for the currencies in the v1
  picker, worth revisiting if more are added.
- The 6-character join code is only ever returned by `POST /api/groups`
  (`DESIGN.md` §2) — `GET /api/groups/:groupId` doesn't include it. So it can
  only be shown/shared once, right after creation (`CreateGroupView`'s
  confirmation step); it can't be recovered later from Group Home. If that
  turns out to matter, it needs a `DESIGN.md` change (return it from the
  group-state endpoint too), not a client-side workaround.
- Dark mode: reviewed, not changed. `BalanceHeroView`'s green/red and the rest
  of the UI all use system-adaptive colors (`.green`, `.red`, `.secondary`),
  which already adjust for dark mode automatically — nothing needed fixing.
- Offline/empty states: reviewed, considered adequate for v1.
  `GroupHomeView` already shows a full-screen spinner on first load and an
  inline error row on failure, consistent with `DESIGN.md` §9 ("design loading
  states as normal, not something to hide"). A dedicated offline banner was
  deliberately not added — nothing here has been exercised against a real
  network yet, so a heavier "offline mode" is easy to over-build blind.

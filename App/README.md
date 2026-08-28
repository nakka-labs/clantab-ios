# Squarely (App target)

The SwiftUI iOS app shell. Scaffolded on Windows (no Xcode available there);
compiles (CI-verified) and, as of 2026-08-28, run-verified end-to-end on an
iOS Simulator — see "Build status" below.

## Setup (macOS)

```bash
brew install xcodegen        # one-time
cd App
xcodegen generate
open Squarely.xcodeproj
```

`Squarely.xcodeproj` and `Squarely/Info.plist` are both generated from
`project.yml` and gitignored — never edit them directly; edit `project.yml`
and regenerate instead.

In Xcode's Signing & Capabilities tab, select your Apple Developer Program
Team. `project.yml` doesn't hardcode a `DEVELOPMENT_TEAM` (no team ID was
known at scaffolding time), so Xcode will prompt for one on first open —
with an enrolled Team this enables real device installs and TestFlight, not
just the 7-day free personal-team signing.

Before running, set a real backend URL in `Squarely/AppConfig.swift`
(`apiBaseURL` currently points at a placeholder). Use `http://localhost:8787/`
for local `wrangler dev` testing per `DESIGN.md` §11 once the Worker exists
(the Worker itself is a separate, later effort — not built in this repo yet).

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

## Build status

**Compiles**, verified by `.github/workflows/ios-build.yml` (a macOS GitHub
Actions runner building `xcodebuild ... -destination 'generic/platform=iOS
Simulator'` — no code signing needed). Three real build errors were found and
fixed this way: a `private` nested-type access error in `CreateGroupView`, a
`Section` overload-resolution failure in `AddExpenseView` caused by a `switch`
mixed into its content closure, and a ternary `ShapeStyle` type mismatch
(`.secondary` vs `.red`).

**Run-verified** (2026-08-28): first interactive run, end-to-end on an iOS
26.5 Simulator (Xcode 26.6), driven by a temporary XCUITest against a local
mock of the API. Every Phase 3-6 screen and flow — Start, Create, Group
Home, Add Expense, Settle Up, Share & Export, Join-by-code, deep-link scheme
registration, resume-on-relaunch, pull-to-refresh — exercised and asserted;
no SwiftUI runtime warnings, no crashes. Full write-up and findings in
`HANDOFF.md`'s "App/ Runtime Verification — Done" section.

## Known gaps

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
- No "leave group" / "switch group" affordance. `RootView` resumes into the
  last group on launch; if that group no longer exists server-side, Group
  Home shows only a small "Group not found." row and the `+` button with no
  way back to Start. Found in the 2026-08-28 runtime pass — needs either a
  "leave group" action or a `notFound`-at-resume fallback to Start.
- Dark mode: reviewed, not changed. `BalanceHeroView`'s green/red and the rest
  of the UI all use system-adaptive colors (`.green`, `.red`, `.secondary`),
  which already adjust for dark mode automatically — nothing needed fixing.
- Offline/empty states: reviewed, considered adequate for v1.
  `GroupHomeView` already shows a full-screen spinner on first load and an
  inline error row on failure, consistent with `DESIGN.md` §9 ("design loading
  states as normal, not something to hide"). A dedicated offline banner was
  deliberately not added — nothing here has been exercised against a real
  network yet, so a heavier "offline mode" is easy to over-build blind.

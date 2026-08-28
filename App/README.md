# Squarely (App target)

The SwiftUI iOS app shell. Builds and its `SquarelyTests` unit tests pass via
the local pre-push hook (`make hooks`); run-verified end-to-end against the
deployed Worker — see "Build status" below.

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

../SquarelyTests/           # App unit tests (XCTest): deep-link parsing (RootView),
                            # group-not-found detection (GroupViewModel). Run via the
                            # `Squarely` scheme (and by the pre-push hook).
```

CSV/JSON serialization itself lives in `SquareKit.Export` (pure functions, tested
on Windows) — this target only writes the result to a temp file for `ShareLink`.

All domain logic (models, balances, debt simplification, validation, network
client, identity storage) lives in `SquareKit`, referenced as a local Swift
package. This target should stay thin — views and view models only.

## Build status

**Compiles + `SquarelyTests` pass** via `make check` / the `pre-push` hook
(`xcodebuild test` for the `Squarely` scheme). This started life as a macOS
GitHub Actions job (`ios-build.yml`, since removed — see `HANDOFF.md`) back
when development was on Windows; it caught three real build errors on its
first run: a `private` nested-type access error in `CreateGroupView`, a
`Section` overload-resolution failure in `AddExpenseView`, and a ternary
`ShapeStyle` type mismatch.

**Run-verified** (2026-08-28): first interactive run, end-to-end on an iOS
26.5 Simulator (Xcode 26.6), driven by a temporary XCUITest against a local
mock of the API. Every Phase 3-6 screen and flow — Start, Create, Group
Home, Add Expense, Settle Up, Share & Export, Join-by-code, deep-link scheme
registration, resume-on-relaunch, pull-to-refresh — exercised and asserted;
no SwiftUI runtime warnings, no crashes. Full write-up and findings in
`HANDOFF.md`'s "App/ Runtime Verification — Done" section.

## Known gaps

- Placeholder app icon (`Assets.xcassets/AppIcon` — a flat "=" mark) + a blue
  `AccentColor`. Fine for TestFlight; swap for real design before the App Store.
- No custom launch screen (`UILaunchScreen: {}` → plain system background —
  HIG-compliant, no flash, but unbranded). `SHIP_PLAN.md` Track 2.
- `DEVELOPMENT_TEAM` isn't set in `project.yml` — add your Team ID there or pick
  it in Xcode's Signing tab for device builds.
- Universal Links need an Associated Domains entitlement + hosted
  apple-app-site-association once there's a production domain; only the
  `squarely://g/:groupId` dev scheme is wired for now.
- `MoneyFormat` assumes 2 decimal minor units for every currency (true for
  INR/USD/EUR/GBP, not for e.g. JPY) — fine for the currencies in the v1
  picker, worth revisiting if more are added.
- The 6-character join code is surfaced both at creation (`CreateGroupView`'s
  confirmation step) and, since the `DESIGN.md` §2/§12 contract change, from
  Group Home's Share & Export menu (`GroupSummary.joinCode` is now returned by
  `GET /api/groups/:groupId`).
- No "leave group" / "switch group" affordance for a group that still exists —
  `RootView`'s v1 model is a single active group, replaced by joining/opening
  another. (A group that has been *deleted* server-side is handled: Group Home
  detects the 404 and `RootView` falls back to the Start screen — see
  `GroupViewModel.groupUnavailable` / `RootView.leaveGroup`, covered by
  `SquarelyTests`.)
- Dark mode: reviewed, not changed. `BalanceHeroView`'s green/red and the rest
  of the UI all use system-adaptive colors (`.green`, `.red`, `.secondary`),
  which already adjust for dark mode automatically — nothing needed fixing.
- Offline/empty states: reviewed, considered adequate for v1.
  `GroupHomeView` already shows a full-screen spinner on first load and an
  inline error row on failure, consistent with `DESIGN.md` §9 ("design loading
  states as normal, not something to hide"). A dedicated offline banner was
  deliberately not added — nothing here has been exercised against a real
  network yet, so a heavier "offline mode" is easy to over-build blind.

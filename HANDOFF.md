# ClanTab iOS — Handoff Guide

## ▶ Status (2026-09-03) — Feature batch + accounts, code-complete

Since the 2026-08-31 block below, all of `FEATURE_BACKLOG.md`'s independent
features and the accounts phase have shipped **in code** (all on `main`,
`make check` green each commit):

- **Feature batch** (2026-09-01/02): percentage splits (schema v2), categories
  + icons (v3), Spending Insights (`ClanTabKit.Insights` + SwiftUI Charts),
  activity search/filter (`ActivityFiltering`), multi-currency ledgers (v4,
  per-currency, **no FX**), CSV import (ClanTab + Splitwise). Branding: app
  icon, launch screen, wordmark (`docs/branding/`), support page
  (`docs/support.html`, published at `/support.html`), App Store screenshots
  (`docs/appstore/screenshots/`).
- **Accounts** (2026-09-03) — optional Sign in with Apple, guests unchanged.
  `GroupDO` schema **v5** (`members.identity_sub`) + new **`UserDO`**; stateless
  30-day session tokens; `/api/auth/*` + claim routes (**`DESIGN.md` §13**).
  iOS: SIWA on the start screen, Keychain session, multi-group model
  (`KnownGroupsStore`), "This is me" claim flow, one-time sync nudge, Settings +
  Delete Account. Full build log: `ACCOUNTS_DESIGN.md` §14. Worker is at **103
  tests**; ClanTabKit ~110; ClanTabTests ~49.
- **Not done — owner tasks** (`ACCOUNTS_DESIGN.md` §16 / `READINESS_CHECKLIST.md`):
  deploy the worker (the live instance is still pre-accounts) +
  `wrangler secret put SESSION_SIGNING_KEY`; enable Sign in with Apple on the
  App ID; add the `SIWA_*` secrets + wire Apple token revocation into
  `DELETE /api/auth/account`; TestFlight pass on a real device (SIWA can't run
  in the simulator); privacy-policy + App Privacy updates for SIWA.

The 2026-08-31 block and everything below it is still accurate as history.

## ▶ Status (2026-08-31) — First TestFlight Build Uploaded

**iOS track**: Phases 0-7 done (`v0.1.0`). The app builds + passes
`ClanTabTests` via `make check` / the pre-push hook, ran end-to-end on an iOS
Simulator (see "App/ Runtime Verification — Done"), and `README.md` has
screenshots + an architecture diagram.

**Backend track** (`worker/`, tracked in `BACKEND_PLAN.md`): **complete
(§1-§8)**. The Cloudflare Worker + RegistryDO + GroupDO implement `DESIGN.md`
§2's full API (54 worker tests), **deployed and live at
`https://clantab.nakka-labs.workers.dev`**, and the iOS app is verified
end-to-end against the deployed URL. `AppConfig.apiBaseURL` points at it.
**Repo tagged `v0.2.0`** ("iOS app + backend, working end to end").

**Ship track** (`SHIP_PLAN.md`): **Track 2 largely done.** As of 2026-08-31:
- Repo is **public** (`nakka-labs/clantab-ios`) — GitHub Actions and Pages are
  now unmetered; the "Actions minutes drained" problem in Track 3.0 is gone.
- Apple App ID `com.clantab.app` registered; App Store Connect app "ClanTab"
  created; `DEVELOPMENT_TEAM: UK652GNPP7` + `CODE_SIGN_STYLE: Automatic` +
  `ITSAppUsesNonExemptEncryption: false` in `project.yml`.
- `MARKETING_VERSION` = `1.0` (matches the App Store Connect version record).
- **Build `1.0 (1)` archived in Xcode and uploaded to App Store Connect**
  (2026-08-31); processed; internal test group `test-team` created.
- Privacy policy **live** at `https://nakka-labs.github.io/clantab-ios/`
  (published by `.github/workflows/pages.yml`).

**Next up:** add an internal tester to `test-team`, install via TestFlight,
run the on-device end-to-end pass against the production Worker, then tag
`v0.4.0`. Still open: `CLOUDFLARE_API_TOKEN` repo secret (tag-deploy CI), a
real app icon, App Store screenshots + App Privacy answers (external testing /
submission only), and Track 1 (custom domain + Universal Links — optional,
invites work by 6-char code today).

The balance/simplify logic now lives in two languages kept in lockstep by
`test-fixtures/balances/` (run by both `swift test` and `npm --prefix worker
test`). The `joinCode` contract change is in: `GET /api/groups/:groupId`
returns it, iOS `GroupSummary` carries it, Group Home re-shares it.

**Repo moved**: the repo now lives at `nakka-labs/clantab-ios` (was
`indra-nakka/clantab-ios` — see Phase 0's checklist below for that original
name, still accurate as history). `origin` in this local clone and the
GitHub repo description are already updated; a fresh clone should use
`https://github.com/nakka-labs/clantab-ios.git`.

**If picking this up:**

1. **Enable the local checks**: `make hooks` (installs the pre-push hook), then
   `make check` runs everything (ClanTabKit + worker + iOS build/tests). The
   macOS Actions job is gone — see "App/ Build + Test Check" below.
2. **Open the app**: `cd App && xcodegen generate && open ClanTab.xcodeproj`
   (the `.xcodeproj` + `ClanTab/Info.plist` are gitignored — regenerate, never
   edit). Backend: `make worker-dev` (serves `:8787`) or work against the
   deployed `AppConfig.apiBaseURL`.
3. **The current focus is `SHIP_PLAN.md`** — TestFlight. The App ID, App Store
   Connect record, signing, and the first build upload are **done** (see the
   status block above). What's left: install via TestFlight and do the
   on-device pass, add the `CLOUDFLARE_API_TOKEN` repo secret, a real app icon,
   and the App Store listing (screenshots + App Privacy) before submission.

## Phase 0 Checklist — Completed
- [x] Private GitHub repository created (`indra-nakka/clantab-ios`)
- [x] Root configs in place (`.gitignore`, `LICENSE`, `Makefile`, `AGENTS.md`, `README.md`, `PLAN.md`, `HANDOFF.md`, `.github/workflows/test.yml`)
- [x] `ClanTabKit` SwiftPM package scaffolded with passing baseline tests on Windows
- [x] Initial commit pushed to `main`

## Phase 1 Checklist — Completed
- [x] `Model/`: `Group`, `Member`, `Expense`, `ExpenseSplit`, `SplitType`, `Settlement`, `Balance`, `SimplifiedSettlement`
- [x] `Logic/Balances.swift`: pure derivation of net balances from expenses & settlements
- [x] `Logic/Simplify.swift`: greedy debt-simplification, deterministic tie-breaking by `memberId`
- [x] `Logic/Validation.swift`: split-sum validation, member/amount checks, deterministic remainder allocation
- [x] `Tests/ClanTabKitTests/`: 25 tests incl. triangle collapse, single-payer, 100÷3 remainder, zero-balance/settled, idempotency, and seeded fuzz (200 iterations each in `Simplify`/`Validation`) — all passing via `swift test --package-path ClanTabKit`

## Phase 2 Checklist — Completed
- [x] `Storage/IdentityStore.swift`: `GroupIdentity`, `IdentityStoring` protocol, `UserDefaultsIdentityStore` (namespaced `"clantab:<groupId>"`), `InMemoryIdentityStore` for tests/previews
- [x] `Network/ClanTabTransport.swift`: `ClanTabTransport` protocol + `URLSessionTransport` default — request encoding/decoding is tested against a fake conforming to this protocol rather than stubbing `URLProtocol` (simpler, fully portable, no reliance on platform URL-loading internals)
- [x] `Network/ClanTabClientError.swift`, `ClanTabWireTypes.swift`, `ClanTabClient.swift`: full API contract from `DESIGN.md` §2 — `createGroup`, `resolveJoinCode`, `joinGroup`, `fetchGroupState`, `addExpense`, `addSettlement` — as an `actor`, decoding the `{ error: { code, message } }` envelope into `ClanTabClientError.server`, a bare 404 into `.notFound`. `id?` fields are encoded via a custom `encode(to:)` that omits the key entirely when nil, matching the wire contract exactly.
- [x] `Tests/ClanTabKitTests/`: 12 new tests (`ClanTabClientTests`, `IdentityStoreTests`) covering request/response shape, structured vs. bare error handling, idempotency-id encoding, and full `GroupStateResponse` decoding — 37 tests total, all passing via `swift test --package-path ClanTabKit`
- Verified on this machine that both `URLSession` (real network round-trip) and `UserDefaults` (suite-backed roundtrip) work correctly under SwiftPM on the Windows Swift 6.3.3 toolchain before committing to this design.

## Phase 3 Checklist — Completed; compiles (CI) and run-verified 2026-08-28 (see "App/ Runtime Verification — Done")
- [x] `App/project.yml`: XcodeGen config (chosen over a hand-authored `.xcodeproj`,
  which can't be safely written blind on Windows — a plain YAML file can).
  `App/README.md` has setup steps (`brew install xcodegen && xcodegen generate`).
- [x] `ClanTabApp.swift` / `AppRoute.swift` / `RootView.swift`: entry point and
  navigation state (start / createGroup / joinGroup / group), incl. `onOpenURL`
  handling for both `clantab://g/:groupId` (dev scheme, testable now) and the
  real `https://<host>/g/:groupId` shape (Universal Links entitlement still
  needed once there's a production domain).
- [x] `Screens/CreateGroupView.swift`, `JoinGroupView.swift`: wired to
  `ClanTabClient` + `IdentityStore`.
- [x] `Screens/GroupHomeView.swift` + `ViewModels/GroupViewModel.swift`: balance
  hero, member list, merged expense/settlement activity feed. Fetch-on-load,
  pull-to-refresh, no optimistic UI, per `DESIGN.md` §7.
- [x] `Components/`: `BalanceHeroView`, `MemberBalanceRow`, `ActivityRow`,
  `MoneyFormat`, `ClientErrorMessage`.
- [x] Compiled (CI) and run-verified 2026-08-28 — the "specific things most
  likely to need a fix" flagged when this was written blind (Picker tagging,
  `@State`/`@Observable` wiring, deep-link parsing) all work at runtime. See
  "App/ Runtime Verification — Done".
- ClanTabKit's own test suite is untouched and still green (37/37,
  `swift test --package-path ClanTabKit`).

## Phase 4 Checklist — Completed; compiles (CI) and run-verified 2026-08-28
- [x] `Screens/AddExpenseView.swift`: amount entry (parsed to integer minor
  units via `MoneyFormat.minorUnits(from:)` — string/integer math, no
  `Double`), payer picker, description, equal-vs-exact split UI. The equal
  split delegates to `Validation.equalSplit` (remainder to the payer) rather
  than reimplementing division; the exact split shows a live "unassigned /
  over the total" indicator and reuses `Validation.validateSplitsSum` as a
  client-side check before the request is even sent (DESIGN.md §6).
- [x] Wired into `GroupHomeView` via a toolbar `+` button → sheet →
  `client.addExpense` → `viewModel.refetch()` — no optimistic UI, same pattern
  as the rest of Group Home.
- [x] Client-generates the idempotency `id` (`UUID().uuidString`) per
  `DESIGN.md` §2.
- [x] `Components/ClientErrorMessage.swift` extended to translate
  `ValidationError` cases too, not just `ClanTabClientError`.
- Built on top of Phase 3's then-unverified App/ code by explicit choice —
  all verified together in the 2026-08-28 Xcode session rather than pausing
  mid-stream. ClanTabKit's own suite remains untouched and green (37/37).

---

## Phase 5 Checklist — Completed; compiles (CI) and run-verified 2026-08-28
- [x] `Screens/SettleUpView.swift`: renders `GroupStateResponse.simplifiedSettlements`
  (server-computed per `DESIGN.md` §2 — never recomputed client-side) as
  minimal "X pays Y — ₹amount" cards, each with a 1-tap "Mark as Paid".
  Takes the *same* `GroupViewModel` instance `GroupHomeView` holds (not a
  static snapshot), so marking one paid → `refetch()` naturally refreshes
  this list with the server's newly recomputed plan.
- [x] "Mark as Paid" calls `client.addSettlement` with a client-generated
  idempotency `id` (`UUID().uuidString`, same pattern as Phase 4), then
  `viewModel.refetch()` — no optimistic UI.
- [x] Wired into `GroupHomeView`: a "Settle Up" row appears right under the
  balance hero, only when `simplifiedSettlements` is non-empty, opening
  `SettleUpView` as a sheet.
- Built on top of Phases 3-4's then-unverified `App/` code, by the same
  explicit choice as Phase 4 — all verified together in the 2026-08-28 Xcode
  session. ClanTabKit's own suite remains untouched and green (37/37).

---

## App/ Build + Test Check — local pre-push hook

Originally a GitHub Actions **macOS** runner (`ios-build.yml`) did the iOS
build, because development was on Windows. Now that there's a Mac, that moved
local — at the time the repo was private and macOS Actions minutes (10× rate)
had drained the account's free pool. The repo is **public** now, so
GitHub-hosted runners (macOS included) are unmetered again and a macOS CI job
could be re-added; the `pre-push` hook is kept anyway for fast local feedback
without waiting on CI. **`make hooks`** points `core.hooksPath` at
`.githooks/`; the `pre-push` hook then runs, before every push, the checks
relevant to what's being pushed:

- `swift test --package-path ClanTabKit` (if `ClanTabKit/` or `test-fixtures/`)
- `worker` typecheck + tests (if `worker/` or `test-fixtures/`)
- `xcodegen generate` + `xcodebuild test` for the `ClanTab` scheme, which
  builds the app and runs `ClanTabTests` (if `App/` or `ClanTabKit/`)

`make check` runs all of it unconditionally. Bypass with `SKIP_CHECKS=1` or
`SKIP_APP_CHECK=1`. The two cloud workflows — `test.yml` (ClanTabKit) and
`worker.yml` (Worker) — are Linux-only and, on a public repo, unmetered;
`worker-deploy.yml` runs on `v*` tags. `pages.yml` publishes the privacy
policy.

**The `ios-build.yml` era closed Phases 3-6's biggest open risk.** It found
and fixed three real build errors on its first run:
1. `CreateGroupView`: a `private` nested `Stage` enum extended from a
   same-file `extension CreateGroupView.Stage { }` — Swift's `private` grants
   access to extensions of the *enclosing* declaration, not extensions of the
   private nested type itself. Fixed by moving the computed property inside
   `Stage`'s own body.
2. `AddExpenseView`: a `switch` mixed directly into a `Section`'s content
   closure alongside a `Picker` made the compiler pick SwiftUI's *Table*-
   oriented `Section` overload instead of the plain one ("generic parameter
   'V' could not be inferred"). Fixed by extracting the switch into its own
   `@ViewBuilder` computed property (`splitDetail`), giving the type checker a
   smaller, independent boundary — the standard fix for this class of SwiftUI
   type-checking failure.
3. `AddExpenseView`: a ternary `amountMinor == exactSplitsTotal ? .secondary
   : .red` failed to unify — `.secondary` is `HierarchicalShapeStyle`, `.red`
   only exists on `Color`. Fixed by naming both branches `Color.secondary` /
   `Color.red` explicitly.

**What CI doesn't prove** (and what the runtime pass below now covers):
navigation, sheet presentation, form validation, and deep-link behaviour at
runtime — none of which compilation says anything about.

## App/ Runtime Verification — Done (2026-08-28)

First interactive run of `App/`, on an **iOS 26.5 Simulator (Xcode 26.6,
iPhone 17 Pro)**, driven end-to-end by a temporary XCUITest (added, run,
then removed — not in the repo) with assertions + screenshots at each step.
Because the Worker backend is out of scope, the app was pointed at a
**local in-memory mock of the `DESIGN.md` §2 API** (a throwaway script that
ports `ClanTabKit/Logic`'s balance + greedy-simplify so Group Home rendered
real numbers). Two temporary local changes for the run — `AppConfig.apiBaseURL`
→ `http://localhost:8787/` and an `NSAllowsLocalNetworking` ATS exception —
were **both reverted**.

**Verified working at runtime (all asserted, all pass):**
- Start screen; Create Group form (text entry, currency picker, `canSubmit`
  gating, submission); post-create confirmation (join code shown once,
  Share Code / Share Invite Link).
- Group Home: balance hero (green/red), member balances, merged activity
  feed, nav title, **resume-into-group on relaunch**, pull-to-refresh.
- Add Expense sheet: amount parsing, payer picker, equal split, submit →
  `refetch()` → feed updates.
- Settle Up sheet: server `simplifiedSettlements` rendered, "Mark as Paid" →
  `addSettlement` → list recomputes and the settled row drops out.
- Share & Export menu: invite link + Export CSV + Export JSON (`ShareLink`).
- Join by code: resolve + graceful "That group or code couldn't be found."
  on an unknown code.
- `.sensoryFeedback` haptics fire (Simulator logs the expected
  no-haptics-device error — confirms the call path).
- **No SwiftUI runtime warnings** (no AttributeGraph cycles, no "publishing
  changes from within view updates", no constraint errors), no crashes.
  Console is clean apart from standard Simulator keyboard/haptic noise.

`swift test --package-path ClanTabKit` stayed green (46/46) throughout.

Screenshots (15) were saved outside the repo at
`../clantab-runtime-verification-shots/` — curate a few into `README.md`
for Phase 7 rather than committing the raw set.

**Findings:**
1. **`.gitignore` gap (fixed).** `xcodegen generate` writes
   `App/ClanTab/Info.plist` from `project.yml`'s `info` block, but it
   wasn't ignored. Added `App/ClanTab/Info.plist` to `.gitignore` — the one
   uncommitted change. `App/README.md`'s "never edit it directly" note about
   the `.xcodeproj` applies to this file too.
2. **Resume-into-deleted-group dead end (UX, pre-existing) — FIXED
   2026-08-28.** If `lastGroupId` pointed at a group that no longer exists
   server-side, the app resumed into it and showed only a small "Group not
   found." row with no way back. Now `GroupViewModel` sets `groupUnavailable`
   when `fetchGroupState` returns a 404 (bare `notFound` or a structured
   `GROUP_NOT_FOUND`), and `RootView.leaveGroup` clears `lastGroupId` and
   routes back to Start. Only a definitive 404 triggers this — transient
   connection errors leave the user on Group Home with the retry affordances,
   by design. Covered by `ClanTabTests/GroupViewModelTests` and confirmed at
   runtime (restart the mock empty → same groupId 404s → app lands on Start).
   Note this only handles a *deleted* group; there is still no "leave"/"switch"
   action for a group that still exists (v1's single-active-group model).
3. **Deep link — parsing now unit-tested.** `clantab://g/<id>` is registered
   and the OS routes it to the app (the "Open in ClanTab?" confirm dialog
   appeared in the runtime pass; the in-app result wasn't visually confirmed —
   no reliable Simulator tap tool for the SpringBoard dialog here). The pure
   pieces are now covered: `RootView.extractGroupId` and the extracted
   `RootView.resolveDeepLink(_:hasIdentity:)` have 11 tests in
   `ClanTabTests/RootViewDeepLinkTests`.

## Phase 6 Checklist — Completed; compiles (CI) and run-verified 2026-08-28
- [x] `ClanTabKit/Export/Export.swift`: CSV and JSON ledger export as pure
  functions - `Export.csv` (money via integer-math decimal strings, RFC 4180
  escaping, sorted oldest-first) and `Export.json` (a complete pretty-printed
  snapshot). Genuinely testable, so it got 9 real tests
  (`Tests/ClanTabKitTests/ExportTests.swift`) - 46 tests total, all passing.
- [x] `Components/ExportFile.swift` (App): writes `Export`'s output to a temp
  file so `ShareLink(item: url)` shares it as a real named `.csv`/`.json` file.
- [x] `GroupHomeView`'s new "Share & Export" toolbar menu: invite link, CSV,
  and JSON, all via `ShareLink`.
- [x] `CreateGroupView` gained a post-creation confirmation stage — the *only*
  place the 6-character join code is available (`DESIGN.md` §2's
  `GET /api/groups/:groupId` doesn't return it) — with `ShareLink` for both
  the code and the capability link.
- [x] Haptic feedback (`.sensoryFeedback(.success, trigger:)`, iOS 17+) on
  expense-added and settlement-marked-paid, wired through `SettleUpView`'s new
  `onSettled` callback.
- [x] Dark mode and offline/empty states: reviewed, no changes needed - see
  `App/README.md`'s "Known gaps" for the reasoning on each.
- Built on top of Phases 3-5's `App/` code; all of it (Phases 3-6) compiles
  cleanly per the CI check above and was run-verified end-to-end on
  2026-08-28 — see "App/ Runtime Verification — Done".

---

## Phase 7 Prompt (Copy-Paste for After App/ Is Verified)

```text
Read PLAN.md, DESIGN.md, and AGENTS.md.

We are starting Phase 7: Ship & Documentation - the last phase in PLAN.md's
roadmap.

1. Polish README.md with an architecture diagram (mermaid is fine) and
   screenshots once the App/ Verification pass has produced a running build to
   screenshot.
2. Review AGENTS.md/PLAN.md/DESIGN.md/HANDOFF.md for drift against what
   actually got built across Phases 1-6, and correct anything stale.
3. Tag a release (e.g. `v0.1.0`) once the App/ Verification prompt has been
   run and the build actually works end-to-end against a real backend - note
   that the Cloudflare Worker backend itself (DESIGN.md's whole API surface)
   hasn't been built yet in this repo. Decide whether "Ship" for v0.1.0 means
   shipping the iOS app against a real deployed Worker, or whether the Worker
   is a separate, not-yet-started piece of work - PLAN.md doesn't currently
   have a phase for building it.

Keep `swift test --package-path ClanTabKit` green throughout.
```

## Phase 7 Status — Docs Reviewed, App/ Run-Verified, README Illustrated; Only the Tag Is Left

Standing decision at the time (**since reversed**):
- ~~Backend is a separate, later effort, out of scope for this roadmap~~ — the
  Worker was built next (`worker/`, `BACKEND_PLAN.md`) and deployed;
  `AppConfig.apiBaseURL` points at it.

What got done:
- [x] Drift review across `AGENTS.md`/`DESIGN.md`/`README.md` against what
  Phases 1-6 actually built. Found and fixed real drift: `DESIGN.md` §5's
  sequence diagrams and §7 described a hypothetical web client (React
  `useGroup`, `identity.ts`/`localStorage`) that was never built in this
  repo — corrected to describe the actual `GroupViewModel` /
  `UserDefaultsIdentityStore`. Recorded the join-code API gap (found in
  Phase 6) in `DESIGN.md` §12 for whoever eventually builds the backend.
  `AGENTS.md` now flags `App/`'s macOS/Xcode requirement in its Commands
  section.
- [x] **App/ CI Build Check** passes — `App/` compiles cleanly (after fixing
  three real errors it caught).
- [x] **App/ Runtime Verification pass (2026-08-28)** — the app has now been
  run end-to-end on an iOS 26.5 Simulator; every Phase 3-6 screen and flow
  exercised and asserted, no runtime warnings or crashes. Full details +
  findings in "App/ Runtime Verification — Done" above.
- [x] Screenshots + a mermaid architecture diagram in `README.md` (2026-08-28).
  Five curated screenshots committed under `docs/screenshots/` (resized to
  360px wide) with a `## Screenshots` table; a `flowchart` diagram under
  `## Architecture Overview` shows the ClanTabKit-core / App-shell /
  out-of-scope-Worker split.
- [x] Acted on both runtime-pass findings (2026-08-28): fixed the
  resume-into-deleted-group dead end (`GroupViewModel.groupUnavailable` +
  `RootView.leaveGroup`), and added the first `App/` unit-test target
  (`ClanTabTests`, 17 tests) for deep-link parsing and group-not-found
  detection — run by the local `pre-push` hook (was `ios-build.yml` at the
  time; that macOS workflow was later retired).
- [x] Release tag: **done**. `v0.1.0` (iOS app standalone, 2026-08-28),
  `v0.2.0` (app + backend end to end), `v0.3.0` (ClanTab rebrand +
  foreground auto-refresh) are all tagged.

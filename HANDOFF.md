# Squarely iOS — Handoff Guide

## ▶ Status (2026-08-28) — App + Backend Live End-to-End; `v0.2.0` Tagged

**iOS track**: Phases 0-7 done, **`v0.1.0` tagged**. The app compiles (CI),
ran end-to-end on an iOS Simulator (see "App/ Runtime Verification — Done"),
has `SquarelyTests` + SquareKit's suite, and `README.md` has screenshots +
an architecture diagram.

**Backend track** (`worker/`, tracked in `BACKEND_PLAN.md`): **complete
(§1-§8)**. The Cloudflare Worker + RegistryDO + GroupDO implement `DESIGN.md`
§2's full API (54 worker tests), **deployed and live at
`https://squarely.nakka-labs.workers.dev`**, and the iOS app is verified
end-to-end against the deployed URL. `AppConfig.apiBaseURL` points at it.
**Repo tagged `v0.2.0`** ("iOS app + backend, working end to end").

Left, all unstarted: a real landing page + Universal Links (needs a production
domain), shipping the iOS app (icon + device + TestFlight), WebSocket live
updates. See `BACKEND_PLAN.md`'s tail.

The balance/simplify logic now lives in two languages kept in lockstep by
`test-fixtures/balances/` (run by both `swift test` and `npm --prefix worker
test`). The `joinCode` contract change is in: `GET /api/groups/:groupId`
returns it, iOS `GroupSummary` carries it, Group Home re-shares it.

**Repo moved**: the repo now lives at `nakka-labs/squarely-ios` (was
`indra-nakka/squarely-ios` — see Phase 0's checklist below for that original
name, still accurate as history). `origin` in this local clone and the
GitHub repo description are already updated; a fresh clone should use
`https://github.com/nakka-labs/squarely-ios.git`.

**If picking this up:**

1. Core suite: `swift test --package-path SquareKit`. App: `cd App &&
   xcodegen generate && open Squarely.xcodeproj` (`.xcodeproj` +
   `Squarely/Info.plist` gitignored — regenerate, never edit). Backend:
   `make worker-test` / `make worker-dev` (Node; `npm --prefix worker ci` first).
2. **§8 deploy needs you**: a Cloudflare account, then `npx --prefix worker
   wrangler login`, `make worker-deploy`, point `App/Squarely/AppConfig.swift`'s
   `apiBaseURL` at the deployed URL (its first real value), and re-run the iOS
   verification against production. See `BACKEND_PLAN.md` §8.
3. To develop against the backend locally in the meantime: `make worker-dev`
   (serves `:8787`) + temporarily set `apiBaseURL` to `http://localhost:8787/`.
4. For TestFlight: Signing & Capabilities → your enrolled Developer Program
   Team; add an app icon; run on a device.

## Phase 0 Checklist — Completed
- [x] Private GitHub repository created (`indra-nakka/squarely-ios`)
- [x] Root configs in place (`.gitignore`, `LICENSE`, `Makefile`, `AGENTS.md`, `README.md`, `PLAN.md`, `HANDOFF.md`, `.github/workflows/test.yml`)
- [x] `SquareKit` SwiftPM package scaffolded with passing baseline tests on Windows
- [x] Initial commit pushed to `main`

## Phase 1 Checklist — Completed
- [x] `Model/`: `Group`, `Member`, `Expense`, `ExpenseSplit`, `SplitType`, `Settlement`, `Balance`, `SimplifiedSettlement`
- [x] `Logic/Balances.swift`: pure derivation of net balances from expenses & settlements
- [x] `Logic/Simplify.swift`: greedy debt-simplification, deterministic tie-breaking by `memberId`
- [x] `Logic/Validation.swift`: split-sum validation, member/amount checks, deterministic remainder allocation
- [x] `Tests/SquareKitTests/`: 25 tests incl. triangle collapse, single-payer, 100÷3 remainder, zero-balance/settled, idempotency, and seeded fuzz (200 iterations each in `Simplify`/`Validation`) — all passing via `swift test --package-path SquareKit`

## Phase 2 Checklist — Completed
- [x] `Storage/IdentityStore.swift`: `GroupIdentity`, `IdentityStoring` protocol, `UserDefaultsIdentityStore` (namespaced `"squarely:<groupId>"`), `InMemoryIdentityStore` for tests/previews
- [x] `Network/SquarelyTransport.swift`: `SquarelyTransport` protocol + `URLSessionTransport` default — request encoding/decoding is tested against a fake conforming to this protocol rather than stubbing `URLProtocol` (simpler, fully portable, no reliance on platform URL-loading internals)
- [x] `Network/SquarelyClientError.swift`, `SquarelyWireTypes.swift`, `SquarelyClient.swift`: full API contract from `DESIGN.md` §2 — `createGroup`, `resolveJoinCode`, `joinGroup`, `fetchGroupState`, `addExpense`, `addSettlement` — as an `actor`, decoding the `{ error: { code, message } }` envelope into `SquarelyClientError.server`, a bare 404 into `.notFound`. `id?` fields are encoded via a custom `encode(to:)` that omits the key entirely when nil, matching the wire contract exactly.
- [x] `Tests/SquareKitTests/`: 12 new tests (`SquarelyClientTests`, `IdentityStoreTests`) covering request/response shape, structured vs. bare error handling, idempotency-id encoding, and full `GroupStateResponse` decoding — 37 tests total, all passing via `swift test --package-path SquareKit`
- Verified on this machine that both `URLSession` (real network round-trip) and `UserDefaults` (suite-backed roundtrip) work correctly under SwiftPM on the Windows Swift 6.3.3 toolchain before committing to this design.

## Phase 3 Checklist — Completed; compiles (CI) and run-verified 2026-08-28 (see "App/ Runtime Verification — Done")
- [x] `App/project.yml`: XcodeGen config (chosen over a hand-authored `.xcodeproj`,
  which can't be safely written blind on Windows — a plain YAML file can).
  `App/README.md` has setup steps (`brew install xcodegen && xcodegen generate`).
- [x] `SquarelyApp.swift` / `AppRoute.swift` / `RootView.swift`: entry point and
  navigation state (start / createGroup / joinGroup / group), incl. `onOpenURL`
  handling for both `squarely://g/:groupId` (dev scheme, testable now) and the
  real `https://<host>/g/:groupId` shape (Universal Links entitlement still
  needed once there's a production domain).
- [x] `Screens/CreateGroupView.swift`, `JoinGroupView.swift`: wired to
  `SquarelyClient` + `IdentityStore`.
- [x] `Screens/GroupHomeView.swift` + `ViewModels/GroupViewModel.swift`: balance
  hero, member list, merged expense/settlement activity feed. Fetch-on-load,
  pull-to-refresh, no optimistic UI, per `DESIGN.md` §7.
- [x] `Components/`: `BalanceHeroView`, `MemberBalanceRow`, `ActivityRow`,
  `MoneyFormat`, `ClientErrorMessage`.
- [x] Compiled (CI) and run-verified 2026-08-28 — the "specific things most
  likely to need a fix" flagged when this was written blind (Picker tagging,
  `@State`/`@Observable` wiring, deep-link parsing) all work at runtime. See
  "App/ Runtime Verification — Done".
- SquareKit's own test suite is untouched and still green (37/37,
  `swift test --package-path SquareKit`).

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
  `ValidationError` cases too, not just `SquarelyClientError`.
- Built on top of Phase 3's then-unverified App/ code by explicit choice —
  all verified together in the 2026-08-28 Xcode session rather than pausing
  mid-stream. SquareKit's own suite remains untouched and green (37/37).

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
  session. SquareKit's own suite remains untouched and green (37/37).

---

## App/ CI Build + Test Check — Passing (`.github/workflows/ios-build.yml`)

Originally no Mac was available here, so a GitHub Actions macOS runner does
the parts that need Xcode. On every push touching `App/**` it runs
`xcodegen generate`, then `xcodebuild build -destination 'generic/platform=iOS
Simulator'`, then `xcodebuild test -only-testing:SquarelyTests` on whatever
iPhone simulator the runner has — no code signing needed. Check status:
`gh run list --workflow=ios-build.yml`.

**This closed the loop on Phases 3-6's biggest open risk.** It found and fixed
three real build errors on the very first run:
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
ports `SquareKit/Logic`'s balance + greedy-simplify so Group Home rendered
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

`swift test --package-path SquareKit` stayed green (46/46) throughout.

Screenshots (15) were saved outside the repo at
`../squarely-runtime-verification-shots/` — curate a few into `README.md`
for Phase 7 rather than committing the raw set.

**Findings:**
1. **`.gitignore` gap (fixed).** `xcodegen generate` writes
   `App/Squarely/Info.plist` from `project.yml`'s `info` block, but it
   wasn't ignored. Added `App/Squarely/Info.plist` to `.gitignore` — the one
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
   by design. Covered by `SquarelyTests/GroupViewModelTests` and confirmed at
   runtime (restart the mock empty → same groupId 404s → app lands on Start).
   Note this only handles a *deleted* group; there is still no "leave"/"switch"
   action for a group that still exists (v1's single-active-group model).
3. **Deep link — parsing now unit-tested.** `squarely://g/<id>` is registered
   and the OS routes it to the app (the "Open in Squarely?" confirm dialog
   appeared in the runtime pass; the in-app result wasn't visually confirmed —
   no reliable Simulator tap tool for the SpringBoard dialog here). The pure
   pieces are now covered: `RootView.extractGroupId` and the extracted
   `RootView.resolveDeepLink(_:hasIdentity:)` have 11 tests in
   `SquarelyTests/RootViewDeepLinkTests`.

## Phase 6 Checklist — Completed; compiles (CI) and run-verified 2026-08-28
- [x] `SquareKit/Export/Export.swift`: CSV and JSON ledger export as pure
  functions - `Export.csv` (money via integer-math decimal strings, RFC 4180
  escaping, sorted oldest-first) and `Export.json` (a complete pretty-printed
  snapshot). Genuinely testable, so it got 9 real tests
  (`Tests/SquareKitTests/ExportTests.swift`) - 46 tests total, all passing.
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

Keep `swift test --package-path SquareKit` green throughout.
```

## Phase 7 Status — Docs Reviewed, App/ Run-Verified, README Illustrated; Only the Tag Is Left

Standing decisions (explicit calls, not defaults to revisit lightly):
- **Backend is a separate, later effort** — out of scope for this roadmap.
  Continue developing/testing the iOS app against `AppConfig.apiBaseURL`'s
  placeholder (or a local mock) until a real Worker exists elsewhere.

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
  `## Architecture Overview` shows the SquareKit-core / App-shell /
  out-of-scope-Worker split.
- [x] Acted on both runtime-pass findings (2026-08-28): fixed the
  resume-into-deleted-group dead end (`GroupViewModel.groupUnavailable` +
  `RootView.leaveGroup`), and added the first `App/` unit-test target
  (`SquarelyTests`, 17 tests) for deep-link parsing and group-not-found
  detection — now also run by `ios-build.yml`.
- [ ] Release tag: **not done**. `App/` now both compiles and runs standalone
  against a mock backend, so `v0.1.0` could reasonably mean "the iOS app
  works standalone" without waiting on the Worker — that's the call to make.

# Squarely iOS — Handoff Guide

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

## Phase 3 Checklist — Completed, Build UNVERIFIED (needs macOS/Xcode)
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
- [ ] **Not yet verified**: no Xcode/macOS was available this session, so none of
  this has actually been compiled. Treat the first `xcodegen generate` + build
  in Xcode as real verification, not a formality — see `App/README.md`'s "Known
  gaps" for the specific things most likely to need a fix (Picker tagging,
  `@State`/`@Observable` wiring, deep link parsing).
- SquareKit's own test suite is untouched and still green (37/37,
  `swift test --package-path SquareKit`).

## Phase 4 Checklist — Completed, Build UNVERIFIED (same caveat as Phase 3)
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
- Built on top of Phase 3's still-unverified App/ code, by explicit choice —
  both will be verified together in one Xcode session rather than pausing
  mid-stream. SquareKit's own suite remains untouched and green (37/37).

---

## Phase 5 Checklist — Completed, Build UNVERIFIED (same caveat as Phases 3-4)
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
- Built on top of Phases 3-4's still-unverified `App/` code, by the same
  explicit choice as Phase 4 — all three will be verified together in one
  Xcode session. SquareKit's own suite remains untouched and green (37/37).

---

## App/ Verification Prompt (Run This First, on macOS — Covers Phases 3-5)

```text
Read App/README.md.

Before starting Phase 7, verify the App/ target actually builds - Phases 3
through 6 were all scaffolded on Windows with no Xcode available, so none of
it has been compiled yet.

1. brew install xcodegen (if needed), then `cd App && xcodegen generate`.
2. Open Squarely.xcodeproj, select an iOS 17+ Simulator, and build.
3. Fix whatever Xcode's compiler flags - likely candidates: Picker/ForEach tag
   inference (currency picker, split-type segmented picker), @Observable +
   @State wiring across GroupHomeView/SettleUpView sharing one view model, the
   switch-over-SplitType inside AddExpenseView's Form, the Stage enum switch
   in CreateGroupView, ToolbarItemGroup + Menu + ShareLink composition in
   GroupHomeView's toolbar, SwiftUI availability on the chosen deployment
   target.
4. Run it. Since there's no backend yet (AppConfig.apiBaseURL is a
   placeholder), Create/Join will fail at the network call - that's expected.
   Confirm the UI itself renders and navigates correctly up to that point,
   including opening the Add Expense and Settle Up sheets and the Share &
   Export menu from Group Home.
5. Keep `swift test --package-path SquareKit` green throughout (46 tests).

Report what broke and what you fixed before moving on to Phase 7.
```

## Phase 6 Checklist — Completed, Build UNVERIFIED (same caveat as Phases 3-5)
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
- Built on top of Phases 3-5's still-unverified `App/` code, same explicit
  choice as before - all four will be verified together in one Xcode session.

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

## Phase 7 Status — Docs Reviewed, Screenshots + Tag Deliberately Blocked

Decided this session (both explicit calls, not defaults to revisit lightly):
- **Backend is a separate, later effort** — out of scope for this roadmap.
  Continue developing/testing the iOS app against `AppConfig.apiBaseURL`'s
  placeholder until a real Worker exists elsewhere.
- **No release tag yet** — tagging implies something that works; nothing in
  `App/` has ever been compiled. Revisit once App/ Verification passes.

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
- [ ] Screenshots and a mermaid architecture diagram in `README.md`: **not
  done**. Screenshots specifically need a build that runs; mermaid diagrams
  don't, but weren't added this pass either.
- [ ] Release tag: **not done**, by design (see above).

**The actual next step is still the App/ Verification Prompt above** — run it
on macOS. Once App/ genuinely builds and runs in Simulator, come back to
finish Phase 7: screenshots, and then decide whether a `v0.1.0` tag makes
sense (it can reasonably describe "the iOS app works standalone against a
placeholder backend" without waiting on the Worker, given that's now
explicitly a separate effort).

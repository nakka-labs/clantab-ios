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

## App/ Verification Prompt (Run This First, on macOS — Covers Phases 3 + 4)

```text
Read App/README.md.

Before starting Phase 5, verify the App/ target actually builds - Phases 3 and
4 were both scaffolded on Windows with no Xcode available, so none of it has
been compiled yet.

1. brew install xcodegen (if needed), then `cd App && xcodegen generate`.
2. Open Squarely.xcodeproj, select an iOS 17+ Simulator, and build.
3. Fix whatever Xcode's compiler flags - likely candidates: Picker/ForEach tag
   inference (both the currency picker and the split-type segmented picker),
   @Observable + @State wiring in GroupHomeView, the switch-over-SplitType
   inside AddExpenseView's Form, SwiftUI availability on the chosen deployment
   target.
4. Run it. Since there's no backend yet (AppConfig.apiBaseURL is a
   placeholder), Create/Join will fail at the network call - that's expected.
   Confirm the UI itself renders and navigates correctly up to that point,
   including opening the Add Expense sheet from Group Home.
5. Keep `swift test --package-path SquareKit` green throughout.

Report what broke and what you fixed before moving on to Phase 5.
```

## Phase 5 Prompt (Copy-Paste for After App/ Is Verified)

```text
Read PLAN.md, DESIGN.md, and AGENTS.md.

We are starting Phase 5: Settle Up Flow.

Implement in the App/ target:
1. `SettleUpView`: render `GroupStateResponse.simplifiedSettlements` (already
   computed server-side, per DESIGN.md §2 - do not recompute simplification
   client-side) as minimal transaction cards ("You owe X ₹500", "Y owes you
   ₹300"), each with a 1-tap "Mark as Paid" action.
2. "Mark as Paid" calls SquarelyClient.addSettlement with a client-generated
   idempotency `id` (per DESIGN.md §2, same pattern as Phase 4's addExpense),
   then GroupViewModel.refetch() - no optimistic UI.
3. Wire a way into SettleUpView from GroupHomeView (toolbar button or a row in
   the existing balance section).

Keep `swift test --package-path SquareKit` green throughout.
```

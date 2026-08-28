# Squarely iOS — Handoff Guide

## ⏸ Session Paused (2026-08-28) — Resume on macOS with Xcode + Apple Developer Program Enrolled

Everything below is pushed to `main` at `e8a50ed` — nothing local, nothing
uncommitted. This whole session ran on Windows (no Mac available), so
everything through Phase 7 was built and CI-verified blind; **nothing has
ever actually run**. That's the very next thing to do.

**Start here, in order:**

1. Read `App/README.md` (build status) and this file's "App/ Runtime
   Verification Prompt" section below in full before touching anything.
2. `cd App && xcodegen generate && open Squarely.xcodeproj`.
3. In Signing & Capabilities, select your now-enrolled Developer Program
   Team. This is new since last session — it unlocks real device signing and
   TestFlight (not just the 7-day free personal-team signing `App/README.md`
   was written assuming), and makes Universal Links (`https://<host>/g/:groupId`)
   viable later if a production domain gets configured. None of that is set up
   yet — this just removes the blocker.
4. Build for Simulator first. It should just work — `.github/workflows/ios-build.yml`
   already verified this compiles (after fixing 3 real errors found there:
   see the "App/ CI Build Check" section below). If Xcode finds something CI
   didn't (CI doesn't catch everything — e.g. asset catalog issues, entitlement
   problems), fix it and push; CI re-verifies on every push to `App/**`.
5. Run the **App/ Runtime Verification Prompt** below — nothing interactive
   has been tested. `AppConfig.apiBaseURL` is still a placeholder, so
   Create/Join will fail at the network call; that's expected (the backend
   is explicitly a separate, later effort — see Phase 7 Status below).
6. Once that passes: finish Phase 7's remaining items (screenshots, a
   mermaid architecture diagram, then decide on a `v0.1.0` tag) — see the
   "Phase 7 Status" section below for exactly what's open.
7. There is no Phase 8 defined anywhere — `PLAN.md`'s roadmap stops at
   Phase 7. Decide what's next only after Phase 7 actually finishes.

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

## App/ CI Build Check — Passing (`.github/workflows/ios-build.yml`)

No Mac was ever available in this development environment (see "how to
test/verify" discussion), so a GitHub Actions macOS runner does the one thing
that genuinely requires Xcode: compiling. It runs `xcodegen generate` +
`xcodebuild -destination 'generic/platform=iOS Simulator'` on every push
touching `App/**` — no code signing needed, since Simulator builds don't
require it. Check status: `gh run list --workflow=ios-build.yml`.

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

**What CI still doesn't prove**: the app has never actually run. Compiling
says nothing about whether navigation, sheet presentation, form validation, or
deep links behave correctly at runtime — that needs an interactive Simulator
or device session, which still needs either macOS access or a signed
CI-built IPA (see the "how to test without a Mac" discussion for the tradeoffs
of each). The prompt below is for whenever that access exists.

## App/ Runtime Verification Prompt (Needs an Interactive Simulator/Device Session)

```text
Read App/README.md and the "App/ CI Build Check" section of HANDOFF.md - the
build itself is already verified by CI, so this is specifically about runtime
behavior, which nothing has exercised yet.

1. cd App && xcodegen generate, open Squarely.xcodeproj, run on an iOS 17+
   Simulator (or a device, if signing is set up).
2. Since there's no backend yet (AppConfig.apiBaseURL is a placeholder),
   Create/Join will fail at the network call - that's expected. Confirm the
   UI itself renders and navigates correctly up to that point: the Start
   screen, Create/Join forms, and opening the Add Expense, Settle Up, and
   Share & Export sheets from Group Home (Group Home itself won't have real
   data without a backend, but the sheets should still present).
3. If anything crashes or misbehaves at runtime (not a compile error - CI
   already covers those), fix it and push; CI will re-verify the compile.
4. Keep `swift test --package-path SquareKit` green throughout (46 tests).

Report what you found before moving on to Phase 7's remaining items
(screenshots, then deciding on a release tag).
```

## Phase 6 Checklist — Completed, Compiles (CI-verified), Not Yet Run
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
- Built on top of Phases 3-5's `App/` code; all of it (Phases 3-6) now
  compiles cleanly per the CI check above. Still not run in a real Simulator
  session - see the Runtime Verification prompt.

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
- **No release tag yet** — tagging implies something that works. `App/` now
  compiles (CI-verified, after this session's fixes), but nobody has actually
  run it — that's a meaningfully different bar than "tagged and shippable."
  Revisit once the Runtime Verification prompt has actually been run.

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

**Update, same session:** the App/ CI Build Check above now passes — `App/`
compiles cleanly, after fixing three real errors it caught. That was the
biggest open risk from Phases 3-6, and it's closed. What's left before
finishing Phase 7 is strictly smaller: an actual interactive run (the Runtime
Verification prompt above), then screenshots, then deciding whether a
`v0.1.0` tag makes sense (it can reasonably describe "the iOS app works
standalone against a placeholder backend" without waiting on the Worker,
given that's now explicitly a separate effort).

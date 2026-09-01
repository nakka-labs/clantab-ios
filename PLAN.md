# ClanTab (iOS) — Build Plan

An open-source, no-login expense splitter for small groups (trips, shared flats, recurring friend circles) on iOS. One link or 6-character code per group. No accounts, no payment processing, no ads.

---

## 0. Project Overview & iOS Architecture

Every member of a group (5–10 people) needs to see and edit a shared ledger. 

- **Pure Swift Engine (`ClanTabKit`)**: All domain models, balance derivation, split validation, and the greedy debt-simplification algorithm are encapsulated in a standalone Swift package.
- **Pure-core testability**: `ClanTabKit` has no Apple-framework dependencies, so its full test suite builds and runs in ~1s on any Swift platform — no Simulator, no Xcode. The Linux CI (`.github/workflows/test.yml`) runs it on every push. (Early development was on Windows for exactly this reason.)
- **Native SwiftUI Shell (`App/`)**: A fluid, modern iOS interface (iOS 17+) for managing groups, recording expenses, and viewing simplified settlements.
- **Sync Model**: Fetch-on-load / refetch-after-write via a lightweight async/await API client connecting to the Cloudflare Worker DO backend (or local offline store).
- **All Money as Integer Minor Units**: Stored and calculated as integers (cents/paise) to eliminate floating-point rounding errors.

---

## 1. Product Specification

### Core Models

```swift
struct Group: Identifiable, Codable, Sendable {
    let id: String           // 16-char unguessable capability string (nanoid)
    let joinCode: String     // 6-char human-typeable code (e.g. "K7M9P2")
    let name: String
    let currency: String     // e.g. "INR", "USD", "EUR" (one per group in v1)
    let createdAt: Date
    var members: [Member]
}

struct Member: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let displayName: String  // Chosen once, stored locally in UserDefaults per group
}

struct Expense: Identifiable, Codable, Sendable {
    let id: String
    let payerId: String
    let amountMinor: Int64   // e.g. 120000 for ₹1,200.00
    let description: String
    let date: Date
    let splitType: SplitType // .equal, .exact, or .percentage
    let splits: [ExpenseSplit]
    let category: String?      // free-form; nil = uncategorized
    let categoryIcon: String?  // SF Symbol name
}

struct ExpenseSplit: Codable, Sendable {
    let memberId: String
    let amountMinor: Int64
}

struct Settlement: Identifiable, Codable, Sendable {
    let id: String
    let fromId: String
    let toId: String
    let amountMinor: Int64
    let date: Date
}

struct Balance: Codable, Sendable {
    let memberId: String
    let netMinor: Int64      // positive = is owed money, negative = owes money
}

struct SimplifiedSettlement: Codable, Sendable, Equatable {
    let fromId: String
    let toId: String
    let amountMinor: Int64
}
```

### Screens

| Screen | Purpose |
|---|---|
| **Create Group** | Group name, currency picker, user display name → generates capability link + 6-char code |
| **Join Group** | Enter 6-char code or open link → pick display name (saved to local device storage) |
| **Group Home** | Balance hero card ("You are owed ₹1,200" / "You owe ₹350"), member net balances, activity feed, link to Spending Insights |
| **Spending Insights** | Total spend, spend over time (day/week/month), and breakdowns by category and by member — SwiftUI Charts over `ClanTabKit.Insights` |
| **Add Expense** | Amount keypad, payer selector, description, category picker (name + SF Symbol), equal / exact / percentage split allocation |
| **Settle Up** | Minimal simplified settle-up transaction cards, 1-tap "Mark as Paid" |
| **Export** | CSV / JSON export via iOS ShareSheet |

### Non-Goals
- No accounts, login systems, or passwords
- No payment processing — settling is a manual "I paid outside the app" click
- No multi-currency within a single group (v1)
- No recurring expenses
- No paid cloud AI / receipt OCR in core v1
- No push notification servers or email tracking

---

## 2. Debt Simplification Algorithm

Given net balances (sum of paid minus owed across all expenses and settlements), find the **minimum number of transactions** (at most $N-1$) that zeroes out everyone's balance.

### Greedy Approach
1. Compute net balance per member in integer minor units. Filter out members with balance $0$.
2. Repeatedly pair the member with the largest positive balance (creditor) with the member with the largest negative balance (debtor).
3. Settle the smaller of the two absolute amounts between them, adjust both balances, and repeat until all balances are zero.

### Essential Unit Tests
- Simple triangle ($A \to B \to C \to A$ with varied amounts) collapses to minimal transactions.
- Single payer paying for all group members simplifies to $N-1$ direct payments to the payer.
- Rounding/division remainders (e.g. ₹100 split 3 ways) never gain or lose a paisa across the ledger; the remainder is deterministically allocated.
- Already settled groups produce 0 transactions.
- Idempotency: running the algorithm twice on identical balances produces the identical output.
- Random fuzz testing: sum of payments equals sum of positive balances.

---

## 3. Phased Roadmap

### Phase 0 — Scaffolding & Setup (Current)
- [x] Create private GitHub repo `indra-nakka/clantab-ios`.
- [x] Root configuration: `.gitignore`, `LICENSE`, `Makefile`, `.github/workflows/test.yml`, `AGENTS.md`, `README.md`, `PLAN.md`, `HANDOFF.md`.
- [x] Scaffold `ClanTabKit` SwiftPM package with skeleton targets.
- [x] Verify `swift test` runs cleanly on Windows.

### Phase 1 — Pure Logic: Domain Models, Balances & Debt Simplification
- [x] Implement `Model/` (`Group`, `Member`, `Expense`, `Settlement`, `Balance`, `SimplifiedSettlement`).
- [x] Implement `Logic/Balances.swift` (pure balance derivation from expenses & settlements).
- [x] Implement `Logic/Simplify.swift` (greedy $N-1$ debt-simplification algorithm).
- [x] Implement `Logic/Validation.swift` (split summation & deterministic remainder allocation).
- [x] Full unit & fuzz test suite in `ClanTabKitTests/` (25 tests, incl. 400 seeded fuzz iterations).

### Phase 2 — Storage & Network API Client
- [x] Implement `Storage/IdentityStore.swift` (local persistence for `[groupId: memberId]`).
- [x] Implement `Network/ClanTabClient.swift` (async/await HTTP client interfacing with group endpoints).
- [x] Integration tests for API serialization/deserialization (12 tests, incl. error envelope, idempotency-id encoding, and full group-state decoding).

### Phase 3 — SwiftUI App Shell & Group Home
- [x] App entry point and navigation state (`ClanTabApp`, `AppRoute`, `RootView`).
- [x] `CreateGroupView`: name, currency, creator display name.
- [x] `JoinGroupView`: 6-character code resolver & deep link handling (`clantab://g/:groupId` dev scheme; Universal Links deferred to a later phase pending a production domain).
- [x] `GroupHomeView`: balance summary hero, member net list, activity feed — backed by `GroupViewModel` (fetch-on-load/refetch, no optimistic UI).
- [x] **Compiles**: verified via `.github/workflows/ios-build.yml` (macOS GitHub Actions runner, iOS Simulator destination, no signing needed). Three real build errors found and fixed in the process.
- [x] **Run & verified** (2026-08-28, first interactive run — see HANDOFF.md "App/ Runtime Verification — Done"): Start screen, Create form + validation, post-create confirmation, Group Home (balance hero, member balances, activity feed), resume-on-relaunch, and pull-to-refresh all exercised on an iOS 26.5 Simulator against a local mock API. No SwiftUI runtime warnings or crashes.

### Phase 4 — Add Expense Flow
- [x] `AddExpenseView`: amount entry, payer picker, description, equal vs. exact split UI with automatic remainder resolution (via `Validation.equalSplit`).
- [x] Wire to group client and refresh state (toolbar button on `GroupHomeView` → sheet → `addExpense` → `refetch()`, no optimistic UI).
- [x] **Compiles** (CI-verified) and **run & verified** 2026-08-28: amount parsing, payer picker, equal split, submit → refetch → activity feed updates. See HANDOFF.md.

### Phase 5 — Settle Up Flow
- [x] `SettleUpView`: render simplified transaction cards from the server-computed `simplifiedSettlements` (never recomputed client-side).
- [x] 1-tap "Mark Paid" recording a settlement (`addSettlement` → `refetch()`, no optimistic UI).
- [x] **Compiles** (CI-verified) and **run & verified** 2026-08-28: server-computed plan rendered, "Mark as Paid" → `addSettlement` → list recomputes and the settled row drops out. See HANDOFF.md.

### Phase 6 — Polish & Export
- [x] CSV and JSON export via iOS ShareSheet (`ShareLink`). Serialization itself lives in `ClanTabKit.Export` (pure functions, fully tested on Windows — 9 tests); the App target only writes the result to a temp file for sharing.
- [x] System share sheet for group invite link & 6-character join code. The join code is only ever returned at creation time (`DESIGN.md` §2 doesn't return it from `GET /api/groups/:groupId`), so it's surfaced in a new post-creation confirmation step in `CreateGroupView` — see `App/README.md`'s "Known gaps" for the underlying API limitation.
- [x] Haptic feedback on expense-added and settlement-marked-paid (`.sensoryFeedback`, iOS 17+).
- [x] Dark mode: reviewed — already fine via system-adaptive colors, no changes needed.
- [x] Offline indicators / empty states: reviewed — existing loading spinner + inline error text considered adequate for v1; a dedicated offline banner deliberately deferred rather than over-built blind.
- [x] **Compiles** (CI-verified) and **run & verified** 2026-08-28: Share & Export menu (invite link, CSV, JSON via `ShareLink`), post-create join-code confirmation, and `.sensoryFeedback` haptics all exercised. See HANDOFF.md.

### Phase 7 — Ship & Documentation
- [x] Reviewed `AGENTS.md`/`DESIGN.md`/`README.md` for drift against what actually got built in Phases 1-6, and corrected what had drifted:
  `DESIGN.md` §5's sequence diagrams and §7 described a hypothetical web client (React `useGroup` hook, `identity.ts`/`localStorage`) that was never built — corrected to describe the actual iOS client (`GroupViewModel`, `UserDefaultsIdentityStore`). Also recorded the join-code API gap (found in Phase 6) in `DESIGN.md` §12 for whoever eventually builds the backend. `AGENTS.md` now notes `App/` needs macOS/Xcode.
- [x] **App/ Runtime Verification pass** (2026-08-28) — first interactive run of `App/`, on an iOS 26.5 Simulator (Xcode 26.6) driven end-to-end by an XCUITest against a local mock of the API. Every screen and flow from Phases 3-6 exercised and asserted; no SwiftUI runtime warnings or crashes. Details, screenshots location, and findings in HANDOFF.md's "App/ Runtime Verification — Done" section. Two findings: a `.gitignore` gap for the xcodegen-generated `App/ClanTab/Info.plist`, and a pre-existing UX dead end when resuming into a group that no longer exists server-side — both since handled (next item).
- [x] Screenshots + mermaid architecture diagram added to `README.md` (2026-08-28) — 5 screenshots from the runtime pass (`docs/screenshots/`) and a `flowchart` showing the ClanTabKit core / App shell / out-of-scope Worker split.
- [x] Acted on the runtime-pass findings (2026-08-28): the resume-into-deleted-group dead end is fixed — Group Home now detects the group's 404 (`GroupViewModel.groupUnavailable`) and `RootView` falls back to the Start screen. Added a first `ClanTabTests` unit-test target (17 tests) covering deep-link parsing (`RootView.extractGroupId` / `resolveDeepLink`) and group-not-found detection. _(At the time `ios-build.yml` ran this in CI; that macOS workflow was later retired — the iOS build + `ClanTabTests` now run in the local `pre-push` hook. See `HANDOFF.md`.)_
- [x] Tagged **`v0.1.0`** (2026-08-28) — the iOS-app-only milestone: ClanTabKit
  pure core (46 tests) + the SwiftUI app, compiled and run-verified end-to-end
  against a mock of the API, with README screenshots + architecture diagram.
  Explicitly **not** in scope for this tag: the Cloudflare Worker backend
  (separate effort — `AppConfig.apiBaseURL` is still a placeholder), a
  physical-device / TestFlight run, and an app icon.
- **Backend scope decision (superseded):** at the time, the Cloudflare Worker was
  treated as out of scope for this roadmap — Phases 1-7 were iOS-app-only, tested
  against a placeholder / local mock. **That decision was reversed afterwards:**
  the Worker was built in `worker/` and deployed (`BACKEND_PLAN.md` §1-§8), and
  `AppConfig.apiBaseURL` now points at it.

---

## Phase 7 complete (2026-08-28)

`PLAN.md`'s roadmap ends here. `v0.1.0` is tagged. The next tracks (status as of
2026-08-31 — see `HANDOFF.md` and `SHIP_PLAN.md` for detail):

- **The backend** — ✅ done. Cloudflare Worker + Durable Objects built in
  `worker/` (`BACKEND_PLAN.md` §1-§8), deployed at
  `https://clantab.nakka-labs.workers.dev`, `AppConfig.apiBaseURL` points at
  it, app re-verified end to end. Tagged `v0.2.0`.
- **Ship the app for real** — in progress (`SHIP_PLAN.md`). App icon
  (placeholder), App ID + App Store Connect record, signing, and the first
  TestFlight upload (`1.0 (1)`) are done. Next: on-device pass, then App Store
  submission (real icon + screenshots).
- **Universal Links** — not started. Associated Domains entitlement + hosted
  `apple-app-site-association`, once there's a production domain
  (`SHIP_PLAN.md` Track 1). Optional; invites work by 6-char code.

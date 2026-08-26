# Squarely (iOS) — Build Plan

An open-source, no-login expense splitter for small groups (trips, shared flats, recurring friend circles) on iOS. One link or 6-character code per group. No accounts, no payment processing, no ads.

---

## 0. Project Overview & iOS Architecture

Every member of a group (5–10 people) needs to see and edit a shared ledger. 

- **Pure Swift Engine (`SquareKit`)**: All domain models, balance derivation, split validation, and the greedy debt-simplification algorithm are encapsulated in a standalone Swift package.
- **Cross-Platform Testability**: `SquareKit` builds and executes tests in ~1s natively on Windows (Swift 6 toolchain) and macOS/Linux CI without requiring an iOS simulator or Xcode for pure logic.
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
    let splitType: SplitType // .equal or .exact
    let splits: [ExpenseSplit]
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
| **Group Home** | Balance hero card ("You are owed ₹1,200" / "You owe ₹350"), member net balances, activity feed |
| **Add Expense** | Amount keypad, payer selector, description, equal/exact split allocation |
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
- [x] Create private GitHub repo `indra-nakka/squarely-ios`.
- [x] Root configuration: `.gitignore`, `LICENSE`, `Makefile`, `.github/workflows/test.yml`, `AGENTS.md`, `README.md`, `PLAN.md`, `HANDOFF.md`.
- [x] Scaffold `SquareKit` SwiftPM package with skeleton targets.
- [x] Verify `swift test` runs cleanly on Windows.

### Phase 1 — Pure Logic: Domain Models, Balances & Debt Simplification
- [ ] Implement `Model/` (`Group`, `Member`, `Expense`, `Settlement`, `Balance`, `SimplifiedSettlement`).
- [ ] Implement `Logic/Balances.swift` (pure balance derivation from expenses & settlements).
- [ ] Implement `Logic/Simplify.swift` (greedy $N-1$ debt-simplification algorithm).
- [ ] Implement `Logic/Validation.swift` (split summation & deterministic remainder allocation).
- [ ] Full unit & fuzz test suite in `SquareKitTests/`.

### Phase 2 — Storage & Network API Client
- [ ] Implement `Storage/IdentityStore.swift` (local persistence for `[groupId: memberId]`).
- [ ] Implement `Network/SquarelyClient.swift` (async/await HTTP client interfacing with group endpoints).
- [ ] Integration tests for API serialization/deserialization.

### Phase 3 — SwiftUI App Shell & Group Home
- [ ] App entry point and navigation state.
- [ ] `CreateGroupView`: name, currency, creator display name.
- [ ] `JoinGroupView`: 6-character code resolver & deep link handling.
- [ ] `GroupHomeView`: balance summary hero, member net list, activity feed.

### Phase 4 — Add Expense Flow
- [ ] `AddExpenseView`: custom keypad / numeric input, payer picker, equal vs. exact split UI with automatic remainder resolution.
- [ ] Wire to group client and refresh state.

### Phase 5 — Settle Up Flow
- [ ] `SettleUpView`: render simplified transaction cards.
- [ ] 1-tap "Mark Paid" recording a settlement.

### Phase 6 — Polish & Export
- [ ] CSV and JSON export via iOS ShareSheet (`ShareLink`).
- [ ] System share sheet for group invite link & 6-character join code.
- [ ] Haptic feedback, dark mode, offline indicators, and empty states.

### Phase 7 — Ship & Documentation
- [ ] Polish README with architecture diagrams and screenshots.
- [ ] Tag release.

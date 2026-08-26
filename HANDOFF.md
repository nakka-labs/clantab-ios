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

---

## Phase 3 Prompt (Copy-Paste for Next Session)

```text
Read PLAN.md, DESIGN.md, and AGENTS.md.

We are starting Phase 3: SwiftUI App Shell & Group Home.

This is the first phase that touches the `App/` target (iOS 17+, SwiftUI) rather
than pure SquareKit logic - it can only be built and run from Xcode on macOS, not
verified on Windows. Keep all business logic in SquareKit; App/ should be thin.

Implement:
1. `App/` Xcode project (or Tuist/XcodeGen config, whichever keeps zero third-party
   dependencies per AGENTS.md) wired to depend on the local `SquareKit` package.
2. App entry point and root navigation state (create vs. join vs. active group).
3. `CreateGroupView`: name, currency picker, creator display name -> calls
   SquarelyClient.createGroup, persists identity via IdentityStore.
4. `JoinGroupView`: 6-character code entry (resolves via SquarelyClient.resolveJoinCode)
   and deep-link handling for the capability URL (/g/:groupId) -> joinGroup, persists
   identity.
5. `GroupHomeView`: balance hero card, per-member net list, activity feed - driven by
   a `GroupViewModel`/`useGroup`-equivalent that fetches on load and refetches after
   every mutation (DESIGN.md §7 sync model - no optimistic UI, no WebSocket in v1).

Since this can't be verified with `swift test` alone, describe what manual
verification in Xcode/Simulator would look like, and keep SquareKit's test suite
green throughout (`swift test --package-path SquareKit`).
```

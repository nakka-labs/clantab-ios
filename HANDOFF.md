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

---

## Phase 2 Prompt (Copy-Paste for Next Session)

```text
Read PLAN.md, DESIGN.md, and AGENTS.md.

We are starting Phase 2: Storage & Network API Client.

Implement the following in `SquareKit`:
1. `SquareKit/Sources/SquareKit/Storage/IdentityStore.swift` - local persistence of
   { groupId: memberId, displayName } per DESIGN.md §7 (identity.ts equivalent).
   Protocol-based so it can be backed by UserDefaults in the app and an in-memory
   fake in tests - no direct UserDefaults dependency inside SquareKit's pure layer.
2. `SquareKit/Sources/SquareKit/Network/SquarelyClient.swift` - async/await HTTP
   client implementing the API contract in DESIGN.md §2 exactly:
   - POST /api/groups
   - GET  /api/groups/resolve/:joinCode
   - POST /api/groups/:groupId/members
   - GET  /api/groups/:groupId
   - POST /api/groups/:groupId/expenses (client-generated idempotency id)
   - POST /api/groups/:groupId/settlements (client-generated idempotency id)
   Model the error envelope ({ error: { code, message } }) as a typed Swift error.
3. `SquareKit/Tests/SquareKitTests/` - integration-style tests for request encoding,
   response decoding, and error envelope handling using URLProtocol stubbing (no
   real network calls, no third-party dependencies per AGENTS.md).

Verify all tests pass with `swift test --package-path SquareKit`.
```

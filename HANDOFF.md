# Squarely iOS — Handoff Guide

## Phase 0 Checklist — Completed
- [x] Private GitHub repository created (`indra-nakka/squarely-ios`)
- [x] Root configs in place (`.gitignore`, `LICENSE`, `Makefile`, `AGENTS.md`, `README.md`, `PLAN.md`, `HANDOFF.md`, `.github/workflows/test.yml`)
- [x] `SquareKit` SwiftPM package scaffolded with passing baseline tests on Windows
- [x] Initial commit pushed to `main`

---

## Phase 1 Prompt (Copy-Paste for Next Session)

```text
Read PLAN.md and AGENTS.md. 

We are starting Phase 1: Pure Logic (Domain Models, Balances & Debt Simplification).

Implement the following in `SquareKit`:
1. `SquareKit/Sources/SquareKit/Model/` - Group, Member, Expense, ExpenseSplit, Settlement, Balance, SimplifiedSettlement.
2. `SquareKit/Sources/SquareKit/Logic/Balances.swift` - Pure function deriving net balances from expenses & settlements in integer minor units.
3. `SquareKit/Sources/SquareKit/Logic/Simplify.swift` - Greedy debt-simplification algorithm collapsing debts to at most N-1 transactions.
4. `SquareKit/Sources/SquareKit/Logic/Validation.swift` - Split sum validation and deterministic remainder distribution.
5. `SquareKit/Tests/SquareKitTests/` - Exhaustive test suite covering:
   - Triangle settlement collapse
   - Single-payer scenarios
   - Rounding remainder allocation (e.g. 100 split 3 ways)
   - Zero-balance / already-settled state
   - Idempotency
   - Random balance fuzz testing

Verify all tests pass with `swift test --package-path SquareKit`.
```

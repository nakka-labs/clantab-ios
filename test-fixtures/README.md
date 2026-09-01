# Shared golden test fixtures

Language-neutral test vectors for the pure balance / debt-simplification logic,
consumed by **both** implementations so they can't drift:

- `ClanTabKit` — `ClanTabKitTests/GoldenParityTests.swift`
- `worker/` — `worker/test/logic.test.ts`

If you change `Balances`/`Simplify` in one language, the other's CI fails until
it matches (or until the fixture is deliberately updated).

## `balances/*.json`

```jsonc
{
  "name": "human-readable case name",
  "members":     [{ "id", "displayName" }],
  "expenses":    [{ "id", "payerId", "amountMinor", "description", "date",
                    "splitType": "equal" | "exact" | "percentage",
                    "splits": [{ "memberId", "amountMinor" }],
                    "category"?, "categoryIcon"?     // optional; ignored by the math
                  }],
  "settlements": [{ "id", "fromId", "toId", "amountMinor", "date" }],

  "expectedBalances":   [{ "memberId", "netMinor" }],   // in `members` order
  "expectedSimplified": [{ "fromId", "toId", "amountMinor" }]
}
```

All amounts are integer minor units. `date` is ISO 8601 and does not affect the
math. `expectedBalances` always sums to zero. `splitType` is only a label —
`percentage` splits reach the ledger already resolved to exact minor-unit shares
(the client does the division, like `equal`'s remainder), so the balance math is
identical for all three types.

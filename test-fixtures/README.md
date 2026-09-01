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
  "expenses":    [{ "id", "payerId", "amountMinor", "currency", "description", "date",
                    "splitType": "equal" | "exact" | "percentage",
                    "splits": [{ "memberId", "amountMinor" }],
                    "category"?, "categoryIcon"?     // optional; ignored by the math
                  }],
  "settlements": [{ "id", "fromId", "toId", "amountMinor", "currency", "date" }],

  "expectedBalances":   [{ "memberId", "currency", "netMinor" }],
  "expectedSimplified": [{ "fromId", "toId", "amountMinor", "currency" }]
}
```

All amounts are integer minor units. `date` is ISO 8601 and does not affect the
math.

Balances and the settle-up plan are **partitioned by currency** — never blended
(no FX). `expectedBalances` lists only the (member, currency) pairs that net to
nonzero, ordered by currency in first-appearance order (across the combined
expenses-then-settlements stream) then `members` order; each currency bucket
sums to zero. `expectedSimplified` runs the greedy match once per currency and
concatenates in the same currency order.

`splitType` is only a label — `percentage` splits reach the ledger already
resolved to exact minor-unit shares (the client does the division, like
`equal`'s remainder), so the balance math is identical for all three types.

# App Store screenshots

Ready to upload to App Store Connect (the iPhone screenshot slot).

- **Size:** 1320 × 2868 (iPhone 6.9" display — captured on an iPhone 17 Pro Max
  simulator). This is the one required iPhone size; App Store Connect scales it
  for every other iPhone.
- **Format:** PNG, no alpha channel (App Store Connect rejects alpha).
- Status bar overridden to 9:41 / full signal / full battery; light appearance.
- Captured 2026-09-02 on the shipped build (multi-currency + all features), with
  a "Lisbon Trip" demo group (4 members, EUR + USD, categorised expenses across
  three months).

Order (hero first — `01` is what shows in search results):

| # | Screen | Shows |
|---|---|---|
| 01 | Group Home | per-currency balance hero + member balances |
| 02 | Insights | spend-over-time chart + category breakdown |
| 03 | Add Expense | amount/currency, payer, category, split types |
| 04 | Settle Up | the minimal per-currency settle-up plan |

Re-capture with `docs/appstore/` in mind whenever the UI changes materially.
The smaller versions in `docs/screenshots/` (used in the top-level `README.md`)
are the same captures.

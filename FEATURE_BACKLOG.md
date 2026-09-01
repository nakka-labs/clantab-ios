# ClanTab — Post-v1 Feature Backlog

> Status: **discussed, not designed.** Pickup point for the next round of
> feature work, separate from `LOGIN_ACCOUNTS_BRIEF.md`.
>
> **Sequencing decided:** ship the items below *before* the accounts work
> in `LOGIN_ACCOUNTS_BRIEF.md`. They're technically independent of
> identity, they're cheaper, and they buy more real usage before
> committing to an identity model that'll need long-term support.

## In scope, next up — genuinely low cost

- **Custom/percentage splits.** Agreed. Add a split-type field to the
  expense model (equal / percentage / exact-amount) — same integer-money
  math already in use, validated in `GroupDO`, no new endpoint, just a
  bigger request payload. Probably the single most-requested feature in
  any splitter app's reviews.
- **Custom categories + icons.** A category string + icon field on the
  expense model, no backend change beyond storing it. Needs an icon
  picker in the UI and a migration story for existing expenses with no
  category (default to "Uncategorized", don't force a backfill).
- **Graphs.** Spending visualizations from data already in the ledger —
  e.g. spend-over-time, per-member share of group spend, category
  breakdown if/when categories exist. Pure `ClanTabKit` computation (like
  `Balances`/debt-simplification today) feeding native SwiftUI Charts —
  no backend change needed, the Worker already returns full expense
  history.
- **Search / filter.** Filter the expense list — by member, date range,
  amount — client-side over data already fetched. No new endpoint;
  `GroupDO`'s `getState` already returns the full expense list per
  `DESIGN.md` §2.
- **CSV import (from other apps).** Let a user bring in history from
  Splitwise/other splitters via CSV, mapped into ClanTab's expense model.
  Needs: a format-detection or column-mapping step (Splitwise's export
  schema differs from ClanTab's own `Export.csv` format from
  `HANDOFF.md`), then batch-`addExpense` against the existing endpoint.
  Reuses the export code's pure-function pattern in reverse.

## In scope, next up — real cost, don't lump in as "cheap"

- **Multi-currency (no auto-conversion) — decided.** A group is NOT
  restricted to one currency; expenses can be in any currency. Ledgers
  are kept separate per currency, not blended — i.e. debt-simplification
  (`PLAN.md` §2) runs once per currency bucket within a group, so a
  member's balance can be "owes ₹500 AND owes $45," never a converted
  single number. This is the correct complement to killing FX-conversion:
  a blended number would just be a fiction once rates move. Cost:
  partitioning the existing greedy algorithm by currency is cheap; the
  real cost is UI — a balance row can carry N currency amounts, and
  settle-up has to work per-currency (can't net ₹500 owed against $45
  owed). **Decided:** a group remembers its last-used currency as the
  default for new expenses; the user can override per expense — avoids
  a currency picker on every single add for groups that are 95% one
  currency.
  **Do not build FX conversion** — ongoing rate-API dependency plus an
  unavoidable correctness call (rate at expense time or settle time?)
  that will visibly drift from what someone actually paid. Explicit
  non-goal in `DESIGN.md` for this reason.

## Some ideas worth implementing at a later point

- **Plain photo attachment on an expense (no OCR).** Dropped for now, not
  killed — genuinely useful, just has a real cost/setup question attached.
  Different from the receipt-OCR non-goal: no AI/parsing, just attaching a
  reference photo. Two implementation paths when this comes back up:
  Cloudflare R2 (10GB/1M-writes/10M-reads free/month, zero egress, but
  requires a payment method on file to activate even within the free tier
  — the first place this project would need a card, breaking the
  zero-card invariant kept everywhere else) vs. local-only/on-device (zero
  setup, zero card, but not visible to other group members — don't use DO
  storage for this either way, it's for rows not blobs). Revisit once
  there's an actual reason to prioritize it.

## Dropped

- **Recurring/scheduled expenses.** Dropped, not building — both the reminder-only and auto-post versions. Stays a non-goal per `DESIGN.md`.

## Confirmed — downstream of accounts, not standalone

- **Settle across all groups with a person — confirmed.** "Simplify
  dues/settling" meant cross-group netting: e.g. see and settle one
  combined view of everything owed between you and Bob across every
  group you share, not just per-group (per-group minimal-transaction
  settling already exists — the greedy debt-simplification algorithm,
  `PLAN.md` §2). Full spec lives in `LOGIN_ACCOUNTS_BRIEF.md` (it depends
  on the accounts identity index — name matching can't safely tell two
  different groups' "Bob" apart, only a real linked identity can).
  Mechanically: a read-side aggregation over groups sharing both
  identities, reported per-currency per the multi-currency decision
  above (never blended); the actual "settle" action still fires one
  `addSettlement` per underlying group through the existing write path —
  no new cross-group ledger, each group's data stays authoritative.

## Explicitly held off (not now, not decided against)

- **Receipt / bill reading (OCR).** Already a stated non-goal for v1 in
  `PLAN.md` §"Non-Goals", `AGENTS.md`, and `DESIGN.md` §12 ("no paid cloud
  AI / receipt OCR in core v1"). Confirmed again here: stays out of scope
  for this round too. Revisit later — it's the one item on this list that
  isn't "cheap" (needs either on-device Vision framework work or a paid
  cloud OCR API, plus a review/correction UI).

## Not yet decided

- Sequencing relative to `LOGIN_ACCOUNTS_BRIEF.md` — whether these ship
  before, after, or interleaved with the accounts work. Both are
  independent of each other technically (none of graphs/search/CSV-import
  touch identity), so this is purely a prioritization call, not a
  dependency.

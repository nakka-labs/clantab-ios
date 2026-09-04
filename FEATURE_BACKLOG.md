# ClanTab — Post-v1 Feature Backlog

> Status: **discussed, not designed.** Pickup point for the next round of
> feature work, separate from `LOGIN_ACCOUNTS_BRIEF.md`.
>
> **Sequencing decided:** ship the items below *before* the accounts work
> in `LOGIN_ACCOUNTS_BRIEF.md`. They're technically independent of
> identity, they're cheaper, and they buy more real usage before
> committing to an identity model that'll need long-term support.

## In scope, next up — genuinely low cost

- ~~**Custom/percentage splits.**~~ **Shipped 2026-09-01.** `SplitType` gained
  `.percentage`; the client resolves entered percentages to exact minor-unit
  shares (`ClanTabKit.Validation.percentageSplit`, same deterministic-remainder
  pattern as `equalSplit`) before dispatch, so the wire contract and balance
  math were unchanged. Server change was minimal: widen the `splitType` union +
  the `split_type` CHECK, plus a `GroupDO` schema-v2 migration (SQLite can't
  alter a CHECK in place). Exact-amount ("custom") splits already existed as
  `.exact`. `AddExpenseView` gained a third segment with per-member `%` fields.
  See `DESIGN.md` §2/§6/§10.
- ~~**Custom categories + icons.**~~ **Shipped 2026-09-01.** `Expense` gained
  nullable `category` + `categoryIcon` (an SF Symbol name, stored per expense so
  no shared name→icon table is needed). `ExpenseCategory` in `ClanTabKit` carries
  the curated default set + icon grid; `CategoryPickerView` does one-tap defaults
  or a custom name + icon. Schema v3 is a plain `ADD COLUMN` (no rebuild); missing
  category renders as "Uncategorized", no backfill. Activity rows show the icon;
  CSV export gained a Category column. See `DESIGN.md` §2/§3/§10.
- ~~**Graphs.**~~ **Shipped 2026-09-01.** `ClanTabKit.Insights` (pure, like
  `Balances`) computes total spend, spend-over-time (day/week/month, empty
  buckets filled), spend by category, and each member's share. `InsightsView`
  feeds spend-over-time into SwiftUI Charts and renders the category/member
  breakdowns as labelled proportional bars; reached from a "Spending Insights"
  row on Group Home. No backend or wire change — settlements are excluded (they
  move money, they aren't spend).
- ~~**Search / filter.**~~ **Shipped 2026-09-01.** `ClanTabKit.ActivityFiltering`
  (pure) filters the activity feed by free-text (description + involved member
  names, case/diacritic-insensitive), by member (payer / split / settlement
  party), and by category (`.any` / `.uncategorized` / `.named`). `GroupHomeView`
  wires it to a `.searchable` field + a toolbar filter menu; only the feed is
  filtered, balances stay group-wide. Date-range / amount-range filtering was
  left out of this pass — add later if asked.
- ~~**CSV import (from other apps).**~~ **Shipped 2026-09-02.** Pure
  `ClanTabKit.CSVImport` auto-detects two formats — ClanTab's own `Export.csv`
  (lossless round-trip) and Splitwise's per-person export (each row
  reconstructed as a single-payer expense; genuine multi-payer rows Splitwise
  can't export losslessly are skipped with a warning). Includes an RFC 4180
  tokenizer and integer-math decimal parsing. `ImportCSVView` picks the file,
  matches the names in it to members (or creates them via the join endpoint),
  then posts each row with a client-generated id (partial import is retry-safe).
  No backend or schema change.

## Shipped

- ~~**Edit / delete an expense or settlement; rename a group / member; remove a
  member; leave a group.**~~ **Shipped 2026-09-04.** Not in the original
  backlog — plain functional gaps. `PUT`+`DELETE` on `.../expenses/:id` and
  `.../settlements/:id` (full replacement, preserves feed order; idempotent
  delete); `PATCH /api/groups/:id` (name / default currency); `PATCH`+`DELETE`
  on `.../members/:id` (rename; remove only when unused → else `MEMBER_IN_USE`).
  All `DESIGN.md` §2, same `groupId`-possession trust model. iOS:
  swipe-to-delete + tap-to-edit on the feed; a Group Settings screen for the
  rest; "Leave This Group" + a start-screen context-menu remove, both
  device-local.
- ~~**Multi-currency (no auto-conversion).**~~ **Shipped 2026-09-01.** `currency`
  on expenses + settlements (schema v4, `ADD COLUMN` + backfill from the group
  currency); `Balance` and `SimplifiedSettlement` gained `currency`.
  `Balances.compute` / `Simplify.simplify` (and the worker ports) now partition
  by currency — nonzero balances per (member, currency), the greedy plan run
  once per currency bucket, never blended. Golden fixtures rewritten +
  `multi-currency.json` added. App: currency picker on Add Expense defaulting to
  the group's last-used currency (`GroupViewModel.lastUsedCurrency`), per-currency
  lines in the balance hero / member rows / settle-up sections, a currency
  segment on the Insights screen, a Currency column in the CSV export.
  **FX conversion was NOT built and stays a hard non-goal** (`DESIGN.md` §12).

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

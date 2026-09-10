# CSV import: format compatibility matrix

`ImportCSVView` → `CSVImport.parse(_:)` (`ClanTabKit/Sources/ClanTabKit/Import/CSVImport.swift`).
Pure, format-auto-detected from the header row. This doc is the source of
truth for what's supported, what was fixed, and what's still a gap — update
it whenever `CSVImport` changes.

## Supported

| App | Detection | Fidelity | Notes |
|---|---|---|---|
| **ClanTab** (`Export.csv`) | exact header match | lossless round-trip | Own format. `Splits` field is `Name:amount; Name:amount`. |
| **Splitwise** | header has `cost`+`currency`+`date`+`description` | lossy by construction | Splitwise only exports each person's *signed net* (paid − owed) per row, not the actual splits. We reconstruct a single-payer expense (payer = largest net) and back-solve everyone else's share. A genuine multi-payer expense (two people net-positive on the same row) **cannot** be reconstructed and is skipped with a warning — that's a limit of Splitwise's export, not ours. |
| **Settle Up** | header has `who paid`+`for whom`+`split amounts` | lossless | Fixed 2026-09-08 (see below). `For whom` / `Split amounts` are parallel `;`-separated lists — no reconstruction needed. `Type` is `expense` or `transfer` (settlement); a transfer's payer ("Who paid") sent the amount to the one person in "For whom". |

## Fixed 2026-09-08 (Settle Up import was totally broken)

Reported via a real export (`Future.csv`, a Settle Up trip). Two independent bugs,
both silent — the import screen just said "Couldn't read that file":

1. **Wrong assumption: file is UTF-8.** `ImportCSVView` read the picked file
   with `String(contentsOf:encoding:.utf8)`. Settle Up's iOS/macOS CSV export is
   **UTF-16LE with a BOM** (`FF FE...`) — decoding that as UTF-8 throws
   immediately, before `CSVImport.parse` ever runs. Same failure mode hits
   *any* UTF-16 CSV — Numbers' "CSV" save and Excel's "Unicode Text" export
   do this too. Fixed with `CSVImport.decode(_ data: Data) -> String?`: sniffs
   the BOM (UTF-8/UTF-16LE/UTF-16BE) and falls back through UTF-8 → UTF-16LE →
   Latin-1 when there's no BOM at all, so a file just opens instead of
   silently failing. `ImportCSVView` now reads bytes (`Data(contentsOf:)`) and
   calls this instead of the old `String(contentsOf:encoding:)`.
2. **No Settle Up parser existed.** Only ClanTab's own format and Splitwise were
   recognized; a correctly-decoded Settle Up file still hit `unrecognizedFormat`.
   Added `parseSettleUp` (see table above).
3. **Rounding remainder, found against the real file, not a hypothetical.**
   When Settle Up splits a cost evenly, it rounds *each* share to 2dp
   independently rather than assigning the leftover minor unit anywhere —
   `₹6628 ÷ 3 → 2209.33 × 3 = 6627.99`, one paisa short of the row's `Amount`.
   ~6% of rows in the real sample file had this (always ±1, occasionally ±2,
   never more). A strict sum-must-match-exactly check would have silently
   *dropped* those rows. Fixed: when the split sum is within
   `max(1, splitCount)` minor units of the total, the remainder is nudged onto
   the payer's own share — the same deterministic-remainder rule ClanTab
   itself uses for equal/percentage splits (`AGENTS.md`). A genuinely wrong
   split (off by more than that) still gets skipped with a warning, not
   silently "corrected."

Verified: `swift test --package-path ClanTabKit --filter CSVImport` (19 cases,
including a UTF-16LE-with-BOM round-trip and the remainder-nudge) and
`make check` (full ClanTabKit + worker + iOS build) both pass, and the real
reported file parses to **31 expenses + 4 settlements, 0 warnings** — the 2
rows that were a rounding paisa short are nudged onto the payer, not dropped.
(The parser change was first written in a sandbox with no Swift toolchain and
cross-checked against a Python re-implementation of the logic; a later pass
compiled and ran it unchanged — no behaviour changes were needed.)

## Known gaps — not fixed, flagged instead of silently guessed at

- **No de-duplication on import, for *any* format.** Every imported row gets
  a fresh client-generated id (`UUID()`), by design, so a partially-failed
  import is safe to retry. But that also means importing the **same file
  twice** — or the same trip exported from two apps by two different group
  members — posts every expense and settlement again, with no detection.
  For a money app this is the sharper edge of "imports need to work
  flawlessly": a successful *second* import is a correctness bug even though
  nothing errors. Real dedup — comparing candidate rows against the group's
  existing ledger by date+amount+payer+description, and deciding what "same
  expense" means when descriptions/rounding differ slightly across apps — is
  a real feature, not a one-line fix, and still its own open CHECKLIST item.
  **Interim (2026-09-09):** `ImportCSVView`'s review screen now shows an amber
  caution above the Import button ("ClanTab won't skip expenses it already
  has. If this file was imported before — or another member imported the same
  trip — every row is added again."), so a re-import isn't silent even though
  it isn't blocked.
- **Splitwise / Settle Up amounts assume `.` as the decimal separator.**
  `parseAmount` strips `,` unconditionally, treating it only as a thousands
  separator (`"1,234.00"` → 123400). An export from a EU-locale device using
  comma-decimal would misparse: `"12,50"` (twelve-fifty, i.e. 1250 minor
  units) currently parses as `1250` *major* units — `125000` minor, a 100x
  error — because the `,` is stripped and the result read as a whole number.
  Nothing in the current codebase
  exercises this path — the real Settle Up file we have is period-decimal — so
  this is not "fixed," it's flagged. A safe fix needs a way to *know* the
  locale convention (e.g. detect a delimiter-shift to `;` the way Excel does
  for comma-decimal locales) rather than guessing from the amount string
  alone, which is genuinely ambiguous (`"1,234"` is 1234 in the US
  convention and 1.234 in the EU one). Don't build this without a real
  sample export from an EU-locale export to test against.
- **Settle Up's `Timezone` column is ignored.** It's blank on every row we've
  seen in practice; `parseDate` treats the naive `yyyy-MM-dd HH:mm:ss`
  timestamp as UTC. If Settle Up does populate it for some export paths, dates
  could be off by the local UTC offset. Low-impact (a date-only display bug,
  not a money bug) but undocumented until now.
- **Settle Up's emoji-prefixed categories are kept as-is** (`"🍲 Food"`), not
  mapped onto ClanTab's plain-text category set. This is a deliberate
  choice, not a bug: categories are free text in this app
  (`ExpenseCategory`), so the emoji just becomes part of the category name
  rather than breaking anything. Cosmetic only.

## Not supported — researched 2026-09-08, re-investigated 2026-09-10, no fix (see `CHECKLIST.md`)

Splitwise, Settle Up, Tricount, and Splid are the four apps this repo's own
competitive scan treats as prominent; usage drops off sharply past them, so
this pass didn't chase anything further down the list. Splitwise and Settle Up
are covered above. For the other two, here's what's actually true right
now, sourced — not guessed:

### Tricount — no self-serve file export; the realistic path is the share link (re-investigated 2026-09-10)
**Native export is gone.** Tricount's FAQ confirms "Export tricount in CSV
and PDF" was removed as a deprecated Premium feature; the only way to get a
file now is to email `support@bunq.com` and they send you CSV or ODF
([help.tricount.com/articles/tricount-faqs](https://help.tricount.com/articles/tricount-faqs),
checked 2026-09-10). Nobody has posted the current support-issued CSV, so its
column schema is still unseen — and since it's not self-serve, a file
importer built for it only helps the rare person who already emailed support,
not anyone switching in from Tricount going forward.

**But Tricount has a first-class public share link.** Every tricount can
generate a link (`tricount.com/...`) that renders every expense, reimbursement
and balance in a browser — no app, no sign-up. Tricount promotes this
("share a link with others… they can view or add expenses in a browser").
The link's backend returns structured JSON, and several third-party tools
already consume it —
[marcomc/tricount-exporter](https://github.com/marcomc/tricount-exporter)
("fetches transactions from a shared Tricount using its public key"),
[tricount-exporter.pages.dev](https://tricount-exporter.pages.dev/),
[tricountextractor.com](https://tricountextractor.com/) — paste a share
link/ID, get the whole ledger, export CSV/JSON. The model is rich: payer(s),
per-member share + allocation type, base + original currency + exchange rate,
category, timestamp.

That endpoint is **undocumented and carries no ToS blessing for programmatic
use** — but the underlying capability (public read access to a tricount via a
deliberately-generated link) is an intentional Tricount feature, which puts
it a notch below Splid's reverse-engineered *sync* protocol on the risk
scale, and a notch above a sanctioned API.

**The `Date,Title,Paid by <name>…,Paid for <name>…,Currency,Category` CSV**
that Sesterce's import docs and the exporter tools normalize to is *not*
Tricount's own format either — it's a convention those third-party tools
invented. Supporting it would mean "we import the output of
tricount-exporter," which needs the user to run that tool first and is an odd
thing to advertise.

**If a Tricount importer is ever prioritized**, the one clean path is a
**share-link import** (worker route: share link/ID → fetch the public
tricount JSON → transform to drafts), not a file parser. Real work against an
undocumented endpoint (~40–60k: fetch + JSON mapping + tests), and Tricount
supports genuine multi-payer expenses that our single-payer `DraftExpense`
can't represent losslessly — same limitation `parseSplitwise` documents, so
those rows would be skipped with a warning. No demand signal today; same call
as Splid — leave it unbuilt.

### Splid — there is no CSV export (investigated 2026-09-10)
Earlier notes here assumed "Splid's iOS/macOS app does have a CSV export…
it shares the same `Who paid`/`For whom`/`Split amounts` header shape." That
assumption came from `Future.csv` being taken for a Splid export before the
person who made it confirmed it was **Settle Up**. On a proper look it does
not hold up:

- **Splid exports PDF or Excel, never CSV.** Its own App Store listing:
  "Download summaries as PDF or Excel\* files" / "\*Excel export available via
  in-app purchase" (Splid Plus, ~$3.99). PDF is free; the spreadsheet is a
  paid in-app purchase. No CSV path exists at any tier, on any platform
  ([apps.apple.com/app/id991473495](https://apps.apple.com/us/app/splid-split-group-bills/id991473495),
  checked 2026-09-10).
- **The `.xlsx` layout is undocumented and behind that paywall.** Nobody has
  posted one; no third-party tool parses one; getting a sample means someone
  buying Splid Plus and exporting a throwaway group. And `.xlsx` is a
  zip-of-XML — `CSVImport.decode` can't touch it (it'd Latin-1-garble the zip
  bytes and fall through to `unrecognizedFormat`). A real Splid importer via
  this route needs an XLSX reader in the kit (unzip + `sharedStrings.xml` +
  sheet XML — there's no lightweight pure-Swift one in the project today),
  *then* a parser built against the unknown sheet layout.
- **There is a reverse-engineered JSON API.** `splid-js`
  ([github.com/LinusBolls/splid-js](https://github.com/LinusBolls/splid-js),
  active Sept 2026) wraps Splid's sync backend: invite-code group access, full
  model (payers, "profiteers" with share weights, amount + currency +
  exchange rate, ISO date, custom category, separate payment/transfer
  objects). Explicitly "not officially associated with Splid," no documented
  ToS. This is the same shape as the Tricount unofficial scraper, and the
  same rule applies: **don't build against a reverse-engineered backend** —
  it can break without notice and the legal footing is unclear.

**Conclusion:** the backlog item as written ("check `parseSettleUp` against a
real Splid CSV") is not actionable — there is no such file. If Splid import is
ever genuinely demanded, it's a from-scratch effort down one of two roads
(a paid-export XLSX reader + parser, or an invite-code → API import), each
much larger than the "~15k, parser may already handle it" the item assumed,
and each gated on inputs we don't have. Not worth starting without a real
demand signal — same call as Tricount.

### Splitwise sign convention — re-checked, confirmed correct, not a bug
While researching the above, a secondary source (a competing app's
migration blog, summarized via an AI-fetched page) claimed Splitwise's
per-person columns use `positive = you owe` — the opposite of what's
shipped here. That would mean the already-shipped Splitwise importer has
every payer/debtor inverted, so it got checked against a primary source
before anything was touched: a real user-posted example row in
[spliit-app/spliit#22](https://github.com/spliit-app/spliit/issues/22)
confirms `positive = paid − owed` (net creditor) — matching
`parseSplitwise` and its tests exactly. No bug, no change made. Kept here
as a reminder that one plausible-sounding secondary source isn't enough to
act on for a money-sign question, even when it's specifically about
*correcting* something.

Neither Tricount nor Splid has a self-serve CSV to build a parser against —
and for both, the only real import path (a share-link / invite-code fetch
against an undocumented backend) is a from-scratch effort much larger than a
CSV parser, gated on demand we don't have. See `CHECKLIST.md`'s Feature
backlog for the prioritization call.

## Fixtures

`test-fixtures/csv-import/settleup-sample.csv` — a small synthetic Settle Up-shaped
file (UTF-16LE, BOM, multi-way splits, a settlement row, an emoji category) for
manual import testing in the Simulator. Real friend names from the reported
bug were **not** committed here (public repo) — this is a fabricated
equivalent, structurally identical to what broke the real import.

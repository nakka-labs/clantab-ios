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
| **Splid** | header has `who paid`+`for whom`+`split amounts` | lossless | Fixed 2026-09-08 (see below). `For whom` / `Split amounts` are parallel `;`-separated lists — no reconstruction needed. `Type` is `expense` or `transfer` (settlement); a transfer's payer ("Who paid") sent the amount to the one person in "For whom". |

## Fixed 2026-09-08 (Splid import was totally broken)

Reported via a real export (`Future.csv`, a Splid trip). Two independent bugs,
both silent — the import screen just said "Couldn't read that file":

1. **Wrong assumption: file is UTF-8.** `ImportCSVView` read the picked file
   with `String(contentsOf:encoding:.utf8)`. Splid's iOS/macOS CSV export is
   **UTF-16LE with a BOM** (`FF FE...`) — decoding that as UTF-8 throws
   immediately, before `CSVImport.parse` ever runs. Same failure mode hits
   *any* UTF-16 CSV — Numbers' "CSV" save and Excel's "Unicode Text" export
   do this too. Fixed with `CSVImport.decode(_ data: Data) -> String?`: sniffs
   the BOM (UTF-8/UTF-16LE/UTF-16BE) and falls back through UTF-8 → UTF-16LE →
   Latin-1 when there's no BOM at all, so a file just opens instead of
   silently failing. `ImportCSVView` now reads bytes (`Data(contentsOf:)`) and
   calls this instead of the old `String(contentsOf:encoding:)`.
2. **No Splid parser existed.** Only ClanTab's own format and Splitwise were
   recognized; a correctly-decoded Splid file still hit `unrecognizedFormat`.
   Added `parseSplid` (see table above).
3. **Rounding remainder, found against the real file, not a hypothetical.**
   When Splid splits a cost evenly, it rounds *each* share to 2dp
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
  nothing errors. Not fixed here (real dedup needs comparing candidate rows
  against the group's existing ledger by date+amount+payer+description, and
  deciding what "same expense" means when descriptions/rounding differ
  slightly across apps — a real feature, not a one-line fix). Worth its own
  CHECKLIST item; at minimum, `ImportCSVView` should warn once before import
  ("Re-importing may create duplicates") rather than staying silent.
- **Splitwise / Splid amounts assume `.` as the decimal separator.**
  `parseAmount` strips `,` unconditionally, treating it only as a thousands
  separator (`"1,234.00"` → 123400). An export from a EU-locale device using
  comma-decimal would misparse: `"12,50"` (twelve-fifty, i.e. 1250 minor
  units) currently parses as `1250` *major* units — `125000` minor, a 100x
  error — because the `,` is stripped and the result read as a whole number.
  Nothing in the current codebase
  exercises this path — the real Splid file we have is period-decimal — so
  this is not "fixed," it's flagged. A safe fix needs a way to *know* the
  locale convention (e.g. detect a delimiter-shift to `;` the way Excel does
  for comma-decimal locales) rather than guessing from the amount string
  alone, which is genuinely ambiguous (`"1,234"` is 1234 in the US
  convention and 1.234 in the EU one). Don't build this without a real
  sample export from an EU-locale export to test against.
- **Splid's `Timezone` column is ignored.** It's blank on every row we've
  seen in practice; `parseDate` treats the naive `yyyy-MM-dd HH:mm:ss`
  timestamp as UTC. If Splid does populate it for some export paths, dates
  could be off by the local UTC offset. Low-impact (a date-only display bug,
  not a money bug) but undocumented until now.
- **Splid's emoji-prefixed categories are kept as-is** (`"🍲 Food"`), not
  mapped onto ClanTab's plain-text category set. This is a deliberate
  choice, not a bug: categories are free text in this app
  (`ExpenseCategory`), so the emoji just becomes part of the category name
  rather than breaking anything. Cosmetic only.

## Not supported — no verified sample to build against

**Tricount** and **Settle Up** are both named in `CHECKLIST.md`'s
competitive scan, but there's no confirmed real export sample for either in
this repo, and their public documentation doesn't spell out the exact CSV
schema. Guessing a parser for a money import without a real file to check it
against is how the Splid bug happened in the first place — don't repeat
that. If support is wanted: get a real exported CSV from each app first (a
throwaway trip with 2-3 rows is enough), add it as a redacted fixture the
same way `Future.csv` informed the Splid fix, then build the parser against
it.

## Fixtures

`test-fixtures/csv-import/splid-sample.csv` — a small synthetic Splid-shaped
file (UTF-16LE, BOM, multi-way splits, a settlement row, an emoji category) for
manual import testing in the Simulator. Real friend names from the reported
bug were **not** committed here (public repo) — this is a fabricated
equivalent, structurally identical to what broke the real import.

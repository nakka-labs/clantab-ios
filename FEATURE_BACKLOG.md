# ClanTab — Post-v1 Feature Backlog

> Status: **discussed, not designed** for anything below not yet shipped.
>
> **Sequencing (resolved 2026-09-05):** most of what's below has no
> dependency on `MANDATORY_LOGIN_PLAN.md` and ships in any order relative to
> it — see `NEXT_STEPS.md` Phase 5. The exception is push notifications,
> the widget, and Siri (all three moved into v1 scope 2026-09-05, below) —
> those sequence *after* `MANDATORY_LOGIN_PLAN.md` Part 2 (`UserDO`
> re-keying), since device-token-per-identity is cleaner built once against
> the final stable identity keys — see `NEXT_STEPS.md` Phase 6.

## In scope, next up — genuinely low cost

All unshipped items below are **[CLI]** — time/effort cost only, no ₹ cost, confirmed 2026-09-05. Nothing here needs owner action beyond reviewing the result.

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

- **Delete goes to trash, with attribution.** **Server side done 2026-09-05**
  (schema v6: `deleted_at` + `deleted_by`, nullable, plain `ADD COLUMN` on
  both `expenses` and `settlements` — no rebuild); worker tests 154 → 163,
  `wrangler deploy --dry-run` validates, not yet deployed. `DELETE` now
  soft-deletes (splits are left alone so a restored expense comes back
  exactly); `getState`/balances/`removeMember`'s in-use check all exclude
  trashed rows; new `GET .../trash` (lists both, newest-deleted first) and
  `POST .../expenses|settlements/:id/restore`. `deletedBy` is an optional
  `?deletedBy=<memberId>` query param on the delete call — client-supplied,
  trusted at face value like every other id in this trust model, not
  cryptographically verified. **Scoped down from the original ask:**
  `created_by`/`edited_by` deliberately not built in this pass — the
  headline "anyone with the link can delete anything" gap is `deleted_by`;
  the other two are a separable follow-up, not bundled in just because the
  schema was open. **iOS side done 2026-09-05** too: swipe-to-delete now
  shows a bottom "Deleted '<description>' [Undo]" banner for ~5s
  (`GroupHomeView`), and a "Recently Deleted" entry in Group Options opens a
  full listing (reusing `ActivityRow`/`ActivityItem`, extended with a
  `deletedAt` accessor) with a per-row Restore button, no expiry. Both call
  the same `restoreExpense`/`restoreSettlement` client methods. ClanTabKit
  117 → 120 tests, App 63 (unchanged — view-layer only, no new
  pure-function surface). No purge job needed for v1 — SQLite storage is
  cheap enough (`production_priority` project memory's cost model) to just
  keep trash forever until there's a reason not to. Not yet deployed
  (server side).
- **Duplicate an expense.** **Done 2026-09-05.** A "Duplicate" swipe action
  on an expense row (`GroupHomeView`, alongside Edit/Delete) opens
  `AddExpenseView` pre-filled with the same payer/split/category — amount
  blank, date today. Reuses the existing `editing:` prefill pattern (a new
  `duplicating:` param); `editing` itself stays `nil` for a duplicate, which
  is what already makes `save()` POST a fresh expense with a new id instead
  of PUTing over the original — no separate branch needed. No backend or
  wire change; App build + test green (63/63, unchanged — view-layer only).
  Solves the recurring-cost itch (rent, groceries) for the common case
  without the correctness problems of auto-posting — see the
  recurring-reminders item below for why full auto-post stays off the table.
- **Recurring reminders (not auto-post).** **Done 2026-09-05**, scoped down
  in two ways agreed with the owner before building:
  - **Equal split only, recomputed fresh each time**, not a stored custom
    split — `RecurringTemplate` (ClanTabKit) holds amount/currency/payer/
    description/category/cadence; whoever's *currently* a member gets an
    equal share when a reminder becomes a real expense. Sidesteps the
    stale-member problem for splits entirely, not just for the payer (which
    *is* stored, and *is* validated — `RecurringTemplateValidation`; a row
    for an ex-member shows "needs updating" in the reminders list and its
    payer field re-defaults on open).
  - **Tapping the notification just opens the app** (default OS behavior) —
    it doesn't deep-link straight to the specific group/reminder. The
    reminder already delivers its value (a nudge to come log something); a
    few extra taps once inside the app (open the group → Group Options →
    Recurring Reminders → tap the reminder) is minor friction, not a
    correctness issue, and skipping the deep-link plumbing kept this a
    same-day build instead of a multi-day one.

  `UNUserNotificationCenter` only — zero backend change, zero server push
  infra, matching the original ask. A "Recurring Reminders" entry in Group
  Options lists templates (add/delete), each opening `AddExpenseView`
  pre-filled (`recurringTemplate:`, alongside the existing `editing:`/
  `duplicating:` prefill sources) — the user still confirms/adjusts and
  taps Add, same as Duplicate. **Auto-post stays off the table**, same
  reasoning as before: a shared, no-hidden-owner ledger where expenses
  appear with nobody having actively added them is the exact trust problem
  trash/attribution exists to fix.

  **Verification:** `RecurringTemplateValidation`/`RecurringSchedule` (pure,
  no `UNUserNotificationCenter` dependency) and the local store are unit
  tested (ClanTabKit 120 → 127); App build + test green (63, unchanged —
  view-layer only). **Not independently verified**: the actual permission
  prompt, scheduled delivery timing, and tap-to-open flow all need a real
  on-device pass — same caveat as Sign in with Apple/Google, `NEXT_STEPS.md`
  Phase 8's TestFlight step covers it.
- **Empty-state consistency.** **Done 2026-09-05.** `GroupHomeView`'s empty
  activity feed now uses `ContentUnavailableView`, same as `InsightsView` —
  distinct copy/icon for "no expenses yet" vs. "no matches for the current
  filter."
- **Amount-entry typography.** **Done 2026-09-05.** `AddExpenseView`'s amount
  field now uses SF Rounded too (`.title2.semibold` — sized for an inline
  Form row rather than `BalanceHeroView`'s standalone `.title.bold` hero
  display, same typeface treatment).
- **Select All / Select None on the equal-split member list.** **Done
  2026-09-05.** Shown once a group has more than 2 members (trivial with 1-2,
  where there's nothing to save); each disables itself once it's already the
  current state.
- **Inline error highlighting on exact/percentage splits.** **Done
  2026-09-05.** Each split row with a nonzero entry turns red while the
  total's off, alongside the existing footer line — an untouched
  (blank/zero) row doesn't turn red just because others don't sum up yet.
- **UPI deep link on Settle Up.** **Done 2026-09-05.** Optional per-member
  UPI ID (a new nullable field, user-supplied, never verified/processed by
  ClanTab); "Mark as Paid" builds a plain
  `upi://pay?pa=<vpa>&am=<amount>&...` link that hands off to
  GPay/PhonePe/Paytm, the person pays there, then confirms back in
  ClanTab. Doesn't touch the no-payment-processing non-goal — ClanTab
  never sees or moves money, just constructs a URI the OS opens. Real
  differentiation for the actual India-based audience this app is for.
  Server: schema v7 (`members.upi_vpa`), `GroupDO.updateMember()`
  replacing `renameMember()` with tri-state `displayName`/`upiVpa`
  semantics (absent = unchanged, `null` = clear, string = set), a new
  `optionalStringOrNull` parse helper distinguishing those three cases
  (empty string still rejected as invalid). Worker suite 166/166 passing;
  **not yet deployed** — bundled with the still-undeployed trash/schema-v6
  work from the previous item. iOS: `ClanTabKit`'s `Member.upiVpa`,
  `FieldUpdate<Value>` enum + `UpdateMemberRequest` on the wire types,
  `ClanTabClient.renameMember(displayName:upiVpa:accessToken:)`; App's
  Group Settings gained a "My UPI ID" section (blank clears it), and
  Settle Up shows a "Pay via UPI" link per transaction whenever the payee
  has a VPA set and the settlement is in INR (UPI's only currency) — built
  from `settlement.amountMinor`/`payee.upiVpa`, never touches the
  no-processing model. ClanTabKit 129/129 passing (was 127); App 63/63
  passing (view-layer only, no new tests — matches the rest of Phase 5).
- **Backup, in two tiers.** (1) Near-free: the CSV/JSON export already
  goes through `ShareLink`, whose share sheet already offers "Save to
  Files" — which already supports iCloud Drive and Google Drive today, if
  the Drive app is installed, with zero new code. The gap is just
  visibility — add an occasional gentle nudge to actually do it (reuses
  `Export.swift` entirely). **Tier 1 done 2026-09-05**, tier 2 (below)
  still open. (2) Medium: real automatic backup via CloudKit
  (iOS/iCloud only — no ₹ cost, the container comes with the Apple
  Developer Program already paid for) — a periodic silent snapshot, not a
  second source of truth, so no sync/conflict-resolution complexity
  (`GroupDO` stays authoritative; CloudKit here is purely a backup
  destination). **Skip a Google Drive API integration for now** — it needs
  its own OAuth scope-verification process with Google (real time cost,
  not money) and there's no Android client yet to justify it; revisit if
  `NAV_POLISH_PLAN.md` Part 3's cross-platform guardrails ever turn into an
  actual Android build.
  Tier 1 scope: `ClanTabKit`'s `BackupNudge` (pure `shouldShow(now:lastShownAt:firstLaunchAt:)`)
  plus `BackupNudgeStoring`/`UserDefaultsBackupNudgeStore`/`InMemoryBackupNudgeStore`
  — unlike the one-time `SyncNudgeStoring` this recurs every 30 days
  (after a first week of grace), no permanent dismiss. `AuthViewModel`
  gained `shouldShowBackupNudge(now:)`/`recordBackupNudgeShown(now:)`,
  reusing `syncNudge.firstLaunchAt()` rather than a second first-launch
  timestamp. App: a new `BackupNudgeCard` on Group Home (below the
  balance hero) offering the existing CSV export as a `ShareLink`
  directly, with a "Not now" dismiss for the current session; shown
  regardless of sign-in state (backup applies to everyone, unlike the
  sync nudge). ClanTabKit 134/134 passing (was 129); App 66/66 passing
  (was 63).
- **Explicit light/dark/system theme toggle.** **Done 2026-09-05.** Dark
  mode already works today — SwiftUI's automatic system-appearance
  adaptation, reviewed in `HANDOFF.md`'s Phase 6 checklist. What's missing
  is a manual override in Settings (a `Picker` + `.preferredColorScheme()`
  at the root, persisted via `@AppStorage`) for someone who wants to pin
  the app's look independent of their system setting. Cheap — hours, not
  days. `AppTheme` enum (`.system`/`.light`/`.dark`, `nil` `colorScheme`
  for system) shared between a `Picker` in Settings' "App" section and
  `.preferredColorScheme()` on `ClanTabApp`'s `WindowGroup` content, both
  reading the same `@AppStorage("clantab.theme")` key so the picker takes
  effect immediately. App 69/69 tests passing (was 66).
- **Category colors, formula-driven, not hand-picked.** **Done
  2026-09-05.** Categories already have name + SF Symbol icon (shipped
  2026-09-01); add a color. Rather than free-picking colors (inconsistent,
  risks poor contrast), extend `DESIGN_BIBLE.md`'s existing
  `oklch(55% 0.16 H)` accent formula — the one brand blue stays the app's
  primary/action color everywhere it is today; categories get a *pastel*
  variant of the same formula (higher lightness, lower chroma, hue varies
  per category), generated systematically rather than art-directed one at
  a time. Directly answers "the UI reads a bit dull" — one accent color
  across every screen is the actual cause, and a curated multi-hue
  category palette fixes it without abandoning the single-accent brand
  discipline. A full custom-color-picker for user-created categories is a
  reasonable follow-on once the curated palette ships — not needed for v1
  of this.
  ClanTabKit's `CategoryColor` is pure OKLCH→sRGB math (Björn Ottosson's
  OKLab formulas), `oklch(88% 0.07 H)`, with `H` a deterministic djb2 hash
  of the category name mod 360 — same name always gets the same color on
  every device, including free-form user-typed categories, with no shared
  name→color table to keep in sync. No UIKit/SwiftUI dependency, per the
  cross-platform guardrail; the App target's `ExpenseCategory.pastelColor`
  converts the resulting components into a `Color`. New shared
  `CategoryIconBadge` (icon on its pastel circle) used in the activity
  feed (`ActivityRow`, expenses only — settlements keep their neutral
  gray marker) and `CategoryPickerView`'s rows. ClanTabKit 141/141 passing
  (was 134); App 69/69 passing (view-layer wiring, no new App tests).

- **Push notifications.** **Moved into v1 scope 2026-09-05.** **Code done
  2026-09-05** (server + iOS); **real delivery still blocked on an owner
  action** — see below. The single highest-engagement feature on this
  list; "Priya added ₹500" landing on a lock screen is what turns "checked
  occasionally" into "used daily." No ₹ cost (APNs itself is free). Notify
  on someone *else's* action, never your own — scoped to the two
  highest-value mutations for v1 (new expense, settlement marked paid);
  edits/deletes/member changes stay silent, extendable later.
  Server: `lib/apns.ts` is a hand-rolled APNs HTTP/2 client (ES256
  provider-token JWT via Web Crypto, no library — same construction as
  `apple-oauth.ts`'s SIWA client secret, factored into a shared
  `lib/pem.ts`). `lib/notify.ts` fans a push out to every *other* claimed
  member's registered devices (`GroupDO.claimedIdentitiesExcluding`,
  `UserDO`'s new `devices` table / `registerDevice`/`unregisterDevice`/
  `deviceTokens`), forgetting any token APNs reports dead. Wired into
  `handleAddExpense`/`handleAddSettlement` via `ctx.waitUntil` — fire-and-
  forget, never blocks or fails the mutation's own response; a no-op
  (not an error) until the `APNS_*` secrets are set. New
  `POST /api/auth/devices` / `DELETE /api/auth/devices/:token` routes.
  Worker suite 193/193 passing (was 174).
  iOS: `ClanTabClient.registerDevice`/`unregisterDevice`; a new
  `AppDelegate` (App target only, never `ClanTabKit` — the cross-platform
  guardrail) bridges `UIApplication`'s registration callbacks and
  `UNUserNotificationCenterDelegate` into the app — permission is
  requested right after a fresh sign-in, foreground pushes still show a
  banner, and a tap opens the group via the *same* deep-link path as any
  other incoming URL (`RootView.handleDeepLink`). `AuthViewModel` caches
  the last-registered device token locally and unregisters it on sign-out,
  so a device switching identities doesn't leave the old identity
  subscribed. `aps-environment` entitlement added to `project.yml`.
  ClanTabKit 144/144 passing (was 141); App 69/69 passing (view/UIKit glue
  — untestable without a real device, matching the rest of this repo's
  external-service call sites, e.g. `apple-oauth.ts`/`google-auth.ts`).
  **What's left, all owner actions (`NEXT_STEPS.md` Phase 6) — none of
  this is buildable or verifiable from here:** (1) enable the Push
  Notifications capability on the App ID in the Apple Developer portal;
  (2) generate an APNs Auth Key (`.p8`) there, and set its Key ID + the
  Team ID + the key contents + the bundle id as the worker's
  `APNS_KEY_ID`/`APNS_TEAM_ID`/`APNS_PRIVATE_KEY`/`APNS_TOPIC` secrets
  (`wrangler secret put ...`); (3) a real-device TestFlight pass — the
  Simulator can't obtain a genuine APNs device token at all, only a real
  device can, so end-to-end delivery has zero test coverage until then.
- **Home-screen widget (WidgetKit).** **Moved into v1 scope, done
  2026-09-05.** Glanceable "you owe / you're owed" for the primary group
  without opening the app; fits the SF Rounded hero-numeral treatment
  already established. Needs an App Group + a lightweight refresh path,
  and a sane empty state for zero-groups-yet before first sign-in. No ₹
  cost. Scoped small-only, no user-facing group picker for v1 (owner
  decision, 2026-09-05) — "primary group" = whichever the app most
  recently opened, and the app pushes a snapshot rather than the widget
  making its own network calls, per the backlog's own "lightweight
  refresh path" wording; a configurable group picker
  (`WidgetConfigurationIntent`) and medium/large sizes are reasonable
  follow-ons.
  New `ClanTabWidgetExtension` target (`App/project.yml`), App-Groups
  entitlement (`group.com.clantab.app`) on both it and `ClanTab`. Pure
  logic in ClanTabKit: `WidgetSnapshotStoring` (a display cache, not a
  second source of truth — always the direct, unmodified output of
  `Balances.compute`, replaced wholesale on every refresh, matching
  `AGENTS.md`'s "derived, never persisted" rule in spirit) and
  `Balances.headline(_:)` (the largest-magnitude nonzero currency, for a
  multi-currency member in a widget with room for exactly one number).
  `MoneyFormat` moved from the App target into `ClanTabKit/Logic` (pure
  Foundation already, now shared by both the App and the widget
  extension). `GroupViewModel.refetch()`/`autoRefetch()` write the
  snapshot and call `WidgetCenter.reloadTimelines` on every successful
  fetch of the currently-open group — which is always "primary" by
  construction, since opening a group is what makes it most-recently-
  opened in the first place. ClanTabKit 152/152 passing (was 144); App
  70/70 passing (widget UI itself untested — WidgetKit rendering has no
  practical unit-test path, matching this repo's treatment of other
  UIKit-glue code; verified instead by installing the built app in the
  Simulator and confirming the `.appex` embeds and validates correctly).
- **Siri / App Intents.** **Moved into v1 scope 2026-09-05** — "Add a ₹500
  expense to Flatmates" via Shortcuts/Siri. No ₹ cost, moderate-high
  effort (disambiguating group/member/split by voice). Lowest-priority of
  the three above within v1, build last.

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

- Nothing currently. ~~Recurring/scheduled expenses~~ was here (dropped
  2026-08-31) and moved back to "In scope, next up" 2026-09-05 as
  reminder-only (not auto-post) — see that entry for why the two versions
  aren't the same decision.

## Confirmed — downstream of accounts, not standalone

- ~~**Settle across all groups with a person.**~~ **Shipped 2026-09-04.**
  `GET /api/auth/people` (`DESIGN.md` §13) — for a signed-in user, the net
  owed to/from every *linked* person across shared groups, per currency
  (never blended). `GroupDO.peerSettlements` picks the simplified settle-up
  edge between the caller and each other claimed member; the endpoint sums
  by person and returns per-group edges. The Apple `sub` is never exposed
  (opaque per-person id). "Settle All" fires one ordinary `addSettlement`
  per group — no cross-group ledger, each group stays authoritative. iOS:
  Settings → "Settle Across Groups" → per-person breakdown → Settle All.

- **Settle across all groups with a person — confirmed.** "Simplify
  dues/settling" meant cross-group netting: e.g. see and settle one
  combined view of everything owed between you and Bob across every
  group you share, not just per-group (per-group minimal-transaction
  settling already exists — the greedy debt-simplification algorithm,
  `PLAN.md` §2). Full spec lives in `ACCOUNTS_DESIGN.md` (it depends
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

Resolved 2026-09-05 — see the sequencing note at the top of this file and
`NEXT_STEPS.md` Phases 5-6.

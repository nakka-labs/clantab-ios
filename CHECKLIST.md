# ClanTab — Checklist

> Status: the one file for what's left and what's done. Replaces
> `NEXT_STEPS.md`, `FEATURE_BACKLOG.md`, `PLAN.md`, `HANDOFF.md`,
> `SHIP_PLAN.md`, `READINESS_CHECKLIST.md`, `ACCOUNTS_DESIGN.md`,
> `ACCESS_TOKEN_PLAN.md`, `MANDATORY_LOGIN_PLAN.md`, `NAV_POLISH_PLAN.md`,
> `BACKEND_PLAN.md`, and `LOGO_BRIEF.md` — all deleted, their unique
> technical content migrated into `DESIGN.md` (the technical contract) or
> `DESIGN_BIBLE.md` (the visual-identity contract), which stay the source
> of truth for *how*. This file is the only place tracking *what's left*
> and *what's done* — one checklist, not a doc per feature.
>
> **Deploy gate.** The app deploys/ships only once it looks finished —
> every item under "Design & UX polish" below is done — and only after a
> real testing and owner-approval pass. Nothing on this list implies an
> imminent deploy or App Store submission by default; submission is the
> last line item, gated behind everything above it, not a milestone to
> route around.

## To do

### Ship-blocking — App Store submission track
- [ ] Deploy the worker — bundles the still-undeployed `RegistryDO`→KV
      cutover, the access-token/regenerate-link route, and the trash +
      UPI schema (v6/v7) changes; ship together, not one at a time.
- [ ] Enable real push delivery: Push Notifications capability on the App
      ID, generate an APNs Auth Key, set the worker's `APNS_KEY_ID` /
      `APNS_TEAM_ID` / `APNS_PRIVATE_KEY` / `APNS_TOPIC` secrets.
- [ ] CloudKit backup, tier 2 (automatic silent snapshot; tier 1 — the
      Save-to-Files nudge — already shipped).
- [ ] Approve moderation copy + EULA zero-tolerance UGC clause; run
      `wrangler secret put ADMIN_TOKEN` to enable `GET /api/admin/reports`
      (currently a no-op).
- [ ] Custom domain + Universal Links (`nakka.dev`, already owned) — do
      this before broad TestFlight distribution so shared links and
      Associated Domains get tested before submission.
- [ ] Trademark + reverse-image checks (USPTO TESS / Google Lens/TinEye)
      on the "ClanTab" name and icon.
- [ ] Update App Store Connect's public support-contact field to
      `indra@nakka.dev` (already live in the privacy policy/support page).
- [ ] Rewrite privacy policy + App Privacy answers for mandatory
      Apple+Google login and UGC moderation (currently describe the
      retired no-login model).
- [ ] Rewrite App Store review notes (`docs/appstore/metadata.md`) —
      currently walk a reviewer through the retired no-login model.
- [ ] Decide the monetization stance — no urgency, but a conscious call
      (~$5-55/mo across 100-1M users, cost-modeled 2026-09-04).
- [ ] Add the `CLOUDFLARE_API_TOKEN` GitHub secret — nice-to-have,
      `make worker-deploy` already works locally without it.
- [ ] TestFlight on-device end-to-end pass — Sign in with Apple/Google,
      push notifications, and recurring-reminder delivery all need a real
      device, none of the three works in the Simulator → tag a version.
- [ ] Submit for App Store review — only after every item above **and**
      every item under "Design & UX polish" below.

### Design & UX polish — must land before "looks finished"

From a screenshot review + persona walkthrough (trip, household, couple,
one-off/casual, large-friend-group):

- [ ] Member identity color/avatar — extend `CategoryColor`'s hash-to-hue
      pattern to members (`MemberColor`, higher chroma), initials on the
      swatch, used everywhere a member appears.
- [ ] Insights donut chart, spend by member — using `MemberColor` once it
      exists; the single most-requested new chart.
- [ ] Group visual identity — emoji or `oklch`-formula color per group in
      the groups list and Group Home header.
- [ ] Shareable settle-up / recap card — client-side `ShareLink`-able
      image from the existing `Balances`/`Insights` output.
- [ ] Currency display — drop trailing `.00` on round amounts.
- [ ] Add Expense submit button — give it real contrast against the
      disabled/empty-field grey.
- [ ] Category picker icon weight — match the filled-icon weight used
      elsewhere (gear, chart glyphs).
- [ ] Root screen / "Your Groups" sheet layout — fix the large dead space
      above/below centered content.
- [ ] Settings sheet chrome — confirm the status-bar-light-on-dark-sheet
      capture was a transition-frame artifact, not a real bug.
- [ ] Onboarding walkthrough — short first-run flow (add a group → add an
      expense → settle up); first run currently drops in cold.
- [ ] Home Screen quick action — `UIApplicationShortcutItems` long-press
      action wrapping the existing `AddExpenseIntent`/`GroupEntity`.
- [ ] Dynamic Type / VoiceOver audit — an actual on-device pass, not an
      assumption, now that the feature surface is this large.
- [ ] Materials/blur on sheets (`.ultraThinMaterial`/`.regularMaterial`)
      instead of flat opaque cards.
- [ ] Tonal surface elevation — 3-4 deliberate grey tiers (canvas → card
      → nested card → modal) instead of two flat tones.
- [ ] Shadow/elevation on the balance hero card and primary buttons.
- [ ] Per-group accent color extended past the badge to that group's
      entire Group Home screen accent.
- [ ] SwiftUI Charts scrub/tooltip interaction + gradient fills on the
      existing Insights charts.
- [ ] Empty-state micro-copy pass — replace generic "no expenses yet"
      copy with something with more personality.
- [ ] Spring/matched-geometry transition from a group card into Group
      Home, replacing the flat push.
- [ ] Display typeface for wordmarks/hero numerals — `DESIGN_BIBLE.md`
      §1, adopted portfolio-wide, not yet built.
- [ ] Gradient app icon / hero-moment treatment — `DESIGN_BIBLE.md` §3,
      adopted portfolio-wide, not yet built.
- [ ] Custom empty-state illustration, one per app — `DESIGN_BIBLE.md`
      §4, adopted portfolio-wide, not yet built.
- [ ] Branded confirmation sound on each app's primary confirming action
      — `DESIGN_BIBLE.md` §5, adopted portfolio-wide, not yet built.

### Feature backlog — absorbed from the competitive scan

Splitwise/Tricount/Settle Up/Splid, primary sources only:

- [ ] Itemized expense entry, manual (type line items + prices, assign to
      people, app computes totals — no camera/OCR).
- [ ] Default split config per group (a standing split, e.g. 70/30,
      instead of re-toggling every time).
- [ ] Read-only web link for balances — a non-member sees "who owes what"
      via a plain browser link, no login, no write access.
- [ ] Offline queueing for adding an expense — needs an engineering check
      first: `GroupDO`'s direct-to-worker write model may require a live
      connection today.
- [ ] Balance-aging nudge ("you've owed ₹500 for 12 days") — distinct
      from the existing add-an-expense recurring reminders.
- [ ] PDF export of a settle-up/insights summary, alongside the existing
      CSV/JSON export and the recap-card image.
- [ ] Inline calculator on the amount field (`450+120` resolves).
- [ ] Archive a group — a soft "done with this one" state, distinct from
      Leave/Remove/Delete.

### Parked — not dropped, revisit deliberately

- Real profile photos (not initials avatars) and plain photo attachment
  on an expense — both need Cloudflare R2, which requires a card on file
  and breaks the zero-card invariant kept everywhere else in this project.
  Decided 2026-09-06 to ship initials/color avatars instead for now; if
  the invariant is ever deliberately broken, revisit both together, same
  R2 decision serves both.
- Receipt / bill reading (OCR) — needs on-device Vision work or a paid
  cloud OCR API plus a review/correction UI; not cheap like the rest of
  this list. Confirmed out of scope again 2026-09-06/07.
- Google Drive backup integration — needs its own OAuth scope-
  verification with Google and there's no Android client to justify it
  yet; revisit if an Android build ever happens.

## Non-goals — will not be built

FX / currency conversion · payment processing or money transfer · a
second cross-group ledger (cross-group settling still fires one
`addSettlement` per underlying group) · paid cloud AI.

## Done (condensed)

**Core v1, 2026-08-28 to 09-02** — group create/join, add/edit/delete
expense and settlement, equal/exact/percentage splits, categories + SF
Symbol icons, multi-currency (no auto-conversion), cross-group settling,
graphs/Insights, search & filter, CSV import/export, rename/remove
member, leave a group.

**Infra hardening, 2026-09-05** — `RegistryDO` retired for a
`JOIN_CODES` Workers KV namespace + a Cloudflare Rate Limiting binding
(20/min); foreground poll interval 5s → 25s; GitHub secret scanning +
push protection turned on (were off).

**Mandatory login, 2026-09-05** — Sign in with Apple + Google, guest
tier fully removed, `UserDO` rekeyed to `provider:sub`, "Add Member by
name" shipped as the prerequisite for removing guests without a
regression, group-switching + Settings reorg nav polish.

**Access token / credential decoupling, 2026-09-05** — a rotatable
`access_token` layered on top of `groupId` possession; "Regenerate Link"
invalidates every previously shared link/code without losing the group.

**Feature backlog batch, 2026-09-05** — trash + attribution (soft
delete, Recently Deleted, undo), duplicate an expense, recurring
reminders (not auto-post), empty-state consistency, amount-entry
typography, select all/none on equal split, inline split-error
highlighting, UPI deep link on Settle Up, backup tier 1 (Save-to-Files
nudge), light/dark/system theme toggle, formula-driven category pastel
colors.

**Identity-dependent features, 2026-09-05** — push notifications (code
complete, delivery gated on the owner actions above), home-screen widget
(WidgetKit, small size only), Siri/App Intents (voice-disambiguated
group, payer = you, equal split).

**Guideline 1.2 compliance, 2026-09-05** — report-content action +
block/remove-member path.

**Design system, 2026-09-05 to 09-07** — `oklch(55% 0.16 H)` color
formula extended to per-category and per-member identity colors; app
icon generation workflow + distinctiveness-check process folded into
`DESIGN_BIBLE.md`; display typeface, icon/hero gradients, empty-state
illustration, and confirmation sound adopted as portfolio-wide Bible
rules (2026-09-07, build work still open above).

**Support infra, 2026-09-05** — support contact moved off personal Gmail
to `indra@nakka.dev` (Cloudflare + Resend).

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
>
> **Reading an item.** Each has a token estimate — a rough CLI budget
> (Claude Code reading the relevant files, writing the change, running
> the existing test suite once or twice) — and 2-4 concrete steps, sized
> so a CLI session can do one step at a time without holding the whole
> feature in its head. `Owner` items have no CLI budget — they're an
> account, a decision, or a click nothing here can do. Estimates are
> order-of-magnitude planning numbers, not quotes.

## To do

### Ship-blocking — App Store submission track

- [ ] **Deploy the worker.** `~5k tokens` (CLI, once `wrangler login` is
      done)
      1. Owner: confirm `wrangler login` is authenticated on this
         machine (`wrangler whoami`).
      2. CLI: run `make worker-deploy`.
      3. CLI: hit the deployed URL's `/api/groups/:groupId` on a scratch
         group to confirm it's live.
- [ ] **Enable real push delivery.** `~5k tokens` (CLI) + `Owner` portal
      work
      1. Owner: enable the Push Notifications capability on the App ID
         in the Apple Developer portal.
      2. Owner: generate an APNs Auth Key (`.p8`), note its Key ID +
         Team ID.
      3. CLI: run `wrangler secret put` for `APNS_KEY_ID` / `APNS_TEAM_ID`
         / `APNS_PRIVATE_KEY` / `APNS_TOPIC` (owner pastes the values
         when prompted).
- [ ] **CloudKit backup, tier 2.** `~90k tokens` (CLI)
      1. Owner: enable the CloudKit capability + confirm the container
         in Xcode's Signing & Capabilities.
      2. CLI: add a `CKRecord` snapshot of the local export payload,
         written on a timer (reuse `BackupNudge`'s cadence logic).
      3. CLI: write it so `GroupDO` stays authoritative — this is a
         backup destination only, never a second source of truth.
      4. CLI: unit-test the snapshot-building logic; verify by installing
         in the Simulator and checking a record appears in the CloudKit
         Dashboard.
- [ ] **Approve moderation copy + enable admin reports.** `~5k tokens`
      (CLI) + `Owner` approval
      1. Owner: approve the moderation copy + EULA zero-tolerance UGC
         clause text.
      2. Owner: pick a strong random value for `ADMIN_TOKEN`.
      3. CLI: run `wrangler secret put ADMIN_TOKEN` with that value.
      4. CLI: confirm `GET /api/admin/reports` with `Authorization:
         Bearer <token>` returns real data, not a 404.
- [ ] **Custom domain + Universal Links.** `~45k tokens` (CLI) + `Owner`
      DNS/portal work
      1. Owner: point `nakka.dev`'s DNS at the Cloudflare Worker route.
      2. CLI: add the `apple-app-site-association` file + wire the
         Worker route for it.
      3. Owner: add the Associated Domains entitlement value in Xcode.
      4. CLI + Owner: install a TestFlight build and confirm a shared
         link opens the app, not Safari.
- [ ] **Trademark + reverse-image checks.** `Owner` — no CLI budget
      1. Owner: run "ClanTab" through USPTO TESS (classes 9, 36, 42).
      2. Owner: reverse-image-search the icon (Google Lens or TinEye).
      3. Owner: note the result in this file's Done section either way.
- [ ] **Update App Store Connect support-contact field.** `Owner` — no
      CLI budget
      1. Owner: log into App Store Connect, set the public support
         contact to `indra@nakka.dev`.
- [ ] **Rewrite privacy policy + App Privacy answers.** `~25k tokens`
      (CLI) + `Owner` approval
      1. CLI: rewrite `docs/privacy-policy.md` for mandatory Apple+Google
         login and UGC moderation.
      2. CLI: update the App Privacy answers doc to match.
      3. Owner: approve both.
- [ ] **Rewrite App Store review notes.** `~15k tokens` (CLI) + `Owner`
      approval
      1. CLI: rewrite `docs/appstore/metadata.md`'s reviewer walkthrough
         for the mandatory-login flow.
      2. Owner: approve.
- [ ] **Decide the monetization stance.** `Owner` — no CLI budget
      1. Owner: pick free / freemium / one-time (cost model already done,
         ~$5-55/mo across 100-1M users).
- [ ] **Add the `CLOUDFLARE_API_TOKEN` GitHub secret.** `~5k tokens`
      (CLI) + `Owner` token
      1. Owner: generate the Cloudflare API token with Workers-deploy
         scope.
      2. CLI: `gh secret set CLOUDFLARE_API_TOKEN` (owner pastes the
         value when prompted).
- [ ] **TestFlight on-device end-to-end pass.** `~10k tokens` (CLI build
      help) + `Owner` device time
      1. CLI: run the archive/export build steps, hand owner the
         `.ipa`/TestFlight build.
      2. Owner: on a real device, verify Sign in with Apple/Google, a
         push notification, and one recurring-reminder delivery.
      3. Owner: tag the version once it passes.
- [ ] **Submit for App Store review.** `Owner` — no CLI budget
      1. Owner: submit only after every item above **and** every item
         under "Design & UX polish" below.

### Design & UX polish — must land before "looks finished"

From a screenshot review + persona walkthrough (trip, household, couple,
one-off/casual, large-friend-group):

- [ ] **Member identity color/avatar.** `~70k tokens` (CLI)
      1. Add `MemberColor` to `ClanTabKit` — same djb2-hash-to-hue
         pattern as `CategoryColor`, higher chroma band.
      2. Unit-test it against a handful of fixed names for stable output.
      3. Wire an initials-on-swatch view and swap it in everywhere a
         member appears (rows, activity feed, split toggles, Insights).
      4. Build + test the App target.
- [ ] **Insights donut chart, spend by member.** `~40k tokens` (CLI,
      after `MemberColor` above)
      1. Add a donut/pie layout to `InsightsView` using SwiftUI Charts'
         `SectorMark`.
      2. Color each slice with `MemberColor`.
      3. Verify it renders correctly with 1, 2, and 6+ members.
- [ ] **Group visual identity.** `~55k tokens` (CLI)
      1. Add a nullable `emoji`/color field to the `Group` model +
         worker schema (`ADD COLUMN`, same pattern as prior additions).
      2. Add a picker in Group Settings.
      3. Show it in the groups list and the Group Home header.
      4. Test worker + ClanTabKit + App.
- [ ] **Shareable settle-up / recap card.** `~50k tokens` (CLI)
      1. Build a `View` that renders the settle-up/Insights summary as a
         card layout.
      2. Use `ImageRenderer` to turn it into an image, client-side only.
      3. Wire a `ShareLink` from Settle Up and/or Insights.
- [ ] **Currency display — drop trailing `.00`.** `~10k tokens` (CLI)
      1. Add a round-amount-aware branch to `MoneyFormat.string`.
      2. Add a unit test for a round amount and a non-round amount.
- [ ] **Add Expense submit button contrast.** `~8k tokens` (CLI)
      1. Give the enabled state its own fill color distinct from the
         disabled/empty-field grey.
- [ ] **Category picker icon weight.** `~5k tokens` (CLI)
      1. Match the SF Symbol weight to the filled icons used elsewhere
         (gear, chart glyphs).
- [ ] **Root screen / "Your Groups" sheet layout.** `~25k tokens` (CLI)
      1. Rework the empty/sparse-content layout so it doesn't center in
         a large dead `VStack`.
      2. Check both the zero-groups and few-groups states.
- [ ] **Settings sheet chrome check.** `~12k tokens` (CLI)
      1. Reproduce the captured screenshot's status-bar-light-on-dark
         moment.
      2. If it's a real bug, fix it; if it's a transition-frame artifact,
         note that in this file and close the item.
- [ ] **Onboarding walkthrough.** `~100k tokens` (CLI)
      1. Design a 3-screen flow: add a group → add an expense → settle
         up.
      2. Build it as a first-run sheet, gated on a stored "seen
         onboarding" flag.
      3. Wire it into the launch/routing path ahead of "Your Groups."
      4. Test the flag logic and the routing change.
- [ ] **Home Screen quick action.** `~20k tokens` (CLI)
      1. Add a `UIApplicationShortcutItems` entry for "Add Expense to
         <primary group>."
      2. Wire it to the existing `AddExpenseIntent`/`GroupEntity`.
      3. Verify the long-press action appears and opens the right flow.
- [ ] **Dynamic Type / VoiceOver audit.** `~45k tokens` (CLI, on-device
      pass)
      1. Step through every screen at the largest accessibility text
         size in the Simulator.
      2. Turn on VoiceOver and step through the primary flows.
      3. Fix layout breaks as found; log anything deferred back into
         this item.
- [ ] **Materials/blur on sheets.** `~25k tokens` (CLI)
      1. Swap flat card backgrounds on Add Expense, Settings, and Your
         Groups sheets to `.ultraThinMaterial`/`.regularMaterial`.
      2. Check contrast still holds in both light and dark mode.
- [ ] **Tonal surface elevation.** `~30k tokens` (CLI)
      1. Define 3-4 grey tiers (canvas → card → nested card → modal) as
         named constants.
      2. Apply them consistently across the existing screens.
- [ ] **Shadow/elevation on hero card + buttons.** `~10k tokens` (CLI)
      1. Add a subtle shadow to `BalanceHeroView` and primary buttons.
- [ ] **Per-group accent color, extended past the badge.** `~30k tokens`
      (CLI, after Group visual identity above)
      1. Apply a group's own hue to that group's entire Group Home
         screen accent, not just the badge.
      2. Verify two different groups read visibly differently.
- [ ] **Chart interaction + gradient fills.** `~25k tokens` (CLI)
      1. Add scrub/tooltip gestures to the existing `InsightsView`
         charts.
      2. Add a gradient fill using SwiftUI Charts' native support.
- [ ] **Empty-state micro-copy pass.** `~12k tokens` (CLI)
      1. Rewrite each `ContentUnavailableView` string with more
         personality, keeping them accurate to the actual empty state.
- [ ] **Spring/matched-geometry transition.** `~30k tokens` (CLI)
      1. Add a `matchedGeometryEffect` from a group card into Group Home,
         replacing the flat push.
      2. Verify it doesn't break the existing navigation stack/back
         behavior.
- [ ] **Display typeface for wordmarks/hero numerals.** `~35k tokens`
      (CLI) + one design decision
      1. Owner/CLI: pick a free Google Fonts family for the display face.
      2. CLI: bundle it, apply it to the ClanTab wordmark + hero numerals
         only.
      3. CLI: verify Dynamic Type still scales it correctly.
- [ ] **Gradient app icon / hero-moment treatment.** `~35k tokens` (CLI)
      + a new icon asset
      1. Owner/CLI: generate the two-stop-gradient icon variant per
         `DESIGN_BIBLE.md` §3's workflow.
      2. CLI: run the icon through the §3 distinctiveness check.
      3. CLI: apply the same gradient treatment to the balance hero card.
- [ ] **Custom empty-state illustration.** `~20k tokens` (CLI wiring) +
      one illustration asset
      1. Owner/CLI: produce one illustration asset for ClanTab's
         zero-state.
      2. CLI: wire it into every "no groups yet"/"no expenses yet" state.
- [ ] **Branded confirmation sound.** `~20k tokens` (CLI wiring) + one
      audio asset
      1. Owner/CLI: produce or source one short confirmation sound.
      2. CLI: play it alongside the existing haptic on "settled up,"
         never replacing it.
- [ ] **Tabular figures + thousands-separator style.** `~10k tokens`
      (CLI)
      1. Set the tabular/lining figure font feature on hero numerals.
      2. Confirm one consistent separator style in `MoneyFormat`.
- [ ] **Tint neutral text/surface tones.** `~20k tokens` (CLI)
      1. Mix 10-15% of the app's hue into the grey tokens defined in
         "Tonal surface elevation" above.
      2. Spot-check contrast ratios still pass.
- [ ] **Name + standardize the shared spring curve.** `~15k tokens`
      (CLI)
      1. Pick one response/dampingFraction pair, name it (e.g.
         `.claimSettle`).
      2. Apply it to every confirm-moment transition instead of
         per-call-site defaults.

### Feature backlog — absorbed from the competitive scan

Splitwise/Tricount/Settle Up/Splid, primary sources only:

- [ ] **Itemized expense entry, manual.** `~130k tokens` (CLI)
      1. Add an `items: [LineItem]` shape (name, price, assignees) to
         the expense model, worker + `ClanTabKit`.
      2. Add a UI for typing line items within Add Expense.
      3. Compute per-person totals from item assignments, reusing the
         existing split-math patterns.
      4. Test worker, `ClanTabKit`, and App.
- [ ] **Default split config per group.** `~45k tokens` (CLI)
      1. Add a nullable "default split" field to the group/member schema.
      2. Add a save/apply UI in Group Settings.
      3. Pre-fill Add Expense from it when set.
- [ ] **Read-only web link for balances.** `~55k tokens` (CLI)
      1. Add a new unauthenticated `GET` route rendering a plain HTML
         balances view for a `groupId` (+ token).
      2. Serve it `noindex`, same as the existing group stub page.
      3. Add a "Share view-only link" action in the app.
- [ ] **Offline queueing for adding an expense.** `~20k tokens`
      investigation, build TBD after
      1. CLI: check whether `GroupDO`'s write path already tolerates a
         disconnected client (does the request just fail, or hang?).
      2. CLI: report back findings + a real effort estimate before
         committing to building it.
- [ ] **Balance-aging nudge.** `~35k tokens` (CLI)
      1. Reuse the recurring-reminder scheduling infra for a "you've
         owed X for N days" local notification.
      2. Trigger it off a stale nonzero balance, not a fixed calendar
         cadence.
- [ ] **PDF export.** `~45k tokens` (CLI)
      1. Build a one-page PDF layout (PDFKit) from the existing
         `Balances`/`Insights` output.
      2. Add it as a second `ShareLink` option alongside CSV/JSON.
- [ ] **Inline calculator on the amount field.** `~25k tokens` (CLI)
      1. Parse simple `+`/`-` arithmetic typed into the amount `TextField`.
      2. Resolve it to a number on blur/submit, unit-test the parser.
- [ ] **Archive a group.** `~35k tokens` (CLI)
      1. Add a nullable `archived_at` to the group schema.
      2. Add "Archive"/"Unarchive" to Group Settings, distinct from
         Leave/Remove/Delete.
      3. Filter archived groups out of the default groups list, with a
         toggle to see them.

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
illustration, confirmation sound, tabular figures, tinted neutrals, and
a named spring curve adopted as portfolio-wide Bible rules (2026-09-07,
build work still open above).

**Support infra, 2026-09-05** — support contact moved off personal Gmail
to `indra@nakka.dev` (Cloudflare + Resend).

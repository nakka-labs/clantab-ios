# ClanTab — Next Steps

> Single running master order for everything left before v1 ships. Detail
> lives in `MANDATORY_LOGIN_PLAN.md`, `ACCESS_TOKEN_PLAN.md`,
> `NAV_POLISH_PLAN.md`, `FEATURE_BACKLOG.md`, `SHIP_PLAN.md`,
> `READINESS_CHECKLIST.md`, `DESIGN.md` §12/§13 — those stay authoritative
> for *how*; this file is the only place that says *in what order*, and owns
> the master **[CLI]**/**[OWNER]** sequencing. Those other docs' own
> "suggested order" sections point back here instead of keeping a second
> copy. Last resequenced: 2026-09-04.
>
> **Ground rule (confirmed 2026-09-04):** v1 doesn't ship until this whole
> list is checked off — a slower, single high-quality release beats several
> partial ones. Nothing below is quietly deferred to "v1.1" unless marked so.

---

## Phase 0 — Owner decisions that unblock everything else

Pure decisions / account creation, zero CLI dependency — clear these first
so nothing downstream stalls waiting on you.

- [x] **[OWNER]** Confirm dropping the guest tier is final — **confirmed
      2026-09-04** (`MANDATORY_LOGIN_PLAN.md` Part 0).
- [x] **[OWNER]** Confirm ~zero real signed-in users on the current `UserDO`
      keying — **confirmed 2026-09-04: app has never left internal
      TestFlight testing, no real users.** Phase 2's re-keying is a clean
      cutover, no migration script needed (`MANDATORY_LOGIN_PLAN.md` Part 0).
- [x] **[OWNER]** Create the Google Cloud OAuth client — **done
      2026-09-05**, client ID wired into `worker/wrangler.jsonc`
      (`GOOGLE_AUDIENCE`) and `AppConfig.swift` (`MANDATORY_LOGIN_PLAN.md`
      Part 1).

## Phase 1 — Cheap infra hardening (no dependencies — do now)

- [x] **[CLI]** `RegistryDO` singleton → Workers KV (`SHIP_PLAN.md` Track 3
      §3) — the one real architectural scaling ceiling; cheap now, likely
      lowers the bill. **Done 2026-09-05:** `RegistryDO` deleted
      (`wrangler.jsonc` `v3` migration, `deleted_classes`); join-code
      resolution moved to a `JOIN_CODES` KV namespace
      (`worker/src/lib/join-codes.ts`), rate limiting moved to a Cloudflare
      Rate Limiting binding (`RESOLVE_RATE_LIMITER`, 20/min). Worker tests
      green (145/145), `wrangler deploy --dry-run` validates the config.
      **Not yet deployed** — `wrangler deploy` is still yours to run
      (`make worker-deploy`); no real users existed on the old `RegistryDO`
      data, so this is a clean cutover, not a migration.
- [x] **[CLI]** Foreground poll interval 5s → ~20-30s (`SHIP_PLAN.md` Track 3
      §8). **Done 2026-09-05:** `GroupViewModel.pollInterval` → 25s.
- [x] **[CLI]** Verify GitHub secret scanning + push protection are on
      (`MANDATORY_LOGIN_PLAN.md` Part 4). **Done 2026-09-05:** both were
      actually **off** — enabled via the repo API
      (`security_and_analysis.secret_scanning` /
      `.secret_scanning_push_protection`, both now `enabled`).

## Phase 2 — Mandatory login (Apple + Google, guests removed)

`MANDATORY_LOGIN_PLAN.md` has the full detail. This is the biggest
structural rework left in the app — everything after this phase should be
built once, against the final post-login shape, not built now and reworked
again once the guest tier disappears.

- [x] **[CLI]** Part 1 — Google Sign-In (worker route + iOS button + view
      model). Needs Phase 0's OAuth client. **Done 2026-09-05:** worker
      side tested (145/145), iOS side built + tested (56/56) via
      `xcodegen generate` + `xcodebuild test`, committed (`ebb8a9e`) and
      pushed to `main`.
- [x] **[CLI]** Part 2 — `UserDO` re-keying to `provider:sub`. **Verified
      2026-09-05 already done** — built alongside Part 1's Google Sign-In
      work; no separate change needed (`MANDATORY_LOGIN_PLAN.md` Part 2).
- [x] **[CLI]** Part 2.5 — Add Member by name. **Hard prerequisite for Part
      3, not optional polish** — without it, removing guests is a real
      regression (see the plan's "Critical finding" callout). **Done
      2026-09-05:** "Add Someone" in `GroupSettingsView`; verified end to
      end against the deployed Worker (`MANDATORY_LOGIN_PLAN.md` Part 2.5).
- [ ] **[CLI]** Part 3 — Remove the guest tier (`StartView`,
      `JoinChoiceView`/`ClaimMemberView`, retire `IdentityStoring`).

## Phase 3 — Access token / credential decoupling

`ACCESS_TOKEN_PLAN.md` (new). Decouples the shareable link/code from the
Durable Object's permanent identity, so a leaked or socially-revoked link
can actually be rotated — not possible today (`groupId` possession is the
only credential, `DESIGN.md` §2/§8). Cost-modeled 2026-09-04, ~1.5-2.5 days.
Not a hard dependency on Phase 2 — today's Bearer+claimed-member auth
already works — but cheapest done once Part 2.5's "Add Member by name"
sharing story is final, so the regenerate-link UI is designed once.

- [ ] **[CLI]** Parts 1-3 — server token issuance/verification (the
      `requireGroup` chokepoint in `worker/src/index.ts`, a new
      `access_token` key in `group_meta`), iOS carry + regenerate, the
      join-code path.
- [ ] **[OWNER]** Part 4 — pick a migration strategy for existing groups
      (trivial either way given today's user count).

## Phase 4 — Nav polish

`NAV_POLISH_PLAN.md` — **sequenced after Phase 2** (previously scoped
standalone; moved here so `StartView` is touched once, on its final
signed-in-only shape, not once now and again when guests are removed).

- [ ] **[CLI]** Part 1 — fix group switching (`GroupsListView` extraction +
      toolbar entry).
- [ ] **[CLI]** Part 2 — Settings reorg (Account / App sections).
- Part 3's cross-platform guardrails are ambient — apply throughout every
  phase above, not a scheduled step of their own.

## Phase 5 — Feature backlog, identity-independent

`FEATURE_BACKLOG.md` "In scope, next up" — no dependency on Phase 2, ships
in any order relative to it, and order within this phase doesn't matter:

- [ ] **[CLI]** Trash + attribution (soft delete, "Recently Deleted", undo
      toast)
- [ ] **[CLI]** Duplicate an expense
- [ ] **[CLI]** Recurring reminders (not auto-post)
- [ ] **[CLI]** Empty-state consistency
- [ ] **[CLI]** Amount-entry typography
- [ ] **[CLI]** Select All / Select None (equal split)
- [ ] **[CLI]** Inline split-error highlighting
- [ ] **[CLI]** UPI deep link on Settle Up
- [ ] **[CLI]** Backup, two tiers (Save-to-Files nudge + CloudKit)
- [ ] **[CLI]** Theme toggle (light/dark/system)
- [ ] **[CLI]** Category pastel colors

## Phase 6 — Feature backlog, identity-dependent

Needs Phase 2's stable `UserDO` keys — building these against a
soon-to-be-rekeyed identity risks rework.

- [ ] **[CLI]** Push notifications
- [ ] **[CLI]** Home-screen widget (WidgetKit)
- [ ] **[CLI]** Siri / App Intents (build last of the three — lowest
      priority within v1)

## Phase 7 — Guideline 1.2 (user-generated content moderation)

Real App Store requirement for a public listing, not optional
(`SHIP_PLAN.md` Track 3 §7).

- [ ] **[CLI]** Report-content action + block/remove-member path (remove
      already exists via Group Settings; report doesn't).
- [ ] **[OWNER]** Approve moderation copy + EULA zero-tolerance UGC clause.

## Phase 8 — App Store submission track

`SHIP_PLAN.md` Tracks 1 & 2, `READINESS_CHECKLIST.md`.

- [ ] **[CLI]** Track 1 — custom domain + Universal Links (`nakka.dev`
      already owned). Do this **before** broad TestFlight distribution, not
      after — so shared links look right and Associated Domains gets tested
      before submission, not scrambled at the end.
- [ ] **[OWNER]** Trademark + reverse-image checks (USPTO TESS) on the
      "ClanTab" name/icon.
- [x] **[OWNER]** Move the support contact off personal Gmail to a
      dedicated alias — **done 2026-09-05: `indra@nakka.dev`** (Cloudflare
      + Resend, forwards to Gmail). Live in `docs/privacy-policy.md` +
      `docs/support.html`. Still needs: update App Store Connect's public
      support-contact field to match once submission starts.
- [ ] **[CLI to draft, OWNER to approve]** Privacy policy + App Privacy
      answers — update to describe Apple+Google mandatory login and UGC
      moderation (currently describes the no-login model).
- [ ] **[CLI to draft, OWNER to approve]** App Store review notes
      (`docs/appstore/metadata.md`) — currently walk a reviewer through "the
      no-login model," which will be false.
- [ ] **[OWNER]** Monetization stance — conscious decision, no urgency
      (~$5-55/mo across 100-1M users, cost-modeled 2026-09-04).
- [ ] **[OWNER]** `CLOUDFLARE_API_TOKEN` GitHub secret — nice-to-have, not
      blocking (`make worker-deploy` works locally meanwhile).
- [ ] **[OWNER]** TestFlight on-device end-to-end pass (Sign in with
      Apple/Google can't run in the simulator) → tag a version.
- [ ] **[OWNER]** Submit for App Store review.

---

## Historical record (shipped, kept for context — not on the critical path)

- [x] Accounts phase code (worker steps 1-5, iOS 6a-6f) — complete on
      `main`, `ACCOUNTS_DESIGN.md` §16. Superseded target-state-wise by
      `MANDATORY_LOGIN_PLAN.md` above (Phase 2); this is what's live today.
- [x] Edit/delete an expense or settlement, rename group/member, remove
      member, leave a group — shipped 2026-09-04.
- [x] Cross-group settling — shipped 2026-09-04.
- [x] Percentage splits, categories+icons, graphs, search/filter, CSV
      import, multi-currency — shipped 2026-09-01/02.

## Deliberate non-goals — will NOT be built

FX / currency conversion · payment processing or money transfer · receipt
OCR / bill reading (the one revisit-later item on the feature list —
`FEATURE_BACKLOG.md` "Explicitly held off") · a second cross-group ledger
(cross-group settling still fires one `addSettlement` per underlying group).

**Corrected 2026-09-05:** third-party login is no longer a non-goal — Google
joins Apple as part of the mandatory login model (`MANDATORY_LOGIN_PLAN.md`).
Sign in with Apple is no longer the only identity.

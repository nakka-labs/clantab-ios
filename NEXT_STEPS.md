# ClanTab — Next Steps

> A single running list of what's left, pulled together from
> `ACCOUNTS_DESIGN.md` §16, `READINESS_CHECKLIST.md`, `FEATURE_BACKLOG.md`,
> `SHIP_PLAN.md`, and `DESIGN.md` §12. Those stay authoritative for detail; this
> is the index. Last synced: 2026-09-04.

---

## 1. Ship the accounts phase (owner tasks — not code)

The code (worker steps 1–5, iOS 6a–6f, docs) is complete on `main`.
Detail: `ACCOUNTS_DESIGN.md` §16.

- [x] **Deploy the worker** + `wrangler secret put SESSION_SIGNING_KEY`
      (2026-09-04, `/api/auth/*` verified live).
- [x] **Enable Sign in with Apple** on the `com.clantab.app` App ID + confirm in
      Xcode.
- [x] **Re-deploy the worker** for the edit/delete + settings routes
      (2026-09-04, verified live).
- [x] ~~**Apple token revocation on account deletion**~~ (Apple Guideline
      5.1.1(v)) — **live 2026-09-04**. Code (`lib/apple-oauth.ts`,
      `authorizationCode` plumbing) + all four `SIWA_*` secrets set + deployed.
      The `authorizationCode` exchange runs on sign-in; `DELETE
      /api/auth/account` calls `/auth/revoke`. End-to-end proof is the
      TestFlight delete-account test (`wrangler tail` will show a `console.error`
      from `apple-oauth` if the `.p8` or Services ID is wrong — non-fatal, but
      Apple's review checks deletion).
- [ ] **TestFlight on-device pass** — the real end-to-end check of steps 6a–6f
      (Sign in with Apple can't run in the simulator). Checklist:
      guest flow unaffected · sign in · list syncs to a 2nd device · claim ·
      one-time nudge · relaunch stays signed in · revoke in iOS Settings drops to
      guest · Delete Account leaves the ledger intact.
- [ ] **Privacy** — update `docs/privacy-policy.md` and the App Store Connect
      **App Privacy** answers to disclose the Apple `sub` (User ID, "App
      Functionality", not tracking). `READINESS_CHECKLIST.md` §"Legal / privacy".

---

## 2. Small functional gaps (not designed — decide if they're v1.1)

- [x] ~~Edit / delete an expense or settlement~~ — shipped 2026-09-04
      (`DESIGN.md` §2 PUT/DELETE; swipe-to-delete + tap-to-edit in the app).
- [x] ~~Rename a group / change its default currency~~ — shipped 2026-09-04
      (`PATCH /api/groups/:id`; Group Settings screen).
- [x] ~~Rename or remove a member~~ — shipped 2026-09-04 (`PATCH` / `DELETE`
      `.../members/:id`; remove is blocked with `MEMBER_IN_USE` when the member
      has activity, is claimed, or is the last one).
- [x] ~~Manually leave / remove a group from your device's list~~ — shipped
      2026-09-04 ("Leave This Group" in Group Settings; "Remove from This
      Device" context menu on the start-screen list — both device-local).

*(Section 2 is done — leaving it here as the record.)*

---

## 3. Backlog features (designed-ish, not built)

`FEATURE_BACKLOG.md` has the full notes.

- [ ] **Cross-group settling** — "settle everything with Bob across all groups".
      Spec in `LOGIN_ACCOUNTS_BRIEF.md` / `FEATURE_BACKLOG.md`. **Now unblocked**
      — the `UserDO` identity index is its only dependency. Read-side
      aggregation over shared groups, per-currency, fires normal per-group
      `addSettlement`s. This was the original point of doing accounts.
- [ ] **Plain photo attachment on an expense** (no OCR). Open question: R2
      (needs a card on file — breaks the zero-card invariant) vs. local-only
      (no card, not shared with the group).
- [ ] **Date-range / amount-range filters** on the activity feed — left out of
      the search/filter pass.

---

## 4. Infrastructure / operational

`SHIP_PLAN.md` Tracks 1, 3, 4.

- [ ] **Custom domain + Universal Links** (Track 1). `nakka.dev` is owned.
      Invites work by 6-char code today; tappable `https://…/g/:id` links need
      the domain on the Worker + the Associated Domains entitlement +
      `apple-app-site-association`.
- [ ] **WebSocket live updates** (Track 4) — currently a 5s foreground poll.
      Only if concurrent usage actually appears.
- [ ] **Operational hardening** (Track 3): observability/alerting, a billing
      alert, rate-limit review — including **`POST /api/auth/apple` per-IP**
      (`ACCOUNTS_DESIGN.md` §3 wants it; not done).
- [ ] **`CLOUDFLARE_API_TOKEN` GitHub secret** — enables deploy-on-tag
      (`worker-deploy.yml`); `make worker-deploy` locally meanwhile.
- [ ] **App icon reverse-image + USPTO trademark checks** — the icon shipped;
      the checks on it haven't run.

---

## 5. Deliberate non-goals — will NOT be built

FX / currency conversion · recurring or scheduled expenses · receipt OCR /
bill reading · payment processing or money transfer · push-notification
servers or email collection · passwords or third-party login.

(Sign in with Apple is the only identity, requesting no name and no email.)

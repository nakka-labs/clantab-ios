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
- [ ] **Re-deploy the worker** for the edit/delete routes (`make worker-deploy` —
      the live instance predates commit `ccf634e`).
- [ ] **Apple token revocation on account deletion** (Apple Guideline 5.1.1(v),
      submission blocker):
  - [ ] Create a Services ID (`SIWA_SERVICES_ID`, e.g. `com.clantab.app.signin`),
        a Key ID, and a `.p8` "Sign in with Apple" key in the Apple Developer
        portal.
  - [ ] `wrangler secret put` for `SIWA_SERVICES_ID` / `SIWA_TEAM_ID`
        (`UK652GNPP7`) / `SIWA_KEY_ID` / `SIWA_PRIVATE_KEY`.
  - [ ] **Code**: capture `authorizationCode` in the iOS SIWA flow → server-side
        token exchange (`lib/apple-oauth.ts`, client-secret JWT) → store the
        refresh token in `UserDO` → `POST appleid.apple.com/auth/revoke` in
        `DELETE /api/auth/account` (currently a `// TODO` at
        `worker/src/index.ts`). *Claude can do this part.*
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
- [ ] **Rename a group / change its default currency** — set at creation,
      immutable after.
- [ ] **Rename or remove a member** — members can only be added; a typo or a
      duplicate placeholder is permanent.
- [ ] **Manually leave / remove a group from your device's list** — today a
      group is only dropped on a 404.

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

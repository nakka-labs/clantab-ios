# ClanTab — Readiness Checklist

> One consolidated list of everything left before this is "complete and
> deployment ready." Doesn't replace the detailed docs — points at them.
> Sources: `SHIP_PLAN.md` (v1 App Store track), `LOGIN_ACCOUNTS_BRIEF.md`
> (accounts), `FEATURE_BACKLOG.md` (features).

## Branding & identity

- Real app icon — current one is a placeholder (flat blue, white "="),
  fine for internal TestFlight, must be swapped before App Store
  submission. Generation prompt + a distinctiveness check against
  competitor icons (visual survey, reverse image search, trademark
  search, small-size confusability test) are in `LOGO_BRIEF.md`.
- Wordmark/logo usable across the icon, README, App Store listing, and any
  landing page — one asset, reused everywhere, not redrawn per surface.
- Launch screen — currently plain system background (compliant, unbranded).
- App Store screenshots — reshoot cleanly on current UI (existing ones
  were from the runtime-verification pass, not a real photoshoot).
- A real support/marketing page on `clantab.nakka.dev`, replacing the bare
  GitHub-repo link currently in `docs/appstore/metadata.md` — same domain
  already needed for Universal Links, so it's a page, not new infra.

## v1 App Store track (already tracked, still open — see `SHIP_PLAN.md`)

- Add an internal TestFlight tester, install, run the on-device
  end-to-end pass, tag `v0.4.0`.
- App Privacy answers + screenshots for external testing/submission.
- `CLOUDFLARE_API_TOKEN` GitHub secret for automated tag-deploy (optional —
  `make worker-deploy` works locally meanwhile).
- Custom domain wiring + Universal Links (optional — 6-character join code
  works without it).
- Track 3 operational hardening: observability/alerting, rate-limit
  review, a billing alert.

## Feature scope (see `FEATURE_BACKLOG.md` / `LOGIN_ACCOUNTS_BRIEF.md`)

Ship order locked: independent cheap features → multi-currency → accounts
→ cross-group settling. Photo attachment shelved (cost/setup tradeoff
unresolved, see backlog).

- ~~Custom/percentage splits~~ (v2), ~~categories + icons~~ (v3), ~~graphs~~
  (`Insights` + SwiftUI Charts), ~~search/filter~~ (`ActivityFiltering`, feed
  only), ~~multi-currency ledgers~~ (v4 — per-currency, no FX), and ~~CSV import~~
  (`CSVImport` — ClanTab + Splitwise formats, client-only) — **done 2026-09-01/02**.
  The full independent-feature batch is complete.
- Accounts: Sign in with Apple, placeholder-member claim flow, the
  groupId-per-identity index, **in-app account deletion** (Apple
  Guideline 5.1.1(v) — not optional once accounts exist).
- Cross-group settling with a person — strictly after accounts.

## Engineering discipline

- Golden parity tests (`worker/test/logic.test.ts` +
  `ClanTabKitTests/GoldenParityTests.swift`) extended in the same commit
  whenever splits-by-type or per-currency simplification logic changes —
  not after, not on one side only.
- `DESIGN.md`, `BACKEND_PLAN.md`, `PLAN.md`, `AGENTS.md`, `README.md`
  updated as each feature actually ships, not left describing the old
  no-login/no-splits/single-currency model after the code has moved on.

## Legal / privacy (new, caused by accounts)

- Privacy policy text (`docs/privacy-policy.md`) updated to describe
  Sign in with Apple + account data once accounts ship — it currently
  describes the no-login model.
- App Privacy answers in App Store Connect re-submitted to match (they
  currently state no accounts/no linked data).

# ClanTab — Readiness Checklist

> One consolidated list of everything left before this is "complete and
> deployment ready." Doesn't replace the detailed docs — points at them.
> Sources: `SHIP_PLAN.md` (v1 App Store track), `MANDATORY_LOGIN_PLAN.md`
> (accounts/login), `FEATURE_BACKLOG.md` (features).

## Branding & identity

- Real app icon — ✅ done 2026-09-02 (`LOGO_BRIEF.md`), exact
  `DESIGN_BIBLE.md` §2 blue (`#0074CA`), legibility-checked at real iOS
  sizes. The in-app `AccentColor` was synced to the same blue in the same
  pass (it was still the off-formula placeholder `#0A7AFF`). Reverse image
  search and trademark search (USPTO TESS) still need running with real
  tools before App Store submission — not done in a cloud session without
  them.
- Wordmark/logo — ✅ done 2026-09-02: `docs/branding/` (SVG + PNG, dark +
  white variants, regenerator script). "=" mark + "ClanTab" in SF Pro
  Rounded Bold. README header updated to use it.
- Launch screen — ✅ done 2026-09-02: the white "=" mark on the brand blue
  (`UILaunchScreen` dict, `LaunchLogo` + `AccentColor`), matches the icon.
- App Store screenshots — ✅ done 2026-09-02: `docs/appstore/screenshots/`,
  four 1320×2868 (6.9") frames (Group Home, Insights, Add Expense, Settle Up),
  alpha-stripped, 9:41 status bar. Upload as-is to App Store Connect.
- Support page — ✅ drafted 2026-09-02: `docs/support.html` (contact + FAQ +
  privacy/repo links), published via `pages.yml` at
  `https://nakka-labs.github.io/clantab-ios/support.html` and set as the App
  Store Support URL. Move to `clantab.nakka.dev/support` once the domain is
  wired (Track 1). Still needs: Pages "GitHub Actions" source confirmed live,
  and a dedicated support email to replace `id0399@gmail.com`.

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

## Feature scope

Master order (including accounts/login sequencing) now lives in
`NEXT_STEPS.md` — this section previously duplicated it and had drifted
stale (it still described the shipped optional-guest accounts model as the
target). Quick pointers:

- **Shipped:** percentage splits, categories+icons, graphs, search/filter,
  CSV import, multi-currency, edit/delete/rename/remove/leave, cross-group
  settling — see `NEXT_STEPS.md` "Historical record."
- **In flight, not a target state:** accounts as shipped (optional Sign in
  with Apple, `ACCOUNTS_DESIGN.md`) is being replaced by
  `MANDATORY_LOGIN_PLAN.md` (Apple + Google, mandatory, guests removed).
  Don't build against the optional-guest model — it's going away.
- **Remaining v1 scope:** `NEXT_STEPS.md` Phases 0-8 — mandatory login,
  access-token hardening (`ACCESS_TOKEN_PLAN.md`, new), nav polish
  (`NAV_POLISH_PLAN.md`), the full `FEATURE_BACKLOG.md` "In scope, next up"
  list (including push/widget/Siri, moved into v1 2026-09-05), Guideline
  1.2 moderation, and App Store submission.

## Engineering discipline

- Golden parity tests (`worker/test/logic.test.ts` +
  `ClanTabKitTests/GoldenParityTests.swift`) extended in the same commit
  whenever splits-by-type or per-currency simplification logic changes —
  not after, not on one side only.
- `DESIGN.md`, `BACKEND_PLAN.md`, `PLAN.md`, `AGENTS.md`, `README.md`
  updated as each feature actually ships, not left describing the old
  no-login/no-splits/single-currency model after the code has moved on.

## Legal / privacy (new, caused by accounts)

- **[CLI to draft, OWNER to approve]** Privacy policy text
  (`docs/privacy-policy.md`) updated to describe Sign in with Apple +
  account data once accounts ship — it currently describes the no-login
  model.
- **[OWNER]** App Privacy answers in App Store Connect re-submitted to match
  (they currently state no accounts/no linked data).
- **[CLI]** Report-content + block/remove-member mechanism (Apple Guideline
  1.2 — user-generated content). Required for a real public listing, not
  optional. `SHIP_PLAN.md` Track 3 §7.
- **[OWNER]** Trademark + reverse-image clearance (USPTO TESS) on the
  "ClanTab" name and icon — not done in a cloud session, needs real tools.
  `LOGO_BRIEF.md` checklist.
- **[OWNER]** Move the public support contact off personal Gmail
  (`id0399@gmail.com`) to a dedicated alias before App Store submission.
- **[OWNER]** Conscious decision on monetization — "no ads, no fees" is
  locked, but the Cloudflare bill grows with users and there's currently no
  revenue offset. Not urgent; shouldn't happen by default either.

# ClanTab — Ship Plan (post-`v0.2.0`)

`PLAN.md` built the iOS app (Phases 0-7 → `v0.1.0`). `BACKEND_PLAN.md` built and
deployed the Worker (§1-§8 → `v0.2.0`). The app and backend now work end to end
against `https://clantab.nakka-labs.workers.dev`.

**Status (2026-08-31):** Track 2 is largely done — App ID registered, App Store
Connect record created, signing wired, and **build `1.0 (1)` is on App Store
Connect** in the `test-team` internal group. Track 3.0 (CI billing) is resolved
by making the repo public. What's left:
- **On-device validation** (Track 2) — add an internal tester, install via
  TestFlight, run the end-to-end pass against the production Worker, tag
  `v0.4.0`.
- **App Store submission** (Track 2) — real app icon, screenshots, App Privacy
  answers, then submit for review. Not needed for internal TestFlight.
- **Tappable invite links** (Track 1) — sharing works today via the
  6-character join code; a link that opens the app on tap needs a custom
  domain + Universal Links. Optional, add anytime.
- **Operational** (Track 3) — no monitoring yet; `CLOUDFLARE_API_TOKEN` secret
  not set (deploy is manual via `make worker-deploy`); one known edge issue
  (the Cloudflare `1010` block for non-browser clients).

---

## 0. Decisions to lock first

### 0.1 Domain — **done** (`nakka.dev`, already owned)

**A custom domain is required for exactly one thing: tappable invite links
that open the app (Universal Links).** Nothing else needs it.

#### What works today with no domain (`clantab.nakka-labs.workers.dev`)

- The entire API and every app flow — verified end to end against the
  deployed Worker.
- **Shipping to TestFlight and the App Store.** Apple does not care what URL
  the backend uses; a `*.workers.dev` backend is fine for a released app.
- The `clantab://g/:id` custom URL scheme (dev/simulator deep links).
- **Joining a group by 6-character code** (`RFRAHM`, typed into the app's
  "Join with a Code" screen) — this needs no link at all and is fully working.

#### What you can't do without a domain

- **Universal Links.** When a friend taps `https://…/g/ABC123` in
  Messages/Mail, iOS should open the ClanTab app directly. That needs:
  1. a domain you control,
  2. an `apple-app-site-association` (AASA) file served from it over HTTPS,
  3. the app's `applinks:` entitlement naming that domain.
  Apple treats `workers.dev` as shared infrastructure — Associated Domains
  on a `*.workers.dev` host is unreliable at best and not something to ship
  on. So without a real domain, the invite **link** doesn't open the app;
  friends fall back to typing the 6-character code (which works fine).
- A link that looks trustworthy. `clantab.nakka-labs.workers.dev/g/ABC123`
  reads like a dev artifact / phishing link; `clantab.nakka.dev/g/ABC123` doesn't.
- A home for the privacy-policy page and any marketing page (these can also
  live elsewhere, but a domain is the clean answer).

#### One host serves everything

`DESIGN.md` §8 assumes same-origin. Simplest setup: **one host, no further
splitting.** The Worker serves, from `clantab.nakka.dev` (a subdomain of the
already-owned `nakka.dev`, shared across the app portfolio):

| path | |
|---|---|
| `/api/*` | the API (`AppConfig.apiBaseURL = https://clantab.nakka.dev/`) |
| `/g/:groupId` | the invite landing page — this URL *is* the Universal Link |
| `/.well-known/apple-app-site-association` | the AASA file |
| `/` | a minimal marketing/pointer page |

`AppConfig.groupShareURL(groupId:)` already produces `<apiBaseURL>/g/:id`, so
once `apiBaseURL` is the real domain, the share link is automatically the
Universal Link. No app-code change beyond the one URL constant + the
entitlement.

#### Getting it wired up

No purchase needed — `nakka.dev` is already an active Cloudflare zone
(bought for the whole app portfolio, ~$12/yr). Turning `clantab.nakka.dev`
into a live host for this Worker is just:

- Add the `clantab` subdomain as a Worker route / Custom Domain in
  `wrangler.jsonc` (two-line change) + redeploy.
- Add the `applinks:clantab.nakka.dev` Associated Domains entitlement and
  serve the AASA file at `/.well-known/apple-app-site-association`.

**Decision:** wire it up now if tappable invite links matter for launch; or
ship v1 on `workers.dev` with code-only joining and wire the subdomain later
(the app's "Join with a Code" flow already covers this case) — the cost
argument for waiting is gone since the domain itself is a sunk, already-paid
cost either way.

### 0.2 Apple distribution — **done (2026-08-31)**

- ✅ **Bundle ID** `com.clantab.app` registered at developer.apple.com.
  (Associated Domains capability for Track 1 not yet enabled — add when Track 1
  starts.)
- ✅ **App Store Connect record** "ClanTab" created (Team: Indra Dev Nakka,
  Team ID `UK652GNPP7`).
- ✅ **`DEVELOPMENT_TEAM: UK652GNPP7`** + `CODE_SIGN_STYLE: Automatic` in
  `project.yml` (`settings.base`) — the project signs without per-machine
  Xcode setup.
- **TestFlight scope**: internal testing (up to 100, no review) is enough to
  start. Internal group `test-team` created; build `1.0 (1)` uploaded
  2026-08-31. External testing / App Store submission triggers App Review —
  see §2.4.

### 0.3 Environments

Right now there's one Worker (`clantab`) = production, and tests use Miniflare.
Decide whether to add a **`clantab-staging`** Worker (a second `env` in
`wrangler.jsonc`, its own DOs) so the iOS app can point at staging for
pre-release testing without touching real groups. Recommended once there are
real users; skip until then.

### 0.4 `MARKETING_VERSION`

Set to `1.0` (`project.yml`) to match the version record App Store Connect
created for the app. Treat it as the TestFlight/App Store version going
forward, independent of git tags; bump `CURRENT_PROJECT_VERSION` per upload.

---

## Track 1 — Custom domain + Universal Links

**Goal:** `https://clantab.nakka.dev/g/:groupId` links open the app directly (or the
App Store if it's not installed), and the API moves to the same domain.

**This is optional for launch.** Without it, invites work by 6-character code
(the app's "Join with a Code" flow, verified). With it, invites also work by
tappable link. Depends on §0.1 (a domain).

1. **Domain on Cloudflare** — add the zone, confirm DNS is active.
2. **Worker custom domain** — `wrangler.jsonc` `routes` (or a Custom Domain in
   the dashboard): `clantab.nakka.dev/*` → `clantab` Worker. Keep
   `*.workers.dev` too, or disable it.
3. **`AppConfig.apiBaseURL`** → `https://clantab.nakka.dev/` (or serve the API and
   the landing page from the same host — `DESIGN.md` §8 assumes same-origin;
   decide `api.` subdomain vs path-based).
4. **Real `/g/:groupId` page** — replace the stub in `worker/src/index.ts` with a
   proper landing page: app-store badge, "Open in ClanTab" (Universal Link
   self-reference + `clantab://` fallback), still `noindex`, still reveals
   nothing about the group.
5. **`/.well-known/apple-app-site-association`** — served by the Worker (JSON,
   `content-type: application/json`, no redirect):
   ```json
   { "applinks": { "apps": [], "details": [
     { "appID": "<TEAMID>.com.clantab.app", "paths": ["/g/*"] } ] } }
   ```
6. **iOS Associated Domains** — add to `project.yml`:
   `com.apple.developer.associated-domains = ["applinks:clantab.nakka.dev"]`
   (an `.entitlements` file + `CODE_SIGN_ENTITLEMENTS`), and enable the
   capability on the App ID.
7. **`RootView`** already parses `https://<host>/g/:id` (`extractGroupId` +
   `RootViewDeepLinkTests`). Just confirm `.onOpenURL` fires for a Universal
   Link (it does — same callback as the custom scheme).
8. **Verify on a real device** — `clantab://` works in Simulator; Universal
   Links only truly work on a signed device build with the AASA fetched by the
   OS. Add a test target case or a manual checklist entry.
9. **Update** `DESIGN.md` §1/§8, `App/README.md` "Known gaps", `BACKEND_PLAN.md` §6.

**`make worker-deploy` is still yours to run** (the sandbox blocks it for me).

---

## Track 2 — TestFlight / App Store readiness

**Goal:** a build you can put on TestFlight, then submit.

1. ✅ **App icon + accent colour** — real icon installed 2026-09-02
   (`LOGO_BRIEF.md`), replacing the earlier placeholder: same equals-sign
   motif, exact `DESIGN_BIBLE.md` §2 blue (`#0074CA`), no transparency.
   Reverse-image and trademark checks from `LOGO_BRIEF.md` still need
   running before App Store submission (not TestFlight).
2. ✅ **Privacy manifest** — `App/ClanTab/PrivacyInfo.xcprivacy`: no tracking;
   "Name" (the display name) + "Other Data Types" (ledger content) both linked
   / not-for-tracking / App Functionality; `UserDefaults` → `CA92.1`. Judgement
   calls are commented in the file — revisit if App Review pushes back.
3. ✅ **Launch screen** — done 2026-09-02. `UILaunchScreen` dict:
   `LaunchLogo` (white "=" mark) centred on `AccentColor` (the brand blue),
   no text — HIG-compliant, matches the app icon. Deliberately
   theme-independent (a branded launch screen shouldn't flip in dark mode).
   ✅ Accessibility: VoiceOver labels + `.accessibilityElement` on the balance
   hero, member rows, activity rows, and settle-up cards (the green/red colour
   was the only owed-vs-owe cue); balance hero now uses a Dynamic-Type font
   instead of a fixed 40pt.
4. ✅ **App Store metadata** — drafted in `docs/appstore/metadata.md`
   (name, subtitle, description, keywords, the App Privacy answers, and
   **review notes** walking a reviewer through the no-login model). Paste into
   App Store Connect. ✅ **Screenshots** — `docs/appstore/screenshots/`, four
   6.9" frames (Group Home, Insights, Add Expense, Settle Up), 2026-09-02.
5. **Review-risk review** — covered in the metadata's review notes: capability
   link, no accounts, trust-based settlement, no IAP, no analytics/ads. Nothing
   should trip 3.1.1 or 5.1.1. **Guideline 1.2 (user-generated content) is the
   real open risk** for a public listing — see Track 3 §7. Resolve before
   submission, not just before TestFlight.
6. **Deploy CI** — `.github/workflows/worker-deploy.yml` exists: on a `v*` tag,
   `npm ci` → typecheck → test → `wrangler deploy`. **Still needs the
   `CLOUDFLARE_API_TOKEN` repo secret** (Cloudflare → My Profile → API Tokens →
   "Edit Cloudflare Workers" template) before it can actually deploy; until
   then, `make worker-deploy` locally. An Xcode Cloud / fastlane lane for
   TestFlight uploads is optional.
7. ✅ **`MARKETING_VERSION` = `1.0`** (matches the App Store Connect version
   record). Bump `CURRENT_PROJECT_VERSION` per upload.
8. ✅ **Privacy policy** — `docs/privacy-policy.md`, published by
   `.github/workflows/pages.yml`. Pages source set to "GitHub Actions"; **live
   at `https://nakka-labs.github.io/clantab-ios/`** and set as the Privacy
   Policy URL in `docs/appstore/metadata.md`. Paste it into App Store Connect
   with the rest of the listing.
9. ✅ **First TestFlight build** — `1.0 (1)` archived in Xcode and uploaded to
   App Store Connect 2026-08-31; processed; internal group `test-team` created.
   Next: add an internal tester and install via the TestFlight app.

**Still needs you:** add an internal tester + the on-device end-to-end pass,
the reverse-image/trademark checks on the new icon (`LOGO_BRIEF.md`), App
Store screenshots + App Privacy answers (external testing / submission), and
the `CLOUDFLARE_API_TOKEN` repo secret.

---

## Track 3 — Operational hardening (do alongside Track 2, before real users)

0. ✅ **CI cost** — **resolved by making the repo public (2026-08-31).**
   GitHub-hosted runners (Linux *and* macOS) are unmetered for public repos, so
   the earlier "macOS drained the shared free pool, now every workflow fails"
   problem is gone. `test.yml` / `worker.yml` / `worker-deploy.yml` / `pages.yml`
   all run for free. The iOS build stays in the local `pre-push` hook (`make
   hooks` / `make check`) for fast feedback; a macOS CI job is now cost-free to
   add if PR-time checks are wanted. The history scan before going public found
   no secrets in the tree (`CLOUDFLARE_API_TOKEN` is a GitHub Secret).
1. **Observability** — the Worker already has `observability.enabled`. Set up a
   Logpush or a dashboard alert for 5xx rate and DO errors. The
   `cloudflare-observability` MCP can tail logs during incidents.
2. **The `1010` edge block** — decide: (a) leave it (native app is unaffected,
   a web client is out of scope), or (b) lower the zone's Browser Integrity
   Check / Bot Fight Mode for `clantab.nakka.dev` if a web client is ever
   planned. Document the decision.
3. ✅ **Rate-limit review, and the bigger fix underneath it** — done
   2026-09-05. The old Registry limiter was in-memory (reset on DO eviction),
   and `RegistryDO` itself was a **singleton**: every group creation and
   every join-code lookup for the entire app serialized through one Durable
   Object (`DESIGN.md` §3). Moved code→groupId resolution to a `JOIN_CODES`
   Workers KV namespace (write-once on create, read-many on lookup,
   `worker/src/lib/join-codes.ts`) and replaced the in-memory counter with a
   Cloudflare Rate Limiting binding (`RESOLVE_RATE_LIMITER`, 20/min) on
   `GET /api/groups/resolve/*`. `RegistryDO` deleted (`wrangler.jsonc` `v3`
   migration). Tests green (145/145); **not yet deployed** —
   `wrangler deploy` / `make worker-deploy` is still yours to run.
4. **Data durability** — DO SQLite is backed up by Cloudflare, but there's no
   user-facing "export the whole group" beyond the CSV/JSON the app already
   does. Consider a periodic `GET`-and-archive job if any group matters.
5. **Cost** — `DESIGN.md` §9's math says the free tier covers far more than this
   will ever see. Add a billing alert anyway.
6. **`compatibility_date`** — `wrangler.jsonc` pins `2025-09-01`; bump
   deliberately when adopting new runtime behaviour, not drift.
7. **Abuse / content — now a real App Store requirement, not just a
   documented risk.** A capability URL that leaks (posted publicly) exposes
   that group; documented trust model (`DESIGN.md` §8). Beyond the leak
   scenario: group names, member names, and expense descriptions are all
   user-generated and shared between whoever holds the link — Apple's
   Guideline 1.2 requires a report mechanism and a way to block/remove a bad
   actor for any app with shared user-generated content. Not optional once
   this is a public App Store listing (priority bumped 2026-09-04). **[CLI]**
   Scaffold a report-content action + a block/remove-member path (remove
   already exists via Group Settings; report doesn't). **[OWNER]** Approve
   the moderation copy and the EULA's zero-tolerance UGC clause before
   submission.
8. **[CLI] Foreground poll interval** — `GroupViewModel.pollInterval` is 5s;
   drop it to ~20-30s. Same UX for a low-frequency app, and it directly cuts
   the Workers request/row-read bill at scale (cost-modeled 2026-09-04).

---

## Track 4 — WebSocket live updates (later; only if warranted)

**Interim step done:** Group Home now runs a lightweight foreground poll
(`GroupViewModel.autoRefetch()` every `pollInterval`, plus a refresh on app
foreground) so a second device's changes show up on their own — no more
manual pull-to-refresh during a shared session. `DESIGN.md` §7. WebSocket push
below is still the real-time endgame.

`DESIGN.md` §12 defers this until "usage shows people actually have the app open
simultaneously." When that's true:

1. `GroupDO` gains a `fetch` WebSocket-upgrade handler alongside the RPC methods;
   it tracks connected sockets and broadcasts a "state changed" ping after every
   mutation.
2. iOS `GroupViewModel` opens a `URLSessionWebSocketTask` on `.task`, calls
   `refetch()` on each ping, falls back to the current fetch-on-load /
   pull-to-refresh if the socket drops. Still no optimistic UI.
3. Hibernation: use the WebSocket Hibernation API so idle groups don't bill.
4. New tests: a `group.test.ts` case for broadcast-on-mutation.

Not on the critical path. Skip until the data says otherwise.

---

## Suggested order

**Superseded 2026-09-05** — the master sequencing (including how Tracks
1-4 here interleave with `MANDATORY_LOGIN_PLAN.md`, `ACCESS_TOKEN_PLAN.md`,
`NAV_POLISH_PLAN.md`, and `FEATURE_BACKLOG.md`) now lives in
`NEXT_STEPS.md`. This doc stays the detailed reference for Tracks 1-4's
*how*; `NEXT_STEPS.md` owns *when*.

## What needs you

See `NEXT_STEPS.md` — every open item across every plan doc is tagged
**[CLI]** / **[OWNER]** there in one place instead of duplicated per-doc.

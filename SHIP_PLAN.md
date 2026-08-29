# ClanTab — Ship Plan (post-`v0.2.0`)

`PLAN.md` built the iOS app (Phases 0-7 → `v0.1.0`). `BACKEND_PLAN.md` built and
deployed the Worker (§1-§8 → `v0.2.0`). The app and backend now work end to end
against `https://clantab.nakka-labs.workers.dev`.

**What's still missing before anyone else can use it:**
- **App Store / TestFlight presence** (Track 2) — the app has no icon, no
  privacy manifest, and no App Store Connect record, so nobody but you can
  install it. *This* is the real blocker to real users.
- **Tappable invite links** (Track 1) — sharing works today via the
  6-character join code typed into the app; a link that opens the app on tap
  needs a custom domain + Universal Links.
- **Operational** (Track 3) — no monitoring, no deploy automation, one known
  edge issue (the Cloudflare `1010` block for non-browser clients).

The app + backend are functionally complete and deployed. Four tracks below;
**Track 2 is the critical path** (Track 1 is a UX upgrade you can add before or
after launch).

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

### 0.2 Apple distribution — **needs you**

- **Bundle ID**: `com.clantab.app` (already in `project.yml`). Register it at
  developer.apple.com → Identifiers, with the **Associated Domains** capability
  enabled (for Track 1).
- **App Store Connect record**: create the "ClanTab" app (needs the bundle ID).
  A name reservation is worth doing early — "ClanTab" may be taken.
- **`DEVELOPMENT_TEAM`**: add your Team ID to `project.yml` (`settings.base`)
  so the project builds signed without per-machine Xcode fiddling. Or keep it
  out and set it in Xcode's Signing tab each machine — your call.
- **TestFlight scope**: internal testing (up to 100, no review) is enough to
  start. External testing / App Store submission triggers App Review — see §2.4.

### 0.3 Environments

Right now there's one Worker (`clantab`) = production, and tests use Miniflare.
Decide whether to add a **`clantab-staging`** Worker (a second `env` in
`wrangler.jsonc`, its own DOs) so the iOS app can point at staging for
pre-release testing without touching real groups. Recommended once there are
real users; skip until then.

### 0.4 `MARKETING_VERSION`

Bumped to `0.2.0` (`project.yml`). Treat it as the TestFlight/App Store
version going forward, independent of git tags.

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

1. ✅ **App icon + accent colour** — `App/ClanTab/Assets.xcassets` with a
   placeholder `AppIcon` (flat blue, white "=") and a blue `AccentColor`,
   wired via `ASSETCATALOG_COMPILER_*` in `project.yml`. Ships fine on
   TestFlight; **swap for real design before the App Store.**
2. ✅ **Privacy manifest** — `App/ClanTab/PrivacyInfo.xcprivacy`: no tracking;
   "Name" (the display name) + "Other Data Types" (ledger content) both linked
   / not-for-tracking / App Functionality; `UserDefaults` → `CA92.1`. Judgement
   calls are commented in the file — revisit if App Review pushes back.
3. **Launch screen / polish pass** — **not done.** `UILaunchScreen: {}` is
   plain system background (HIG-compliant, no flash, but unbranded); a
   storyboard launch screen with the wordmark is a nice-to-have. Still to do:
   a dark-mode spot check on a device.
   ✅ Accessibility: VoiceOver labels + `.accessibilityElement` on the balance
   hero, member rows, activity rows, and settle-up cards (the green/red colour
   was the only owed-vs-owe cue); balance hero now uses a Dynamic-Type font
   instead of a fixed 40pt.
4. ✅ **App Store metadata** — drafted in `docs/appstore/metadata.md`
   (name, subtitle, description, keywords, the App Privacy answers, and
   **review notes** walking a reviewer through the no-login model). Paste into
   App Store Connect. Screenshots still to reshoot cleanly for the store.
5. **Review-risk review** — covered in the metadata's review notes: capability
   link, no accounts, trust-based settlement, no IAP, no analytics/ads. Nothing
   should trip 3.1.1 or 5.1.1.
6. ✅ **Deploy CI** — `.github/workflows/worker-deploy.yml`: on a `v*` tag,
   `npm ci` → typecheck → test → `wrangler deploy`. **You add the
   `CLOUDFLARE_API_TOKEN` repo secret** (Cloudflare → My Profile → API Tokens →
   "Edit Cloudflare Workers" template). An Xcode Cloud / fastlane lane for
   TestFlight uploads is optional.
7. **Bump `MARKETING_VERSION`** (now `0.2.0`) and `CURRENT_PROJECT_VERSION` per
   build.
8. ✅ **Privacy policy** — written at `docs/privacy-policy.md`. **You host it**
   (GitHub Pages from `/docs` is the quick path) and put the URL in App Store
   Connect + update the metadata file.

**Still needs you:** the Apple App ID + App Store Connect record, a real app
icon (eventually), hosting the privacy policy, App Store screenshots, the
`CLOUDFLARE_API_TOKEN` secret, and the TestFlight upload (Xcode → Archive →
Distribute, or fastlane with an App Store Connect API key).

---

## Track 3 — Operational hardening (do alongside Track 2, before real users)

0. ✅ **CI cost** — the metered macOS `ios-build.yml` is gone; the iOS build +
   `ClanTabTests` moved to a local `pre-push` hook (`make hooks` / `make
   check`, `.githooks/pre-push`). Cloud CI is now Linux-only (`test.yml`,
   `worker.yml`) plus tag-triggered `worker-deploy.yml` — all within the free
   tier. A self-hosted macOS runner could bring PR checks back later, unmetered.
   **Until the account's Actions minutes reset (or a spending limit is set),
   even the Linux workflows fail** — the free pool is shared and macOS drained
   it. `make check` locally is the source of truth meanwhile.
1. **Observability** — the Worker already has `observability.enabled`. Set up a
   Logpush or a dashboard alert for 5xx rate and DO errors. The
   `cloudflare-observability` MCP can tail logs during incidents.
2. **The `1010` edge block** — decide: (a) leave it (native app is unaffected,
   a web client is out of scope), or (b) lower the zone's Browser Integrity
   Check / Bot Fight Mode for `clantab.nakka.dev` if a web client is ever
   planned. Document the decision.
3. **Rate-limit review** — the Registry limiter is in-memory (resets on DO
   eviction). Fine for now; if abuse appears, move the counter to DO storage or
   add a Cloudflare Rate Limiting rule on `/api/groups/resolve/*`.
4. **Data durability** — DO SQLite is backed up by Cloudflare, but there's no
   user-facing "export the whole group" beyond the CSV/JSON the app already
   does. Consider a periodic `GET`-and-archive job if any group matters.
5. **Cost** — `DESIGN.md` §9's math says the free tier covers far more than this
   will ever see. Add a billing alert anyway.
6. **`compatibility_date`** — `wrangler.jsonc` pins `2025-09-01`; bump
   deliberately when adopting new runtime behaviour, not drift.
7. **Abuse / content** — a capability URL that leaks (posted publicly) exposes
   that group. Documented trust model (`DESIGN.md` §8). No action unless it
   becomes a real problem; note it.

---

## Track 4 — WebSocket live updates (later; only if warranted)

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

```
0. Lock decisions (§0) — Apple app record is the long pole; domain is optional

CRITICAL PATH ─────────────────────────────────────────────
├─ Track 2 (icon, privacy manifest, metadata, deploy CI)   needs §0.2
├─ Track 3 (observability, edge, limits)   alongside Track 2, done before
│                                          the first external tester
▼
TestFlight internal → external → App Store submission

OPTIONAL / PARALLEL ───────────────────────────────────────
├─ Track 1 (domain + Universal Links)   needs §0.1 (a domain); can land
│                                       before OR after launch — until then,
│                                       invites are by 6-char code
└─ Track 4 (WebSockets)   post-launch, iff concurrent usage appears
```

You can ship v1 on the `workers.dev` backend with code-only joining, then add
the domain + Universal Links as a fast-follow. Or buy the domain up front and
do both tracks together. Either is fine.

Rough sizing: Track 1 ≈ 1 day of work once the domain exists · Track 2 ≈ 1-2
days plus the icon/metadata/policy content (yours) · Track 3 ≈ half a day ·
Track 4 ≈ 1-2 days when it's time.

## What needs you (nothing else is blocked on me)

| | | required for launch? |
|---|---|---|
| Register the App ID, create the App Store Connect app | Track 2 | **yes** |
| App icon (or a one-line brief) | Track 2 | **yes** |
| Privacy policy page + App Store copy/screenshots | Track 2 | **yes** |
| Run the TestFlight upload (Xcode Archive → Distribute, or fastlane) | Track 2 | **yes** |
| Add `CLOUDFLARE_API_TOKEN` as a GitHub secret (deploy CI) | Track 2.6 | optional |
| **Buy a domain**, put it on Cloudflare | Track 1 | **no** — enables tappable links; add anytime |
| Run `make worker-deploy` when the backend changes | Tracks 1 & 3 | as needed |

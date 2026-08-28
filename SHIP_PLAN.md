# Squarely — Ship Plan (post-`v0.2.0`)

`PLAN.md` built the iOS app (Phases 0-7 → `v0.1.0`). `BACKEND_PLAN.md` built and
deployed the Worker (§1-§8 → `v0.2.0`). The app and backend now work end to end
against `https://squarely.nakka-labs.workers.dev`.

**What's still missing before anyone else can use it:**
- The share link is `squarely.nakka-labs.workers.dev/g/:id` — an ugly URL that
  only opens a stub page, not the app (no Universal Links).
- The app has no icon, no privacy manifest, no App Store / TestFlight presence —
  it can't be installed by anyone but you, from Xcode.
- Production has no monitoring, no deploy automation, and one known edge issue
  (the Cloudflare `1010` browser-integrity block for non-browser clients).

This plan covers getting past all of that. Four tracks; the first two are the
critical path to real users.

---

## 0. Decisions to lock first

### 0.1 Domain — **needs you** (costs money, ~$10/yr)

Universal Links, a shareable link, and a real landing page all need a domain you
control on Cloudflare. Options:

- **Buy `squarely.app`** (or `.com`, `getsquarely.com`, …) via Cloudflare
  Registrar (at-cost) or any registrar + point the nameservers at Cloudflare.
- The Worker gets a custom-domain route; `AppConfig.apiBaseURL` moves to it.

Nothing in Track 1 can start until this exists. Everything else can proceed
without it.

### 0.2 Apple distribution — **needs you**

- **Bundle ID**: `com.squarely.app` (already in `project.yml`). Register it at
  developer.apple.com → Identifiers, with the **Associated Domains** capability
  enabled (for Track 1).
- **App Store Connect record**: create the "Squarely" app (needs the bundle ID).
  A name reservation is worth doing early — "Squarely" may be taken.
- **`DEVELOPMENT_TEAM`**: add your Team ID to `project.yml` (`settings.base`)
  so the project builds signed without per-machine Xcode fiddling. Or keep it
  out and set it in Xcode's Signing tab each machine — your call.
- **TestFlight scope**: internal testing (up to 100, no review) is enough to
  start. External testing / App Store submission triggers App Review — see §2.4.

### 0.3 Environments

Right now there's one Worker (`squarely`) = production, and tests use Miniflare.
Decide whether to add a **`squarely-staging`** Worker (a second `env` in
`wrangler.jsonc`, its own DOs) so the iOS app can point at staging for
pre-release testing without touching real groups. Recommended once there are
real users; skip until then.

### 0.4 `MARKETING_VERSION`

`project.yml` still says `0.1.0`. Bump to `0.2.0` now, and treat it as the
TestFlight/App Store version going forward (independent of git tags).

---

## Track 1 — Custom domain + Universal Links

**Goal:** `https://squarely.app/g/:groupId` links open the app directly (or the
App Store if it's not installed), and the API lives at a real hostname.

Depends on §0.1.

1. **Domain on Cloudflare** — add the zone, confirm DNS is active.
2. **Worker custom domain** — `wrangler.jsonc` `routes` (or a Custom Domain in
   the dashboard): `api.squarely.app/*` → `squarely` Worker. Keep
   `*.workers.dev` too, or disable it.
3. **`AppConfig.apiBaseURL`** → `https://api.squarely.app/` (or serve the API and
   the landing page from the same host — `DESIGN.md` §8 assumes same-origin;
   decide `api.` subdomain vs path-based).
4. **Real `/g/:groupId` page** — replace the stub in `worker/src/index.ts` with a
   proper landing page: app-store badge, "Open in Squarely" (Universal Link
   self-reference + `squarely://` fallback), still `noindex`, still reveals
   nothing about the group.
5. **`/.well-known/apple-app-site-association`** — served by the Worker (JSON,
   `content-type: application/json`, no redirect):
   ```json
   { "applinks": { "apps": [], "details": [
     { "appID": "<TEAMID>.com.squarely.app", "paths": ["/g/*"] } ] } }
   ```
6. **iOS Associated Domains** — add to `project.yml`:
   `com.apple.developer.associated-domains = ["applinks:squarely.app"]`
   (an `.entitlements` file + `CODE_SIGN_ENTITLEMENTS`), and enable the
   capability on the App ID.
7. **`RootView`** already parses `https://<host>/g/:id` (`extractGroupId` +
   `RootViewDeepLinkTests`). Just confirm `.onOpenURL` fires for a Universal
   Link (it does — same callback as the custom scheme).
8. **Verify on a real device** — `squarely://` works in Simulator; Universal
   Links only truly work on a signed device build with the AASA fetched by the
   OS. Add a test target case or a manual checklist entry.
9. **Update** `DESIGN.md` §1/§8, `App/README.md` "Known gaps", `BACKEND_PLAN.md` §6.

**`make worker-deploy` is still yours to run** (the sandbox blocks it for me).

---

## Track 2 — TestFlight / App Store readiness

**Goal:** a build you can put on TestFlight, then submit.

1. **App icon + accent colour** — `Assets.xcassets` with `AppIcon` (1024px
   master, Xcode generates the rest on modern targets) and an `AccentColor`.
   This is design work — a simple wordmark/monogram ("📐" is the current
   stand-in). `project.yml` needs `ASSETCATALOG_COMPILER_APPICON_NAME` /
   `_GLOBAL_ACCENT_COLOR_NAME` (or Xcode defaults once the catalog exists).
2. **Privacy manifest** — `PrivacyInfo.xcprivacy` in the app target. Squarely
   collects only a device-local display name and makes network calls; declare
   `NSPrivacyCollectedDataTypes` accordingly (likely *none* leave the device as
   "linked to identity" — the display name is user-chosen, not an identifier)
   and the required-reason APIs it uses (`UserDefaults` → `CA92.1`). Apple
   rejects builds without this.
3. **Launch screen / polish pass** — `UILaunchScreen: {}` is currently empty;
   a minimal branded launch screen. Dark-mode spot check on a device.
   Accessibility: Dynamic Type, VoiceOver labels on the balance hero and
   activity rows.
4. **App Store metadata** — description, keywords, support URL, privacy policy
   URL (required — even for "no accounts", you need a page stating what the
   capability link means and that settlements are trust-based), screenshots
   (6.7"/6.9" + 6.1"), the "no login / capability URL" model explained for the
   reviewer in the review notes.
5. **Review-risk review** — the capability-link security model, "no accounts",
   and trust-based settlement are all fine but unusual; pre-empt reviewer
   questions in the notes. Confirm nothing trips 3.1.1 (no in-app purchase
   surface) or 5.1.1 (data collection) unexpectedly.
6. **CI**: add a `Deploy Worker` GitHub Action on `v*` tags
   (`CLOUDFLARE_API_TOKEN` secret, `wrangler deploy`), so backend releases are
   reproducible. Optionally an Xcode Cloud / fastlane lane for TestFlight
   uploads.
7. **Bump `MARKETING_VERSION`** and `CURRENT_PROJECT_VERSION` per build.

**Needs you:** the icon (or a brief for it), the Apple app record, the privacy
policy page, App Store screenshots/copy, and the TestFlight upload itself
(Xcode → Archive → Distribute, or fastlane with an App Store Connect API key).

---

## Track 3 — Operational hardening (do alongside Track 2, before real users)

1. **Observability** — the Worker already has `observability.enabled`. Set up a
   Logpush or a dashboard alert for 5xx rate and DO errors. The
   `cloudflare-observability` MCP can tail logs during incidents.
2. **The `1010` edge block** — decide: (a) leave it (native app is unaffected,
   a web client is out of scope), or (b) lower the zone's Browser Integrity
   Check / Bot Fight Mode for `api.squarely.app` if a web client is ever
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
0. Lock decisions (§0) — domain purchase + Apple app record are the long poles
│
├─ Track 1 (domain + Universal Links)      ┐
│    needs §0.1                            ├─ both feed a good first-run
├─ Track 2 (icon, privacy, metadata, CI)   ┘   experience; do in parallel
│    needs §0.2
│
├─ Track 3 (observability, edge, limits)   — alongside Track 2, finish before
│                                             the first external tester
▼
TestFlight internal → external → App Store submission
│
└─ Track 4 (WebSockets) — post-launch, iff concurrent usage appears
```

Rough sizing: Track 1 ≈ 1 day of work once the domain exists · Track 2 ≈ 1-2
days plus the icon/metadata/policy content (yours) · Track 3 ≈ half a day ·
Track 4 ≈ 1-2 days when it's time.

## What needs you (nothing else is blocked on me)

| | |
|---|---|
| **Buy a domain**, put it on Cloudflare | Track 1 |
| Register the App ID (+ Associated Domains capability), create the App Store Connect app | Track 1 & 2 |
| App icon (or a one-line brief) | Track 2 |
| Privacy policy page + App Store copy/screenshots | Track 2 |
| Run `make worker-deploy` and the TestFlight upload | Track 1 & 2 |
| Add `CLOUDFLARE_API_TOKEN` as a GitHub secret (for deploy CI) | Track 2.6 |

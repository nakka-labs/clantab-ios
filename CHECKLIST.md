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

- [x] **Deploy the worker.** Done 2026-09-08. `wrangler whoami` confirmed
      an OAuth token for `id0399@gmail.com` (account
      `a4c993ce08b752dc5e16eac386ae954e`) with `workers (write)` scope, so
      CLI ran `make worker-deploy` — uploaded `clantab` (version
      `0c392b79-c507-42a0-b6ce-01f158e20ebf`) to
      `https://clantab.nakka-labs.workers.dev` with all bindings intact
      (GROUP_DO / USER_DO / REPORTS_DO, JOIN_CODES KV, RESOLVE_RATE_LIMITER,
      APPLE/GOOGLE_AUDIENCE vars; production secrets untouched — this was a
      redeploy over the 2026-09-04 initial cutover). Verified live, not just
      exit 0: CLI created a scratch group over HTTPS
      (`POST /api/groups`), then `GET /api/groups/:groupId?token=…` returned
      `200` with the real state body, the tokenless call `403 FORBIDDEN`,
      and an unknown id `404 GROUP_NOT_FOUND`.
- [x] **Enable real push delivery.** Done 2026-09-09. Owner enabled the
      Push Notifications capability on the `com.clantab.app` App ID and
      generated an APNs Auth Key (Key ID `77K24W288H`, Team ID
      `UK652GNPP7` — same team as the `SIWA_*` secrets). CLI set the four
      Worker secrets via `wrangler secret put`: `APNS_KEY_ID`,
      `APNS_TEAM_ID`, `APNS_PRIVATE_KEY` (the `.p8` PKCS#8 PEM piped from
      file), `APNS_TOPIC` = `com.clantab.app`. `APNS_ENVIRONMENT` left
      unset → `apnsConfigFromEnv` defaults to the production APNs host,
      correct for TestFlight/App Store builds (a local Xcode build's
      sandbox token would need `APNS_ENVIRONMENT=sandbox` temporarily).
      Each `secret put` redeployed the Worker, so `notifyGroup` now
      dispatches for real instead of no-op returning on a null config.
      Verified the provider auth live, not just exit 0: a hand-minted
      ES256 JWT (same construction as `lib/apns.ts`) + a deliberately
      bogus device token returned `400 BadDeviceToken` from **both**
      `api.push.apple.com` and `api.sandbox.push.apple.com` — proving the
      key/team/topic and JWT signature are all accepted and the key is
      authorized for APNs (a bad key or a capability still disabled on the
      App ID would be `403 InvalidProviderToken`). Real on-device delivery
      is covered by the "TestFlight on-device end-to-end pass" below.
- [x] **CloudKit backup, tier 2.** Done 2026-09-08, verified on device
      2026-09-09 (`DESIGN.md` §7/§8).
      1. Owner: CloudKit capability enabled on the `com.clantab.app` App ID,
         `iCloud.com.clantab.app` container created + assigned (Apple
         Developer portal, 2026-09-09).
      2. CLI: `CKRecord` snapshot of the export payload, written on a
         self-throttling cadence.
      3. CLI: backup destination only — `GroupDO` stays authoritative.
      4. CLI: snapshot logic unit-tested; verified on a real device — a
         `GroupBackup` record lands in the CloudKit Dashboard.
      Pure layer in `ClanTabKit/Export/CloudBackup.swift`:
      `CloudBackupSnapshot` (the `Export.json` shape +
      `groupId`/`capturedAt`/`schemaVersion`), deterministic `encode`, an
      FNV-1a `checksum` (non-crypto, kept dependency-free for Linux CI), a
      `CloudBackupSchedule.shouldBackUp` gate shaped exactly like
      `BackupNudge.shouldShow` — writes only when the payload checksum
      changed (≥ 10 min since last) or a day has passed — and a
      `UserDefaults`-backed `CloudBackupStateStore` (last timestamp +
      checksum, per group). App layer `App/ClanTab/CloudKitBackup.swift`:
      `CloudKitGroupBackup` (behind a `GroupBackupWriting` protocol,
      `NoOpGroupBackup` the default so tests never touch CloudKit) writes one
      `GroupBackup` record per group (`recordName` = `group-<id>`, `.allKeys`
      overwrite, the JSON blob as a `CKAsset`) to `privateCloudDatabase`,
      fire-and-forget from `GroupViewModel.updateCaches` — gated by the same
      `myIdentity` guard, so only claimed groups. Every failure path
      swallowed (`accountStatus != .available`, offline, any `CKError`);
      nothing reads a record back. Tests: `CloudBackupTests` (10, kit) +
      `CloudKitBackupTests` (2, app — `makeRecord` field mapping + no-op
      inertness). `make check` green (kit 200 · app 99).
      On-device verification (2026-09-09): a real iPhone signed into iCloud
      + Sign in with Apple, group "Goa trip" (`group-xZNcdQBW6VTU1wuz`) with
      2 expenses — Xcode console logged `CloudKit backup ok`, and the
      `GroupBackup` record's `payload` asset downloaded from the Dashboard
      decoded to the complete, correct ledger (`schemaVersion 1`, INR,
      integer minor units, both expenses with splits, ISO 8601 dates —
      byte-identical conventions to `Export.json`).
      Schema deployed to Production 2026-09-09 (`GroupBackup` + auto-indexes
      + default role entries; app is `privateCloudDatabase`-only so the role
      changes are inert) — confirmed present in the Production environment,
      so TestFlight/release builds can write too. Actual write-on-a-release-
      build verification is folded into the TestFlight pass below.
- [x] **Approve moderation copy + enable admin reports.** Done 2026-09-09,
      owner-approved with strengthening edits. Guideline 1.2's literal
      requirement is "act on objectionable content reports within 24 hours"
      and the copy committed to no timeframe, so before approval: the
      privacy policy's + website's UGC section now says "reviewed within 24
      hours", the review notes (`docs/appstore/metadata.md`) spell out the
      24-hour review + the EULA zero-tolerance policy + the published
      support contact, and the Terms of Service "Your content" clause
      (`clantab-website/terms.html`) gained an explicit "We have zero
      tolerance for objectionable content and abusive users" sentence plus
      the 24-hour review commitment. Privacy-policy "Last updated" bumped to
      2026-09-09 in both repos. In-app strings (`ReportContentView`,
      `GroupSettingsView` footer) left as-is — accurate and sufficient.
      `ADMIN_TOKEN`: CLI generated `openssl rand -base64 32`, set via
      `wrangler secret put ADMIN_TOKEN` (redeployed the Worker), value handed
      to the owner for their password manager. Verified live against
      production: `GET /api/admin/reports` with no auth → `401`, a wrong
      bearer → `401`, the real token → `200` with the report log JSON (one
      pre-existing 2026-09-05 smoke-test report). Was `404` before the
      secret existed, as designed ("safe until configured").
- [x] **Custom domain + Universal Links.** Done 2026-09-09, verified on a
      real device — tapping a `https://clantab.nakka.dev/g/…` link (from
      Messages) opens the app straight to the group / claim screen, not
      Safari. Invite links use `clantab.nakka.dev/g/:groupId?token=…` — same
      host as the marketing site, `/g/*` routed to the Worker, AASA on Pages
      scoped to `/g/*` so the marketing pages stay web.
      **Done (CLI):**
      - AASA live at `https://clantab.nakka.dev/.well-known/apple-app-site-association`
        (`nakka-labs/clantab-website@9aeaac4`) — verified `200`,
        `content-type: application/json`, no redirect; app ID
        `UK652GNPP7.com.clantab.app`, `components: [{ "/": "/g/*" }]`. Root
        copy + a `_redirects` 200-rewrite as a Workers-Static-Assets
        belt-and-suspenders.
      - Worker: `GET /.well-known/apple-app-site-association` route (same
        JSON, for the workers.dev host); `/g/:groupId` now carries `?token=`
        through to its `clantab://` fallback button. Typechecked, 66 route
        tests green.
      - App: `com.apple.developer.associated-domains: [applinks:clantab.nakka.dev]`
        in `project.yml`; `AppConfig.shareLinkBaseURL` (`clantab.nakka.dev`,
        decoupled from `apiBaseURL`); `SceneDelegate` rewritten to funnel
        every URL — cold + warm, `clantab://` + Universal Link — through the
        new `IncomingURL` helper (a custom `UISceneDelegate` suppresses
        SwiftUI's `.onOpenURL`). App tests green (`RootViewDeepLinkTests` 17,
        `IncomingURLTests` 4); `clantab://` receive path smoke-tested in the
        Simulator, no crash.
      **Done (owner, 2026-09-09):**
      - Worker deployed with the AASA route + token pass-through — verified
        live on `workers.dev`.
      - Cloudflare Worker Route `clantab.nakka.dev/g/*` → the `clantab`
        Worker added (zone `nakka.dev`). It *does* coexist with the
        website's Custom Domain. Verified scoped: `/g/*` → Worker's
        "Open in ClanTab" page; `/`, `/privacy`, `/support`, `/terms`,
        `/style.css`, `/screenshots/*`, `/.well-known/apple-app-site-association`
        all still served by Pages; `/gg` / `/generic` don't over-match.
        (Cosmetic: a bare `/g/` with no id returns the Worker's JSON 404
        rather than a friendly page — unreachable via any real link.)
      - Associated Domains capability enabled on the `com.clantab.app` App ID.
      - On-device test passed: a `clantab.nakka.dev/g/…` link tapped from
        Messages opened the app (build carrying the `applinks` entitlement,
        commit `01d7e26`).
- [x] **Trademark + reverse-image checks.** Done 2026-09-08, owner-run.
      Wordmark: "ClanTab" through USPTO's trademark search
      (`tmsearch.uspto.gov` — TESS was retired), Basic Search plus an
      Advanced/Expert-mode pass scoped to classes 9/36/42 — no close
      matches, live or dead. Icon: `icon-1024.png` through both Google
      Lens and TinEye — no close matches either. Clear on both fronts.
- [x] **Update App Store Connect support-contact field.** Done 2026-09-09.
      Modern App Store Connect has no standalone support-email field on the
      app page — only Support URL / Marketing URL / Privacy Policy URL.
      Owner set **Support URL** to `https://clantab.nakka.dev/support`,
      which carries `indra@nakka.dev` prominently (support `mailto:`, the
      deletion-request `mailto:`, and the footer) — satisfies Guideline
      1.2's "published contact information". Privacy Policy URL →
      `https://clantab.nakka.dev/privacy` (see the metadata items above).
      The reviewer-only contact in **App Review Information** is filled at
      submission time, not here.
- [x] **Rewrite privacy policy + App Privacy answers.** Done 2026-09-08,
      owner-approved. `docs/privacy-policy.md` rewritten end to end for
      mandatory Apple/Google sign-in: what each provider returns (Apple —
      no name/email requested; Google — token carries an email that the
      backend never reads, stores, or logs, only the opaque `sub`), what
      the backend keeps per identity (opaque id, first-sign-in date, Apple
      refresh token for revocation, a groups→member index, APNs tokens),
      in-app account deletion, and the live report/remove UGC-moderation
      path. `docs/appstore/metadata.md`'s "App Privacy" questionnaire table
      reworked to match — added Identifiers → User ID and Identifiers →
      Device ID (both linked · not tracking · App Functionality), documented
      the Google-email "not collected" call with its fallback answer — and
      `App/ClanTab/PrivacyInfo.xcprivacy` synced to the same
      (`NSPrivacyCollectedDataTypeUserID` + `…DeviceID` added, stale "no
      accounts" comment replaced).
      Hosting update 2026-09-09: the canonical Privacy + Support pages moved
      to `clantab.nakka.dev` (`/privacy`, `/support`) — its own repo,
      `nakka-labs/clantab-website`, on Cloudflare Pages, live and verified
      (direct `200`, no redirect). `docs/appstore/metadata.md`'s Privacy
      Policy URL + Support URL updated to match; `docs/privacy-policy.md` and
      `docs/support.html` stay the upstream source (the website pages are a
      hand-port), and `pages.yml`'s `nakka-labs.github.io/clantab-ios/`
      publish stays as a secondary auto-mirror.
- [x] **Rewrite App Store review notes.** Done 2026-09-08, owner-approved.
      `docs/appstore/metadata.md`'s review-notes block rewritten for the
      mandatory-login flow — Sign in with Apple covers the reviewer path
      (their own Apple ID, no demo account, a fresh account reaches 100% of
      the app), a sign-in-first TO TEST walkthrough, and explicit
      Guideline 1.2 (report/remove) and 5.1.1(v) (Delete Account) sections.
      Same pass also fixed the file's stale pre-login marketing copy:
      subtitle ("Split expenses, settle up fast"), the description's
      sign-in section, the promo text, and a reasoned re-confirmation that
      4+ still holds given the UGC is confined to private invite-only
      groups with report+remove moderation.
- [ ] **Decide the monetization stance.** `Owner` — no CLI budget
      1. Owner: pick free / freemium / one-time (cost model already done,
         ~$5-55/mo across 100-1M users).
- [x] **Add the `CLOUDFLARE_API_TOKEN` GitHub secret.** Done 2026-09-08.
      Owner generated a Cloudflare API token ("Edit Cloudflare Workers"
      template, scoped to the one account
      `a4c993ce08b752dc5e16eac386ae954e`) and handed it over; CLI set it via
      `gh secret set CLOUDFLARE_API_TOKEN` on `nakka-labs/clantab-ios`.
      Verified the token authenticates (`wrangler whoami` → the right
      account, single-account so CI needs no `CLOUDFLARE_ACCOUNT_ID`) and
      that `wrangler deploy --dry-run` bundles cleanly with it. The
      `worker-deploy.yml` workflow (tag `v*` / manual dispatch) can now
      deploy.
- [ ] **TestFlight on-device end-to-end pass.** `~10k tokens` (CLI build
      help) + `Owner` device time
      1. [x] Owner: CloudKit schema deployed to Production 2026-09-09
         (Dashboard → Deploy Schema Changes → Deploy to Production) — a
         clean additive deploy: `GroupBackup` record type + its auto-
         generated indexes + the default `_world`/`_icloud`/`_creator` role
         entries for the new type (harmless — the app writes only to
         `privateCloudDatabase`). `GroupBackup` confirmed present in the
         Production environment.
      2. [x] CLI: archive + export + **upload done 2026-09-09**. Build
         number bumped to `7` (App Store Connect already had a `6` from an
         earlier upload — `altool --validate-app` caught it, `5` was
         rejected). `xcodebuild archive` + `-exportArchive`
         (`app-store-connect` `ExportOptions.plist`,
         `-allowProvisioningUpdates`) → `ClanTab.ipa` `1.0 (7)`, signed
         `Apple Distribution: Indra Dev Nakka (UK652GNPP7)` (cloud-managed),
         profile "iOS Team Store Provisioning Profile: com.clantab.app",
         `aps-environment: production`, `associated-domains: *`,
         `beta-reports-active: true`, widget embedded.
         `xcrun altool --validate-app` → VERIFY SUCCEEDED (no errors);
         `--upload-app` → UPLOAD SUCCEEDED (Delivery UUID
         `05c21652-dfaf-433a-8db5-c78d97730101`), using an ASC API key
         (`58887ALLXT`, App Manager) at
         `~/.appstoreconnect/private_keys/`. Now processing in App Store
         Connect; will appear under TestFlight in ~10–30 min. Archive also
         in `~/Library/Developer/Xcode/Archives/2026-09-09/`.
      3. [x] CLI: TestFlight configured 2026-09-09. Build 7 is
         `processingState VALID`, `usesNonExemptEncryption false` (export
         compliance auto-answered), and already `IN_BETA_TESTING` in the
         internal group **"test-team"** (`id0399@gmail.com`, builds 3–7) —
         installable now from the TestFlight app. Set the "What to Test"
         (`betaBuildLocalization` en-US) + the beta app localization
         (feedback email `indra@nakka.dev`, privacy URL). Full pass
         checklist: `docs/appstore/testflight-pass.md`.
      4. Owner: run the pass on a real device — Sign in with Apple/Google,
         a push (CLI triggers it via an API expense-add), a recurring-
         reminder delivery, a shared `clantab.nakka.dev/g/…` link opening
         the app, Report a Problem, Delete Account, and a `GroupBackup`
         record in the CloudKit Dashboard's *Production* environment.
      5. Owner: tag the version once it passes.
- [ ] **Submit for App Store review.** `Owner` — no CLI budget
      1. Owner: submit only after every item above **and** every item
         under "Design & UX polish" below.

### Group dashboard, switching fix & backend read efficiency — locked 2026-09-09

> Scope locked 2026-09-09 after a brainstorm (group-switching bug report
> → dashboard-first launch screen → backend cost/architecture review).
> Full reasoning lives in `DESIGN.md` §7 (client state/dashboard design),
> §8 (the `accessToken` storage finding), §9 (row-read cost model), and
> §12 (the server-side-caching idea considered and rejected). Read those
> before touching this section — this list is *what*, not *why*; update
> `DESIGN.md` first if the *why* changes, then this list.

- [x] **Fix: group switching doesn't actually switch.** Done 2026-09-09.
      Root cause, not a UI issue: `RootView`'s `.group(groupId)` case
      renders `GroupHomeView`, which seeds `@State var viewModel` from
      `groupId` only in `init`. SwiftUI treats `.group("A")` →
      `.group("B")` as the same view identity (same case, same switch
      position), so `init` never re-runs and `viewModel` stays pinned to
      the first group opened. Fix applied: `.id(route)` on the whole
      `content` subtree in `RootView.body` (`AppRoute` made `Hashable`)
      so SwiftUI tears down and rebuilds every `@State` (`viewModel`
      included) whenever the route's associated values change — the
      switcher sheet's `onSwitchGroup` → `enterGroup` → `route = .group(…)`
      path now actually re-seeds. (First landed as a narrower
      `.id(groupId)` on just the `.group` branch; widened to `.id(route)`
      by the same-view-identity audit below, which found `.claimMember`
      had the same bug.) `make check` green (kit + worker + iOS build +
      `ClanTabTests`). Purely a view-tree identity change; the actual
      multi-group switch is exercised by the "TestFlight on-device
      end-to-end pass".
- [x] **Audit: same view-identity footgun, anywhere else in the app.**
      Done 2026-09-09. Swept every `_x = State(initialValue:)` in `App/`
      and every `.sheet` / `.fullScreenCover` presentation.
      **Found one more, same class:** `RootView`'s `.claimMember(groupId:,
      accessToken:)` case — a second deep link / tapped push for a
      *different* group while already on the claim screen goes
      `.claimMember("A")` → `.claimMember("B")`, same `switch` case = same
      identity, so `ClaimMemberView`'s `.task`-loaded `@State members`
      (and `newMemberName`, `pendingConfirmation`) stay pinned to group A
      while `groupId` updates to B underneath.
      **Systemic fix:** `AppRoute` made `Hashable` and `.id(route)` put on
      the whole `content` subtree in `RootView.body` — every route case
      now rebuilds when its associated values change, so the previous
      per-case `.id(groupId)` (from the item above) was removed as
      redundant. `.start` / `.createGroup` / `.joinGroup` carry no
      associated values so they were never at risk.
      **Cleared, with reasoning (not eyeballed):** every other param-
      seeded view is presented via `.sheet(isPresented:)` (the view is
      destroyed on dismiss → fresh `init` each presentation; a background
      poll mutating members/state mid-sheet is deliberately *not*
      re-seeded, so it can't clobber a half-filled form) or `.sheet(item:)`
      (`editingExpense`, `duplicatingExpense`, `loggingTemplate` — SwiftUI
      rebinds on `item.id` change). `GroupSettingsView`, `AddExpenseView`,
      `NewRecurringReminderView`, `ReportContentView` all fall into one of
      those two buckets. `make check` green.
- [x] **Dashboard becomes the launch screen.** Done 2026-09-09.
      Deleted `RootView.resolveInitialRoute()` and its call in `body`'s
      launch `.task` — it auto-skipped into the device's one group when
      exactly one was known. `route` defaults to `.start` and nothing
      else auto-routes on launch, so a returning user always lands on
      `StartView` (the signed-in "your groups" list). Deep links, push
      taps and the Home Screen quick action still route on their own,
      unchanged. Stale rationale comments in `GroupHomeView` (the "Your
      Groups" toolbar button + `onCreateNewGroup`, both still needed as
      the screen's way back out) refreshed. `make check` green.
- [x] **Settings: launch-screen preference (Dashboard vs. a chosen
      group).** Done 2026-09-09. New `@AppStorage("clantab.launchGroupId")`
      (`""` = dashboard, else a groupId), shared by `SettingsView` and
      `RootView`. `SettingsView` gained an "Open at Launch" `Picker` in
      the existing "App" section next to the Appearance picker —
      "Dashboard" + one row per known group (emoji + name, most-recently-
      opened first, `"Group"` fallback for an unnamed one), shown only
      when signed in with ≥1 group. `RootView.launchRoute(preferredGroupId:
      isSignedIn:isKnownGroup:)` — pure, tested — resolves the pin on
      launch in `body`'s `.task`; a pin to a group that's no longer in
      `knownGroups` (left it, or a different account signed in) falls back
      to the dashboard and clears itself. Deep links / push taps / the
      quick action still run after and override. Tests:
      `RootViewDeepLinkTests` +4 (`launchRoute`), new `SettingsViewTests`
      x3 (`launchLabel`). `make check` green.
- [x] **Currency-bucketed totals header on the dashboard.** Done
      2026-09-09. New `DashboardTotals.compute([KnownGroup])` in
      ClanTabKit (`Logic/`) sums each group's cached `myBalances` by
      currency — one `CurrencyTotal` per currency, never blended (no FX),
      zero-net buckets dropped, `nil`/unloaded groups skipped, first-
      appearance currency order (matching `Balances`). New
      `DashboardTotalsHeader` component renders it above `StartView`'s
      `GroupsListView` (inside the signed-in `ScrollView`, in a `VStack`):
      a "YOUR BALANCE" caption + one coloured line per currency ("You owe
      ₹500" red / "You're owed $20" green), nothing at all when every
      bucket nets to zero. Tests: `DashboardTotalsTests` (7, kit) +
      `DashboardTotalsHeaderTests` (5, app — the `line(for:)` wording +
      three-grouping). `make check` green. Visual check folds into the
      TestFlight on-device pass (needs ≥2 groups with cached balances).
- [x] **Repoint Group Home's "Your Groups" button; delete the dead
      switcher sheet.** Done 2026-09-09. `GroupHomeView`'s two callbacks
      `onSwitchGroup` + `onCreateNewGroup` collapsed into one
      `onOpenGroupsHub` (`RootView` wires it to `route = .start`); the
      toolbar "Your Groups" button now calls that. Deleted the
      `isPresentingGroupSwitcher` `@State`, its whole sheet (a
      `Create a Group` button + a `GroupsListView` of `otherKnownGroups`
      — a duplicate of what `StartView` already shows, now with the
      cross-group totals header too), and the `otherKnownGroups`
      computed var. `make check` green.
- [x] **Worker: push payload carries the recipient's own updated
      balance.** Done 2026-09-09. `notifyGroup` gained a
      `recipientBalance: { currency, balances }` option (the mutation's
      currency + the `state.balances` array the route handler already read
      from `getState()`); per recipient it folds
      `{ balanceCurrency, balanceNetMinor }` into `payload.data` —
      *that member's* own net in that currency, `"0"` when they hold no
      nonzero balance in it (`data` values must be strings). Wired at both
      `index.ts` call sites (add-expense, add-settlement). `GroupDO`'s
      `claimedIdentitiesExcluding` → `claimedRecipientsExcluding`,
      returning `{ sub, memberId }[]` so the fan-out (the one DO call that
      already happens) knows which member each recipient is — claiming is
      1:1 identity↔member per group. No new DO round-trips. Keys are
      `balanceCurrency`/`balanceNetMinor` (flatter + unambiguous vs. the
      note's shorthand `{groupId, currency, netMinor}`; `groupId` is
      already in `data`). Tests: `notify.test.ts` +2, `group.test.ts`
      `claimedRecipientsExcluding` rewritten. worker 213 green. `DESIGN.md`
      §7 note updated.
- [x] **iOS: push handler writes the carried balance into the local
      cache.** Done 2026-09-09. `AppDelegate.applyCarriedBalance(from:)`
      reads `balanceCurrency`/`balanceNetMinor` from a push's `userInfo`
      and folds it into the group's cached `myBalances` via
      `Balances.applyingCarriedBalance` (new ClanTabKit helper — updates
      just that currency's bucket, drops it at zero, leaves a
      multi-currency member's other buckets intact) →
      `KnownGroupsStore.updateBalances`. Called from **all three** push
      paths: `willPresent` (foreground), `didReceive` (tap), and a new
      `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`
      (background/suspended wake). The worker now sends a combined
      alert + `content-available` payload (`lib/apns.ts`) so iOS actually
      wakes the app for the last one. `AppDelegate` gets the store from
      `ClanTabApp` (`nonisolated(unsafe)`, set once at startup; the store
      is `Sendable` + lock-guarded).
      **Owner note:** `UIBackgroundModes: [remote-notification]` added to
      `project.yml` → it's an **Info.plist key only**, no Apple Developer
      portal capability beyond the `aps-environment` entitlement already
      there — nothing for the owner to click; it just needs to ride the
      next TestFlight build. Background push is best-effort (iOS throttles
      it) — the guaranteed path is the next item's fallback sync.
      Tests: `BalancesTests` +4 (kit), new `AppDelegateTests` x6 (app),
      `apns.test.ts` body assertion updated. `make check` green (worker
      213 · kit · app).
- [x] **Dashboard fallback sync for missed/denied push.** Done
      2026-09-09. New `GET /api/auth/groups/balances` (Bearer) —
      `GroupDO.myBalances(sub, memberId)` (same stale-membership guard as
      `peerSettlements`) fanned out concurrently over `listGroups()`,
      returning `{ groups: [{ groupId, balances: [Balance] }] }` (the
      caller's own nonzero balances per group). Kit: `GroupBalancesResponse`
      wire type + `ClanTabClient.groupBalances(token:)`. App:
      `AuthViewModel.reconcileGroupBalances(force:)` folds each group's
      balances into `knownGroups.updateBalances`, gated by pure
      `DashboardReconcile.shouldReconcile` (6h staleness) +
      `UserDefaultsDashboardSyncStore` timestamp — called `force:false`
      from `RootView`'s launch `.task`, `force:true` from `StartView`'s
      new `.refreshable` pull-to-refresh. `INVALID_SESSION` signs out;
      any other failure is silent and doesn't advance the timestamp.
      Tests: `DashboardReconcileTests` + `DashboardSyncStoreTests` (6, kit),
      `AuthViewModelTests` +4 (app), `auth-routes.test.ts` +3 (worker).
      `make check` green (worker 216 · kit 220 · iOS build). `DESIGN.md`
      §7/§13 updated.
- [x] **Worker: parallelize the `handleAuthPeople` fan-out loop.** Done
      2026-09-09. The per-group `peerSettlements` reads (independent calls
      to different `GroupDO`s) now go out concurrently via `Promise.all`
      into a `views` array; the aggregation pass over the resolved views
      stays sequential and, since `Promise.all` preserves order, still
      sees groups newest-first (the `displayName` "first name wins" rule
      depends on it). Behaviour byte-identical — `auth-routes.test.ts`'s
      multi-group netting test unchanged and green (worker 213).
- [x] **Security: move `KnownGroup.accessToken` into the Keychain.**
      Done 2026-09-09. New `GroupAccessTokenStoring` +
      `KeychainGroupAccessTokenStore` in ClanTabKit — one
      `kSecClassGenericPassword` item holding a `[groupId: token]` JSON
      map, `kSecAttrAccessibleAfterFirstUnlock`, same
      `#if canImport(Security)` split and construction as
      `KeychainSessionStore`. `KnownGroup.CodingKeys` now omits
      `accessToken` (kept as a transient property); `KnownGroup` alone
      never carries it to disk. `UserDefaultsKnownGroupsStore` takes an
      injected token store (defaults to the Keychain one), writes the
      token through on `remember`, deletes on `forget`, merges it back on
      `all()`, and runs a one-time `init` migration lifting any token
      still inline in a pre-existing blob into the Keychain + rewriting
      the blob clean. `InMemoryKnownGroupsStore` unchanged (in-memory —
      not a disk-secret concern). No App-target changes — the default
      store construction picks up the Keychain backing.
      Tests: `KnownGroupsStoreTests` +3 (kept-out-of-blob, forget-drops-
      token, legacy-migration) with an injected `InMemoryGroupAccessToken`
      store so tests never touch the real Keychain (as `SessionStoreTests`
      does). `make check` green (kit 217 · worker · iOS build). `DESIGN.md`
      §8 gap marked fixed.

**Parked out of this pass, deliberately:** cross-group spend graphs on
the dashboard — needs a new backend aggregate endpoint nothing today
provides, sized against real usage telemetry that doesn't exist yet.
Revisit only after the items above have shipped and produced real
groups-per-user / expenses-per-group numbers, not on a timer. See
`DESIGN.md` §12.


### Design & UX polish — must land before "looks finished"

From a screenshot review + persona walkthrough (trip, household, couple,
one-off/casual, large-friend-group):

- [x] **Member identity color/avatar.** Done 2026-09-07. `MemberColor`
      (`oklch(50% 0.17 H)`, djb2 hue) + shared `OKLCH` primitive extracted
      from `CategoryColor`; `MemberAvatar` (white initials, WCAG-AA on every
      hue) wired into Group Home, activity feed (settlement rows), Add
      Expense split rows, Settle Up, Group Settings, Claim Member, and
      Insights "By member" (rows + per-member bar tint). Menu pickers left
      as plain text — SwiftUI won't render a custom icon there. Verified in
      the Simulator, light + dark.
- [x] **Insights donut chart, spend by member.** Done 2026-09-07.
      `SectorMark` donut in `InsightsView`'s "By member" section, each slice
      in that member's `MemberColor` (matching the row avatar + bar tint);
      the rows are the legend, chart legend hidden. Shown only with 2+
      spending members — one slice is just a filled ring. Verified in the
      Simulator with 1, 2, and 7 members.
- [x] **Group visual identity.** Done 2026-09-07. A per-group **emoji**
      (chose emoji over a formula colour — orthogonal to the member/
      category colour systems; the later per-group-accent item can layer a
      colour on top). Stored as a nullable `group_meta.emoji` key (a new
      key, not a `SCHEMA_VERSION` bump — same as `access_token`), set via
      `PATCH /api/groups/:id` with the `null`-clears tri-state; on
      `GroupSummary` + `KnownGroup`. Preset-chip picker in Group Settings
      (no free text = nothing to validate), shown before the name in the
      groups list and prefixed on the Group Home nav title. Verified in the
      Simulator (pick → save → header + list update). worker 209 · kit
      171 · app 80.
- [x] **Shareable settle-up / recap card.** Done 2026-09-07. `RecapCard`
      — a 4:5 card on `DESIGN_BIBLE.md` §3's one sanctioned brand gradient,
      with two modes (`.settleUp` = the simplified plan, `.recap` = total
      spent + per-member with `MemberColor` bars), the group emoji + name
      in the header. `ImageRenderer` → `Image` (client-side only, no
      worker), handed to a `ShareLink` in both the Settle Up and Insights
      toolbars, re-rendered on plan/currency change. Verified in the
      Simulator: both card designs + the share sheet showing the rendered
      image. kit 171 · app 80.
- [x] **Currency display — drop trailing `.00`.** Done 2026-09-07.
      `MoneyFormat.string` drops the fraction digits when
      `isRoundAmount` (`minorUnits % 100 == 0`) — "₹1,200", not "₹1,200.00";
      a non-round amount still shows both places. Applies everywhere money
      is rendered (app + widget + recap card); `plainString` (edit fields,
      CSV/JSON export) is untouched. Tests: `isRoundAmount`, a
      locale-independent digit-count check, and Darwin-only exact strings.
      kit 174 · app 80.
- [x] **Add Expense submit button contrast.** Done 2026-09-07. The submit
      button is now a full-width `.borderedProminent` / `.controlSize(.large)`
      button — a solid accent-blue fill with white bold text when enabled,
      dropping to a muted grey pill while a required field is empty.
      Verified in the Simulator (both states). app 80. (`CreateGroupView`'s
      submit has the same weak pattern — left for the "primary buttons"
      polish item.)
- [x] **Category picker icon weight.** Done 2026-09-07. The category
      glyphs render at `.semibold` now — `CategoryIconBadge` (the pastel
      badge, used in the picker list + activity feed) and the custom-icon
      grid in `CategoryPickerView` — so their small outline strokes carry
      the same visual weight as the app's chrome symbols. Verified in the
      Simulator. app 80.
- [x] **Root screen / "Your Groups" sheet layout.** Done 2026-09-07.
      `StartView` reworked — no more centered title with the buttons shoved
      to the bottom by a `Spacer`. Signed out: a centered welcome unit
      (tinted "=" mark + wordmark + tagline + the two sign-in buttons).
      Signed in: a standard nav-bar large "ClanTab" title with the groups
      list from the top, or a centered "No groups yet" get-started message;
      Create / Join dock full-width to the bottom safe area with a `.bar`
      backing. Verified all three states in the Simulator. app 80.
- [x] **Settings sheet chrome check.** Done 2026-09-07. The status bar
      itself is fine — `.preferredColorScheme` from the root propagates to
      the Settings sheet on iOS 17+; verified every settled state (light /
      dark device × System / Light / Dark theme) has correct, matching
      status-bar contrast. The captured "light on dark" was a
      transition-frame artifact, not a persistent bug. While checking, did
      find a real 1-frame glitch — the sheet's nav bar flashed the tint
      colour as it slid up (a `NavigationStack`-in-`.sheet` quirk) — fixed
      with `.toolbarBackground(.visible, for: .navigationBar)` on
      `SettingsView`. app 80.
- [x] **Onboarding walkthrough.** Done 2026-09-07. `OnboardingView` — a
      3-page carousel (group → add expenses → settle up), each an accent
      glyph on a tinted circle + title + one line, with Skip / page dots /
      a Continue→Get Started button. Presented as a `.fullScreenCover` from
      `RootView` ahead of everything, gated on
      `OnboardingStoring` (new `UserDefaultsOnboardingStore` in ClanTabKit,
      sticky flag). Verified the full first run in the Simulator: fresh
      install → carousel → Skip/Get Started → start screen → relaunch skips
      it. Tests: `OnboardingStoreTests` (3) + `RootView.shouldPresentOnboarding`
      (2). kit 177 · app 82.
- [x] **Home Screen quick action.** Done 2026-09-07. A dynamic
      `UIApplicationShortcutItem` ("Add Expense" / subtitle = the
      most-recently-opened named group), refreshed by `RootView` on every
      group-list change. Received via a `SceneDelegate` (SwiftUI's `App`
      lifecycle never calls `UIApplicationDelegate.performActionFor`);
      `RootView` routes into the group and `GroupHomeView` opens the Add
      Expense sheet once its state is loaded — cold launch and warm launch
      both. Verified in the Simulator: the long-press menu shows it, and
      tapping opens straight to Add Expense. Tests: `QuickActionsTests` (6).
      kit 177 · app 88.
- [x] **Dynamic Type / VoiceOver audit.** Done 2026-09-07. Walked every
      screen at AX5 (accessibility-XXXL). Fixed the rows that broke —
      `ActivityRow`, `SettleUpView`, `MemberBalanceRow`, `InsightsView`'s
      breakdown rows: at accessibility text sizes the trailing
      amount/button now stacks under the name instead of being wrapped
      character-by-character or truncated off the edge; money `Text` got
      `.lineLimit(1)` everywhere. VoiceOver: the sim's a11y tree reads
      cleanly ("Aditi Rao is owed ₹2,030", "Rohan Mehta paid for … , Food,
      ₹1,480"); added explicit labels to the split toggles and the
      exact/percentage amount fields. app 88.

      Deferred (functional, just tight at AX5, not broken): the category
      icon grid and "Select All / Select None" in Add Expense; the
      activity-row metadata line truncates its date.
- [x] **Materials/blur on sheets.** Done 2026-09-07. Every sheet
      presented from Group Home + the Settings sheet now gets
      `.presentationBackground(.regularMaterial)` (`materialSheet()`), and
      each `Form`/`List` inside gets `.scrollContentBackground(.hidden)`
      (`materialSheetContent()`) so the blur shows through the gutters
      while the inset row groups keep their fill for legibility. Covers
      Add Expense, Settings, Your Groups, Settle Up, Group Settings, edit/
      duplicate expense, Import CSV, Recently Deleted, Recurring Reminders.
      Verified light + dark — contrast holds. app 88. (The one nested sheet,
      New Recurring Reminder, isn't converted — a follow-up.)
- [x] **Tonal surface elevation.** Done 2026-09-08. `App/ClanTab/Surface.swift`
      — a 4-tier scale (`well` → `canvas` → `card` → `raised`), each
      resolved per light/dark via a dynamic `UIColor`. The app's `List`
      screens now sit on an explicit `Surface.canvas`
      (`.scrollContentBackground(.hidden)` + `.background`) rather than the
      raw system tone, so canvas→card elevation is deliberate (clearest in
      dark mode: near-black canvas, lifted cards); the Insights bar tracks
      and the emoji-picker chips use `Surface.well` instead of
      `secondary.opacity(…)` guesses. Greys are plain today — the
      `DESIGN_BIBLE.md` §2 hue tint is the next item, and lands in this one
      file. app 88 · kit 177.
- [x] **Shadow/elevation on hero card + buttons.** Done 2026-09-08.
      `BalanceHeroView` is a raised `Surface.raised` card with a soft
      neutral shadow — it's now the clear focal point on Group Home rather
      than floating text. `primaryButtonShadow()` (a small accent-tinted
      lift, `active:` gates it off for a disabled button) on the three
      prominent CTAs: Create a Group, Add Expense submit, onboarding
      Continue/Get Started. Verified light + dark. app 88.
- [x] **Per-group accent color.** Done 2026-09-08. Since "Group visual
      identity" went with an emoji, added `GroupColor` to ClanTabKit —
      `DESIGN_BIBLE.md` §2's formula with the hue hashed from the group's
      permanent `id` (shared `OKLCH` primitive, same `55%/0.16` band as the
      brand accent). Scoped to the header, not the chrome (owner call):
      the balance hero card gets a light wash + matching shadow in the
      group's hue, and the groups list shows each group's emoji — or, with
      no emoji, its initial in white on a solid disc of its colour, same
      shape as a `MemberAvatar` (`GroupColor.badge(forId:)` at the `50%`
      band for white-text contrast). Two groups read clearly differently.
      Buttons/links stay brand blue. Tests: `GroupColorTests` (2).
      kit 179 · app 88. (Follow-up 2026-09-08: the no-emoji badge was a
      filled centre dot that read as a selected radio button — swapped
      for the initial.)
- [x] **Chart interaction + gradient fills.** `~25k tokens` (CLI)
      1. Add scrub/tooltip gestures to the existing `InsightsView`
         charts.
      2. Add a gradient fill using SwiftUI Charts' native support.
      Done 2026-09-08: the over-time bars get a native `LinearGradient`
      fill (accent → 40% accent, top-down) and `.chartXSelection` scrub —
      the touched bar stays lit while the rest drop to 0.3, with a
      `.regularMaterial` pill above it showing the period + amount. The
      by-member donut gets `.chartAngleSelection`: the scrubbed slice
      isolates (others dim to 0.3) and the centre annotation swaps from
      "Total" to that member's name + spend. Verified light + dark in the
      Simulator. kit 179 · app 88.
- [x] **Empty-state micro-copy pass.** `~12k tokens` (CLI)
      1. Rewrite each `ContentUnavailableView` string with more
         personality, keeping them accurate to the actual empty state.
      Done 2026-09-08: rewrote all seven empty/zero states — Group Home
      activity ("No Expenses Yet" → "Add the first one and ClanTab keeps
      a running tally of who owes whom"), the filtered-feed no-match,
      Insights ("Nothing to Chart Yet"), Recurring Reminders ("Nothing
      on Repeat Yet"), Recently Deleted ("Nothing in the Bin"), Settle
      Across Groups ("All Square"), and the CSV import intro. Warmer and
      more specific, still literally true to each state. Verified the
      Group Home and All-Square states light + dark in the Simulator.
      kit 179 · app 88.
- [x] **Spring/matched-geometry transition.** Done 2026-09-09. A literal
      cross-screen `matchedGeometryEffect` stays out: `RootView`'s
      `.id(route)` (from the group-switching fix) tears the outgoing
      screen down before the incoming one exists, so source and target
      are never co-present — the pre-2026-09-09 note already ruled the
      badge→balance-card morph infeasible for a different reason
      (async-gated target), and `.id(route)` makes it structurally
      impossible now. The achievable version shipped: opening / leaving a
      group runs `withAnimation(.claimSettle)` around the `route` change
      with a `.transition` on the routed subtree —
      `.scale(0.95) + .opacity` in, `.opacity` out — so the group screen
      springs up from 95% with a soft dissolve on the one shared
      confirm-moment curve (`Animation.claimSettle`, whose doc comment
      names this exact use). Form routes (`.createGroup` etc.) stay
      instant. **Verified in the Simulator** (2 seeded groups): opens and
      closes both directions cleanly, and the historical `.searchable`
      flipped-snapshot glitch does **not** reproduce mid-transition
      (mid-frame screenshot captured). The always-rendered accent
      placeholder card from the earlier pass stays. `make check` green.
      (Simulator-tooling note: an unsigned `CODE_SIGNING_ALLOWED=NO` sim
      build can't use the Keychain, so the dev-session recipe now needs
      an `InMemoryGroupAccessTokenStore` injected — logged in the
      `running-the-ios-app` memory.)
- [x] **Display typeface for wordmarks/hero numerals.** `~35k tokens`
      (CLI) + one design decision
      1. Owner/CLI: pick a free Google Fonts family for the display face.
      2. CLI: bundle it, apply it to the ClanTab wordmark + hero numerals
         only.
      3. CLI: verify Dynamic Type still scales it correctly.
      Done 2026-09-08. Face: **Space Grotesk** (owner pick — geometric
      grotesque, strong large-size numerals with tabular figures, SIL
      OFL). Bundled as three static instances (Medium/SemiBold/Bold)
      sliced from the Google Fonts variable font into
      `App/ClanTab/Resources/Fonts/` + `UIAppFonts`; `OFL.txt` ships
      alongside. `Font.display(...)` (`DisplayFont.swift`) wraps
      `.custom(_:size:relativeTo:)` so it scales with Dynamic Type
      (verified at AX-XL). Applied to: the pre-sign-in welcome wordmark,
      the Insights "Total spent" figure, and the recap card's total +
      "Made with ClanTab". Everything else — body, chrome, screen titles,
      iconography — stays SF Pro. (Follow-up 2026-09-08: the Group Home
      balance was reverted to SF Rounded — owner call, Space Grotesk's ₹
      and geometric digits read calculator-ish at that size — plus a thin
      space between the currency symbol and first digit, hero card only.)
      Not done: the signed-in start screen's wordmark is a system large
      *nav* title; fonting one SwiftUI large nav title needs either a
      global `UINavigationBar` appearance override (would hit every
      screen's title — violates "not chrome") or a scoped
      `UIViewControllerRepresentable` hack that didn't restore cleanly
      across the route-swap stack. Left as SF Pro. kit 179 · app 88.
- [x] **Gradient app icon / hero-moment treatment.** `~35k tokens` (CLI)
      + a new icon asset
      1. Owner/CLI: generate the two-stop-gradient icon variant per
         `DESIGN_BIBLE.md` §3's workflow.
      2. CLI: run the icon through the §3 distinctiveness check.
      3. CLI: apply the same gradient treatment to the balance hero card.
      Done 2026-09-08. Icon: the "=" motif is unchanged; the flat
      `#0074CA` background is now a vertical `oklch(60% 0.15 250)` →
      `oklch(40% 0.14 250)` gradient (same stop-pair as
      `RecapCard.brandGradient`), regenerated by
      `docs/branding/make-app-icon.py`. Distinctiveness: legibility
      re-checked at 180/120/60/40 px on light + dark; motif unchanged so
      the shape reasoning carries; reverse-image + trademark search still
      need tools this environment lacks (noted in `DESIGN_BIBLE.md` §3).
      Hero card (owner call: "per-group gradient wash"): the flat
      `opacity(0.09)` accent tint on `BalanceHeroView` becomes a two-stop
      wash (`GroupColor.wash(forId:)` — the group's own hue at the §3
      60%→40% lightness points, `0.16 → 0.05` opacity over
      `Surface.raised`), so every group's card carries its identity with a
      hint of depth. Green/red amount colours and per-group hue both
      kept. Verified light + dark. kit 179 · app 88.
- [x] **Custom empty-state illustration.** `~20k tokens` (CLI wiring) +
      one illustration asset
      1. Owner/CLI: produce one illustration asset for ClanTab's
         zero-state.
      2. CLI: wire it into every "no groups yet"/"no expenses yet" state.
      Done 2026-09-08. Asset: `EmptyStateGlyph` (`DESIGN_BIBLE.md` §4) —
      an empty rounded "tab" outline holding the app's "=" mark,
      template-rendered so it tints `.secondary` and themes itself.
      Generated by `docs/branding/make-empty-state.py`. Wired into the
      genuine zero-states: StartView "No groups yet", Group Home "No
      Expenses Yet", Insights "Nothing to Chart Yet", Recurring Reminders
      "Nothing on Repeat Yet", Recently Deleted "Nothing in the Bin". The
      filtered-feed "Nothing Matches" and "All Square" keep SF Symbols
      (outcome states, not zero-state branding moments). Verified light +
      dark. kit 179 · app 88.
- [x] **Branded confirmation sound.** `~20k tokens` (CLI wiring) + one
      audio asset
      1. Owner/CLI: produce or source one short confirmation sound.
      2. CLI: play it alongside the existing haptic on "settled up,"
         never replacing it.
      Done 2026-09-08. Asset: `settled.caf` (`DESIGN_BIBLE.md` §5) — a
      short rising perfect fifth (C6→G6) on a soft exponential decay,
      peak ~0.32, synthesised by
      `docs/branding/make-confirmation-sound.py`. `ConfirmationSound.play()`
      uses `AudioServicesPlaySystemSound` (honours the ring/silent
      switch), called from `SettleUpView`'s "Mark as Paid" handler
      alongside the existing `.sensoryFeedback(.success)` — only on
      settling up, never add-expense. Verified in the Simulator: the
      settlement lands and the log shows the system sound server engaged
      at the tap. kit 179 · app 88.
- [x] **Tabular figures + thousands-separator style.** `~10k tokens`
      (CLI)
      1. Set the tabular/lining figure font feature on hero numerals.
      2. Confirm one consistent separator style in `MoneyFormat`.
      Done 2026-09-08. (1) `.monospacedDigit()` is baked into
      `Font.display(size:…)`, so every hero numeral (balance, Insights
      total, recap card) gets Space Grotesk's `tnum` — a value that
      updates in place no longer nudges its neighbours. The face's
      figures are already lining. (2) `MoneyFormat.string` now pins
      grouping to threes (`groupingSize`/`secondaryGroupingSize` = 3,
      `,` group / `.` decimal) regardless of device locale — a lakh
      reads "₹100,000", not "₹1,00,000"; the currency symbol stays
      locale-native. New test `testStringGroupsByThrees`. kit 180 · app 88.
- [x] **Tint neutral text/surface tones.** `~20k tokens` (CLI)
      1. Mix 10-15% of the app's hue into the grey tokens defined in
         "Tonal surface elevation" above.
      2. Spot-check contrast ratios still pass.
      Done 2026-09-08. `Surface.swift`'s four tiers now carry a fixed
      `chroma 0.007` at 250° instead of pure grey (`DESIGN_BIBLE.md`
      §2) — landed at ~4% of the accent chroma, not 10-15%: at the
      near-white light tiers a bigger tint clips one channel and reads
      as a blue cast, not a neutral. The two brightest light tiers
      dropped a hair off pure white (`card` 0.995→0.99, `raised`
      1.0→0.995) so the tint registers. Contrast unchanged (lightness
      dominates luminance): primary text ~19:1, secondary ~10:1 on
      canvas — well past AAA. System `.secondary`/`.tertiary` text left
      as-is (tinting it app-wide fights the system controls beside it).
      Verified light + dark. kit 180 · app 88.
- [x] **Name + standardize the shared spring curve.** `~15k tokens`
      (CLI)
      1. Pick one response/dampingFraction pair, name it (e.g.
         `.claimSettle`).
      2. Apply it to every confirm-moment transition instead of
         per-call-site defaults.
      Done 2026-09-08. `Animation.claimSettle` (`App/ClanTab/Motion.swift`)
      = `spring(response: 0.4, dampingFraction: 0.85)`, settled, not
      bouncy (`DESIGN_BIBLE.md` §5). Applied to the one confirm-moment
      transition that exists today — the delete/undo toast on Group Home
      (was `.default`). The chart-scrub `.easeOut` and onboarding page
      `.easeInOut` are continuous/navigational, not confirm moments, so
      they keep their curves. Future confirm-moment transitions (a
      settle-up animation, the deferred open-a-group hero) adopt
      `.claimSettle`. kit 180 · app 88.

- [x] **Close test gaps from the confirm-moment polish batch.** Done
      2026-09-08. Added six `GroupsListViewTests` cases for
      `GroupsListView.initial(for:)` — first letter uppercased, leading
      emoji skipped, leading digits skipped, and emoji-only / symbol-only /
      empty names all falling back to `"#"`. `BalanceHeroView`'s
      `spacingCurrencySymbol` went from `private func` to an internal
      `static func` (behaviour unchanged; call site now `Self.`-qualified),
      covered by a new `BalanceHeroViewTests` — a prefix-symbol currency
      (`"₹1,200"` → thin space inserted, incl. a leading-minus amount), a
      suffix-symbol format (no-op), and an already-spaced input (no-op).
      kit 180 · app 97.
- [x] **De-duplicate GroupColor's hue math.** Done 2026-09-08. Both
      `color(forId:)` and `badge(forId:)` in `GroupColor+Color.swift` now
      call one `private static func swatch(forId:lightness:)` that holds
      the single `OKLCH.sRGB(hue:lightness:chroma:)` call; the two entry
      points just pass their lightness constant (`GroupColor.lightness` /
      `0.50`). `color(forId:)` no longer round-trips through the kit's
      `rgb(forId:)`, but the maths is identical, so output is unchanged and
      `GroupColorTests` (kit) passes untouched. kit 180 · app 97.
- [x] **Verify `settled.caf` is actually bundled.** Done 2026-09-08. Ran
      `cd App && xcodegen generate` and inspected the generated
      `ClanTab.xcodeproj/project.pbxproj`: `settled.caf` has a
      `PBXFileReference` and a `PBXBuildFile`, and `settled.caf in
      Resources` is listed in the ClanTab target's `PBXResourcesBuildPhase`
      (Copy Bundle Resources) alongside the Space Grotesk fonts. So the
      folder-source auto-detection on `sources: - path: ClanTab` already
      picks it up — **no explicit `resources:` entry was needed**, and
      `project.yml` is unchanged. (Owner still to confirm the chime is
      audible on a device/Simulator with the ringer on.) kit 180 · app 97.
- [x] **Fix CSV import: Settle Up was completely broken, plus a real
      remainder-rounding bug.** Done 2026-09-08, prompted by a real failed
      import (`Future.csv`, a Settle Up trip export — originally described
      as a Splid export; the exporter later confirmed it was Settle Up, and
      the attribution was corrected repo-wide on 2026-09-08). Two bugs, both
      silent — the import screen just said "Couldn't read that file":
      1. `ImportCSVView` read the picked file as UTF-8
         (`String(contentsOf:encoding:.utf8)`). Settle Up's iOS/macOS export
         is UTF-16LE with a BOM, which throws immediately under that
         assumption — same failure mode as Numbers' "CSV" save and Excel's
         "Unicode Text" export. Fixed with a new
         `CSVImport.decode(_ data: Data) -> String?` (BOM-sniffing UTF-8 /
         UTF-16LE / UTF-16BE, falling back through UTF-8 → UTF-16LE →
         Latin-1 with no BOM); `ImportCSVView` now reads bytes and calls it
         instead of assuming an encoding.
      2. No Settle Up parser existed at all — `CSVImport.parseSettleUp` added
         (`Who paid`/`Amount`/`Currency`/`For whom`/`Split amounts`/
         `Purpose`/`Category`/`Date & time`/`Type`; `Type` `expense` vs
         `transfer` for settlements). Unlike Splitwise's lossy per-person
         net-balance reconstruction, Settle Up's `For whom`/`Split amounts`
         are parallel lists giving each share directly, so it round-trips
         losslessly.
      3. Found only by checking against the real file, not a hypothetical:
         Settle Up rounds each share to 2dp independently on an equal split,
         so ~6% of rows in the real sample were a paisa off the row total
         (`₹6628 ÷ 3 → 2209.33 × 3 = 6627.99`). A strict sum-must-match
         check would have silently dropped those rows. Fixed by nudging the
         small remainder onto the payer's own share — the same rule
         `Validation.equalSplit` already uses.
      Also hardened: a stray BOM *character* surviving decode no longer
      breaks header matching; `parseDate` gained Settle Up's
      `yyyy-MM-dd HH:mm:ss` format. Full writeup + the (still open) gaps —
      no duplicate-import guard on any format, EU-locale comma-decimal
      amounts unhandled, Tricount/Splid still unsupported (no verified
      sample to build against) — in `docs/csv-import-formats.md`.
      Written first in a sandbox with no Swift toolchain (cross-checked
      with a Python re-implementation of the parsing logic); a later pass
      compiled it unchanged and confirmed green — `swift test --filter
      CSVImport` (19 cases, incl. the UTF-16 round-trip and the
      remainder-nudge) and `make check` both pass, and the real reported
      file parses to 31 expenses + 4 settlements with 0 warnings (the 2
      rounding-short rows nudged, not dropped). No behaviour changes were
      needed on that pass. kit 190 · app 97.

### Feature backlog — absorbed from the competitive scan

Splitwise/Tricount/Settle Up/Splid, primary sources only:

- [~] **De-dupe guard on CSV import.** `~20k tokens` (CLI) — found
      2026-09-08 while fixing Settle Up import (`docs/csv-import-formats.md`).
      Every imported row gets a fresh client-generated id, by design, so a
      partial import is safe to retry — but that also means importing the
      *same* file twice (or the same trip exported from two apps by two
      group members) silently posts every row again. No detection at all
      today.
      **Interim done 2026-09-09:** `ImportCSVView`'s review screen shows an
      amber caution above the Import button ("ClanTab won't skip expenses
      it already has…") — a re-import is no longer silent, though it's not
      blocked. `make check` green.
      **Still open — the real fix:** a definition of "same expense" across
      apps (date+amount+payer+description, allowing for each app's own
      rounding) and a check against the group's existing ledger before
      posting.
- [ ] **Balance bubble/circle-pack view.** `~30k tokens` (CLI) — Settle
      Up's group-home screen (not in the original competitive scan) shows
      each member as a circle sized by |balance|, one big "should pay"
      bubble front-and-center, everyone-settled members shrunk to a dot.
      Cheap: no charting library needed, `Canvas` + a simple circle-pack
      layout (biggest circle centered, rest placed around it by a
      spiral/grid heuristic — exact packing isn't the point, it reads fine
      approximate) — same pattern this app already uses for the Insights
      donut (`SwiftUI Charts` is for axis-based charts; this one is custom
      either way, in SettleUp's own implementation and here). Reuses the
      existing per-member `GroupColor` for fill. Good candidate for a
      second Group Home page (rotates alongside the existing balance hero
      per the screenshot pattern) rather than a replacement — it reads
      well for "who owes the most" at a glance but is worse than the list
      for "how much do I owe whom," which is what settle-up actually needs.
- [ ] **Splid import — get a real sample.** `~15k tokens` investigation +
      build (CLI) — surfaced 2026-09-08 when `Future.csv`, the file the CSV
      importer was built and verified against, turned out to be a Settle Up
      export, not Splid (the exporter confirmed it). Settle Up support is
      done; actual Splid support is now the gap. Splid's iOS/macOS app does
      have a CSV export, and it shares the same `Who paid`/`For whom`/`Split
      amounts` header shape — but we have **no verified Splid sample**:
      nobody's posted one publicly and we haven't triggered one ourselves,
      so the exact column shape, decimal-locale convention, settlement-row
      encoding, and any per-row rounding quirk are all unconfirmed for
      Splid specifically.
      1. Get someone to trigger Splid's own CSV export on a throwaway 2-3-row
         group, redact names, hand over the file.
      2. Check the existing `parseSettleUp` against that real file — it may
         already handle Splid given the shared header, or it may not.
         Verify the sign/share convention, decimal locale, settlement-row
         shape, and any per-row rounding quirk (Settle Up's was a real
         6%-of-rows bug a guess would've missed) before claiming Splid as
         supported; branch the parser or split detection only if the real
         file forces it.
- [ ] **Tricount import — get a sample first, likely low priority.**
      `~10k tokens` investigation, build TBD after (CLI) — researched
      2026-09-08 (`docs/csv-import-formats.md`). Tricount's self-serve
      CSV/PDF export was a Premium feature that's now **deprecated**
      (help.tricount.com/articles/tricount-faqs, checked 2026-09-08): the
      only way to get a file today is emailing support@bunq.com and waiting
      for them to send one. No published column schema exists — the one
      public "Tricount exporter" tool on GitHub scrapes Tricount's API and
      invents its own CSV shape, which is not what Tricount itself would
      ever hand a user.
      1. If this is still wanted, get someone to request their own export
         via bunq support, redact it, hand it over as the real sample —
         don't build against the unofficial scraper's invented schema.
      2. Weigh against the rest of the backlog before spending CLI budget:
         since there's no self-serve export anymore, this only helps people
         who already have an old export file sitting around, not anyone
         swapping in from Tricount going forward.
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
- [ ] **Image storage backend (R2).** `~35k tokens` (CLI), blocked on
      an Owner step — unblocks the three items below (profile photos,
      group cover images, receipt attachments) and any future
      "attach an image" feature. Was parked 2026-09-06 because R2
      needs a billing card, breaking the zero-card invariant kept
      everywhere else in this project — that invariant stops applying
      once monetization ships (App Store Connect already needs
      bank/tax details for paid IAP), so this is unparked pending the
      monetization-stance decision (`Decide the monetization stance`,
      above). Cost is negligible regardless: R2 has no egress fee and
      free tiers of 10GB storage / 1M writes / 10M reads per month;
      realistic usage stays inside or barely above that even at 1M
      users (~$3-15/mo). Build once, wire to all three surfaces
      below — don't build three separate upload paths.
      1. Owner: enable R2 on the Cloudflare account (adds a billing
         card to that account, nothing user-facing).
      2. Add an `r2_buckets` binding in `wrangler.jsonc`, one bucket,
         objects namespaced by path (`avatars/{userId}`,
         `groups/{groupId}/cover`, `expenses/{expenseId}/receipt-{n}`).
      3. Worker: an authenticated endpoint that checks the caller's
         session + group membership and returns a short-lived
         presigned R2 URL for PUT (upload) or GET (view) — the Worker
         never proxies the image bytes itself, keeping compute/
         duration cost flat regardless of image volume.
      4. Server-side validation on upload: mimetype whitelist, size
         cap (reject >5MB pre-compression) — don't trust client-side
         compression alone.
      5. Delete-on-delete: hook the existing member-remove /
         expense-delete / group-delete paths to also delete the
         associated R2 object(s), so storage doesn't grow with
         orphans.
- [ ] **Profile photos (replacing/supplementing initials avatars).**
      `~25k tokens` (CLI) — needs the R2 backend above shipped first.
      1. iOS: image picker + client-side resize to ~512px + JPEG
         compress (~q0.7) before upload — the actual cost/UX lever,
         do this even though the server also caps size.
      2. Wire upload through the presigned-URL flow; store the R2
         object key on the user record (`UserDO`), not the blob.
      3. Swap the existing `MemberColor` initials avatar for the
         photo wherever it renders, falling back to initials when
         unset.
- [ ] **Group cover image.** `~20k tokens` (CLI) — needs the R2
      backend above; reuses the same upload/compress/display pattern
      as profile photos with the object keyed to the group instead of
      the user.
      1. Add an optional cover-image field to the group record.
      2. Group Settings: upload/replace/remove UI.
      3. Show it on the group's dashboard entry and header.
- [ ] **Photo attachment on an expense (receipts).** `~30k tokens`
      (CLI) — needs the R2 backend above. Plain photo attachment
      only; receipt OCR stays out of scope (see Parked below).
      1. Add an `attachments: [String]` (R2 object keys) field to the
         expense model, worker + `ClanTabKit`.
      2. Add Expense: attach-photo action (camera or picker), same
         resize/compress step as above.
      3. Expense detail: thumbnail + full-screen view via the
         presigned-URL flow.
      4. Include in the delete-on-delete cleanup from the backend
         item.

### Parked — not dropped, revisit deliberately

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

**Marketing/legal site, 2026-09-09** — `clantab.nakka.dev` (Home, Privacy,
Support, Terms, Contact) shipped as its own repo `nakka-labs/clantab-website`
on Cloudflare Pages, built from real app content. App Store Connect
Privacy/Support URLs repointed there. `docs/privacy-policy.md` +
`docs/support.html` remain the upstream source, hand-ported into that repo.

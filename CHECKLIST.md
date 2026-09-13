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
- [x] **Decide the monetization stance.** Done 2026-09-10, owner-decided.
      Free, no paywall, full feature set open to anyone who installs —
      rejected a mandatory one-time purchase: the app only works once a
      whole group installs it, so gating install behind payment fights
      the adoption mechanic directly (every competitor in the
      competitive scan — Splitwise, Tricount, Settle Up, Splid — is
      free-to-join for the same reason), and realistic revenue at this
      app's scale rounds to zero against the infra cost it'd supposedly
      offset (infra is already ~$5-55/mo regardless, per the cost model
      above). Parked, not decided against: an optional one-time
      "support the dev" tip IAP, non-blocking, same shape as the
      GitHub Sponsors call made for the other portfolio apps — revisit
      as its own later item if wanted for the StoreKit/IAP portfolio
      value, never as a gate.
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
      3b. [x] CLI: build `1.0 (10)` archived, exported, and uploaded
          2026-09-13 — carries every fix since build 9 (the fresh-eyes UI
          audit's [3]/[4]/[6]/[7] and the rescan's two backend fixes, both
          above). Checked the live build number in ASC first (`9`, matched
          the repo — no drift to correct this time), `make bump-build` →
          `10`, `xcodebuild archive` + `-exportArchive` with `destination:
          upload` in `ExportOptions.plist` (the newer one-step flow —
          no separate `altool` calls needed) using the Admin-role ASC API
          key. `processingState VALID` within ~2 minutes, automatically
          assigned to the internal **"test-team"** group alongside builds
          1–9, "What to Test" set. Archive at
          `~/Library/Developer/Xcode/Archives/2026-09-13/`.
      3c. [x] CLI: build `1.0 (11)` archived, exported, and uploaded
          2026-09-13 — carries the full round-3 playtest batch (the round-3
          section above, closed same day). Checked the live build number
          via the ASC API first (`GET /v1/builds?filter[app]=6807057518
          &sort=-uploadedDate&limit=1` — `10`, matched the repo), `make
          bump-build` → `11`, same archive + `-exportArchive` flow as 3b.
          `processingState VALID`. Archive at
          `~/Library/Developer/Xcode/Archives/2026-09-13/ClanTab-1.0-11
          .xcarchive`. Owner testing this build in parallel with the
          "Merge duplicate members" work below.
      3d. [x] CLI: build `1.0 (12)` archived, exported, and uploaded
          2026-09-13 — adds the merge-duplicate-members app UI on top of
          round-3 (worker side already deployed separately). Checked the
          live build number first (`11`, matched the repo), `make
          bump-build` → `12`, same flow as 3b/3c. Upload succeeded; still
          processing as of this note. Archive at
          `~/Library/Developer/Xcode/Archives/2026-09-13/ClanTab-1.0-12
          .xcarchive`.
      3e. [x] CLI: build `1.0 (13)` archived, exported, and uploaded
          2026-09-13 — carries the personal-Insights rework, member-
          balance breakdown, bubble-sizing fix, delete-dialog revert, and
          duplicate-amount fix ("Real-device findings" above) on top of
          build 12. Checked the live build number first (`12`, matched
          the repo), `make bump-build` → `13`, same flow as 3b/3c/3d.
          Upload succeeded; still processing as of this note. Archive at
          `~/Library/Developer/Xcode/Archives/2026-09-13/ClanTab-1.0-13
          .xcarchive`.
      3f. [x] CLI: build `1.0 (14)` archived, exported, and uploaded
          2026-09-13 — carries the Insights race-condition/crash-risk
          fix (`.onChange(of: auth.groups)`, safe dictionary
          construction) found reviewing the Owner's "insights completely
          removed" report on build 13. Checked the live build number
          first (`13`, matched the repo), `make bump-build` → `14`, same
          flow as 3b–3e. Upload succeeded; still processing as of this
          note. Archive at
          `~/Library/Developer/Xcode/Archives/2026-09-13/ClanTab-1.0-14
          .xcarchive`.
      3g. [x] CLI: build `1.0 (15)` archived, exported, and uploaded
          2026-09-13 — carries every fix since build 14: the full D1-D14
          code-level-defect audit (EU-locale CSV corruption + its
          plausibility-flag safety net, the type-checker house rule,
          `AddExpenseView`'s itemized-editor extraction, `print()` →
          `os.Logger`, the UPI-ID currency gate, the Remind cooldown,
          the Group-Settings invite link) and the Insights-tab-removal
          follow-through (`MySpendingView` replacing `InsightsHubView`).
          Checked the live build number via the ASC API first (`GET
          /v1/builds?filter[app]=6807057518&sort=-uploadedDate&limit=1`
          — `14`, matched the repo; note for next time: `curl`'s URL
          globbing parser chokes on the literal `[app]` in that query
          string with exit 3 "URL malformed" unless called with `-g`).
          `make bump-build` → `15`, same archive + `-exportArchive`
          `destination: upload` flow as 3b–3f, same Admin-role ASC API
          key. `processingState VALID` within ~2 minutes (confirmed via
          the API, not assumed), `usesNonExemptEncryption: false`
          auto-answered, already assigned to the internal **test-team**
          group alongside builds 1–14. Set the "What to Test" note via
          `PATCH /v1/betaBuildLocalizations/:id` (plain, tester-facing
          language — CSV import fix, My Spending replacing Insights, UPI
          ID/Remind/Invite fixes). Archive at
          `~/Library/Developer/Xcode/Archives/2026-09-13/ClanTab-1.0-15
          .xcarchive`.
      4. Owner: run the pass on a real device — Sign in with Apple/Google,
         a push (CLI triggers it via an API expense-add), a recurring-
         reminder delivery, a shared `clantab.nakka.dev/g/…` link opening
         the app, Report a Problem, Delete Account, and a `GroupBackup`
         record in the CloudKit Dashboard's *Production* environment.
         **Added 2026-09-11, once a build carrying the round-2 batch
         ships:** the Friends screen with **two real signed-in
         accounts** that share a group — confirm a friend who's settled
         up still lists, "Start a Private Tab" from one side then
         "Open" (not "Start") the same tab from the other with no
         invite step, an expense added in it, and that it never appears
         in either account's main groups list / dashboard totals. This
         is the one class of check the CLI's live-smoke-test couldn't
         cover (every new route needs a real Bearer session).
         **Added 2026-09-13, once a build carrying the round-3 batch
         ships:** Delete Account specifically re-checked for "signing
         back in shows zero groups" (not just "signed out") — the exact
         bug that batch fixed; an Edit on a settlement row actually
         saves; a description like "Uber to airport" auto-picks a
         category; the Group Home floating Add Expense button doesn't
         collide with the undo banner after a delete.
      5. Owner: tag the version once it passes.
- [ ] **Submit for App Store review.** `Owner` — no CLI budget
      1. Owner: submit only after every item above, every item under
         "Design & UX polish" below, every item under "Friend playtest +
         competitive gap-fill, round 2" below (accepted 2026-09-10 as a
         small, bounded launch delay — see that section for why), every
         item under "UX audit, build 9" below (added here 2026-09-12 —
         that section didn't exist when this gate was first written;
         **all 34 of its findings are now done as of 2026-09-12**,
         including [29]'s pointer to "De-dupe guard on CSV import" in the
         Feature backlog, which is also done), **and** every item under
         "Friend playtest, round 3" below (added here 2026-09-13 — a new
         real-device batch on build 10; the three large items in that
         batch — merge duplicate members, universal display name, link
         Apple/Google accounts — are deliberately *not* part of this
         gate, see "Parked" below for why).
      Pricing is done: Price = Free across all 175 territories, set via
      the ASC API 2026-09-10 (`POST /v1/appPriceSchedules`, base
      territory USA at the free price point); 0 IAP products / 0
      subscription groups. So the remaining gates are the real-device
      TestFlight pass (step 4 above), the rest of the UX audit batch,
      tagging, and this submit decision.

### Friend playtest + competitive gap-fill, round 2 — accepted 2026-09-10

Real-device feedback from a friend using the app (not the owner), plus a
second competitive scan against Splitwise/Tricount/Settle Up/Splid,
critically triaged in chat 2026-09-10. Accepted as ship-blocking — a
small, bounded launch delay, not a reopen of "what should this app be."
Everything that came up in that scan and is NOT listed here was
deliberately cut, not missed — see "Parked" below for the ones worth
writing down, "Non-goals" for the rest.

**Batch closed 2026-09-11** — every item below shipped. The name-wise
filter accuracy item (the friend's "not accurate" report) was manually
re-verified by the owner and works correctly; dropped rather than kept
as a checklist line with nothing left to do. Round-2 is done; only the
Owner-only TestFlight pass + submit remain.

- [x] **Friends/contacts list with live cross-group balances + private
      1:1 tabs.** Done 2026-09-11. The reason for the round-2 delay.
      1. [x] **Spike done 2026-09-10 — no new identity plumbing needed.**
         The "claim a placeholder member" mechanism already links a group
         `Member` to an authenticated account: `members.identity_sub`
         (schema v5, nullable), the composite `"<provider>:<sub>"` string,
         with `claim()` enforcing one identity per member per group
         (`GroupDO.claim` rejects a second member for the same `sub`). So
         "same person across groups" keys on `identity_sub` for free — and
         `GET /api/auth/people` → `handleAuthPeople` → `PeopleView`
         ("Settle Across Groups") **already** does the read-side
         cross-group peer aggregation over `GroupDO.peerSettlements`,
         concurrently fanned out over `UserDO.listGroups()`. Remaining
         work is therefore a first-class **Friends tab** (promote/extend
         the `people` aggregation, add zero-balance friends, per-person
         drill-in), **hidden 2-person groups** for 1:1 tabs (auto-created,
         `UISceneDelegate`-hidden, reuse every existing piece), and the
         **member profile screen** (shared with item 8 below). Not started.
      2. [x] **Private 1:1 tabs — done.** A hidden, auto-created 2-person
         `GroupDO`, keyed by a **deterministic groupId**:
         `oneOnOneGroupId(subA, subB)` (SHA-256 of the sorted identity
         pair, `tab-`-prefixed) — not a secret (`groupId` never has
         been); the group's own randomly-generated `access_token`
         (`initGroup`, unchanged) is the real capability. `group_meta.hidden`
         (new key, no schema bump) marks it; `GroupSummary.hidden` /
         `peerSettlements` surface it. New `POST /api/auth/friends/tab`:
         ensure-and-return the tab between the caller and a friend,
         proof-of-relationship being any `(groupId, theirMemberId)` pair
         from `GET /api/auth/friends` (caller has a claimed member
         there, `theirMemberId` resolves to a *different* claimed
         identity — a group proves itself, so the tab's own id works
         too once it exists). First call creates the group and claims
         **both** sides directly server-side via the existing
         `initGroup`/`addMember`/`claim`/`addMembership` primitives —
         no join code redeemed, no invite link — and registers the
         membership in *both* identities' `UserDO` indexes, which is
         what makes the tab reachable from either side afterward with
         zero invite step. Idempotent after: same groupId, always a
         valid token. `UserDO` gained its own `USER_SCHEMA_VERSION` 2
         (`memberships.hidden`, mirrors the group's own flag so
         `GET /api/auth/groups` can tell a tab apart from a normal group
         with no extra `GroupDO` round-trip) — its first-ever migration,
         same `migrate()` pattern as `GroupDO`.
      3. [x] **Friends list screen — done.** `GET /api/auth/friends`:
         every OTHER claimed co-member across every shared group (formal
         + hidden tab), regardless of balance — a directory, unlike
         `/api/auth/people`'s nonzero-only settle worklist (which stays
         unchanged; the concurrent `peerSettlements` fan-out was
         extracted into a shared `fetchPeerViews` helper). Reverses the
         "no second cross-group ledger" non-goal below, exactly as
         planned: one read-side aggregation over every shared ledger,
         no new write-side ledger. App: `FriendsView` (toolbar button on
         `StartView`, next to Settings — a new `AppRoute.friends` case,
         no tab bar added) lists every friend with
         `PeopleView.summary`'s existing "You owe / owes you / Settled
         up" line; tapping one pushes `FriendDetailView` (aggregate
         balance, the shared *formal* groups for context, and a
         "Start/Open a Private Tab" button — idempotent either way —
         that routes straight into the ordinary `GroupHomeView` via the
         existing `enterGroup` path once the tab's ensured).
      4. [x] **Member tap → profile — done**, via the "Member profile
         screen" item below (`MemberProfileView`), already shipped
         2026-09-10 ahead of this item; reused as-is, no changes needed.
      **Verification:** kit 288 · worker 270 · iOS build + `ClanTabTests`
      green (`AuthViewModelTests` +5, `ClanTabAuthClientTests` +3,
      `KnownGroupsStoreTests` +2, worker `auth-routes.test.ts` +7,
      `user.test.ts` +2 incl. a v1→v2 migration walk). Deployed to
      production (version `6493ae8f`); live-smoke-tested unauthenticated
      (`/api/auth/friends` / `/api/auth/friends/tab` → `401`, a plain
      group create still `201`s). **Not yet verifiable from the CLI:**
      every new route requires a real signed-in Bearer session (Apple/
      Google identity), which can't be minted outside the app — full
      end-to-end confirmation (two real accounts, a shared group, a
      private tab created and reopened from both sides) is folded into
      the "TestFlight on-device end-to-end pass" below, alongside the
      other identity-gated checks already waiting there.
      **Follow-ups, not blocking:** `GroupSettingsView` still shows
      invite-link/join-code UI inside a private tab (harmless — there's
      no one to invite to an already-fully-claimed 2-person group — but
      pointless); a friend's row on `FriendsView` doesn't show an
      at-a-glance "has a private tab" hint before you open it.
- [x] **CSV import: identify failed rows, not just a count.** Done
      2026-09-11 — the repro finally landed: ran `Future.csv` (a real
      Settle Up export, 35 rows) through the actual import flow in the
      Simulator. Root cause found: 3 rows had a blank "Purpose", which
      round-tripped to an empty `description` — the server's own
      `requireString` (and `AddExpenseView.canSubmit`) reject that
      outright, so those 3 rows 400'd on post with the failure surfaced
      only as "Imported 32, 3 failed," no row, no reason. Two fixes:
      **(1) root cause** — `CSVImport.parseSettleUp`/`parseSplitwise`
      now substitute a generic "Expense" fallback for a blank
      Purpose/Description (`ClanTab` rows are exempt: its own export
      can't have written a blank one to begin with) — re-running
      `Future.csv` now imports all 35/35 cleanly, no failures at all.
      **(2) the actual ask** — `ImportCSVView.Stage.finished` now
      carries `[FailedRow]` (a date-stamped label + the server's own
      error message) instead of a bare `Int`; a genuine failure (a
      de-dup collision, a dropped connection, anything the parse layer
      can't see coming) now lists each row and why on the finished
      screen instead of just a count. Tests: `CSVImportTests` +2
      (blank-Purpose and blank-Description fallback, one per format).
      worker unaffected · kit 331. `make check` green — app/kit-only,
      nothing to deploy. Verified live in the Simulator both ways:
      before the fix, "Imported 32, 3 failed"; after, "Imported 35
      rows."
- [x] **Bubble graph: legibility floor, not just a zero-balance dot.**
      Done 2026-09-10. `CirclePack.layout` gained a `minNonZeroRadius`
      parameter (default `0` = disabled, so existing callers/tests are
      unchanged) — a floor applied only to items with a *nonzero* weight,
      re-applied after the scale-to-fit shrink so a crowded box can't push
      a real balance back under the label threshold (at the cost of a
      slight overlap in that rare case). A genuine zero still floors at
      `minRadius`. `BalanceBubbleView` passes `minNonZeroRadius: 20` and
      the initials threshold dropped `20 → 19` for float headroom, so any
      nonzero balance now shows at least initials. Test:
      `CirclePackTests.testNonZeroFloor`. `make check` green.
- [x] **All Insights graphs interactive — tap a member to filter.** Done
      2026-09-11. `ClanTabKit.Insights.totalSpend`/`byCategory`/`overTime`
      all gained an optional `memberId` (default `nil` — every existing
      caller unaffected) that scopes each expense's contribution down to
      that member's own split share, the same "what they consumed, not
      what they paid" rule `byMember` already used. `InsightsView` gained
      one shared `selectedMemberId` (not per-chart state, per the plan) —
      tapping a "By member" row toggles it (tap again to clear), which
      re-filters "Total spent" (relabelled to "Ana's spend" + a "Show
      Everyone" button), the over-time bars, and the category
      pie/breakdown all at once. "By member" itself always stays
      unfiltered (it's the list *doing* the filtering) and its bars are
      proportioned against a separate always-whole-group `groupTotal`, not
      the (possibly narrowed) `total` — otherwise another member's bar
      could read as "over 100%" once a filter shrinks the denominator.
      The shareable recap card also always uses the unfiltered group
      total — sharing mid-filter shouldn't quietly share a narrower
      number. Tests: `InsightsTests` +3 (`totalSpend`/`byCategory`/
      `overTime` with `memberId`). kit 300 · app build green.
- [x] **Category pie chart in Insights.** Done 2026-09-11. A genuine
      pie (no inner radius — reads as a different chart from the
      "By member" donut at a glance), each slice in that category's
      existing formula-driven pastel color + SF Symbol icon
      (`CategoryPickerView`'s `ExpenseCategory.pastelColor`, no new
      palette). Same drag-to-isolate interaction as the member donut
      (`CHECKLIST.md` "Chart interaction"); since a full pie has no
      hollow center for a resting label, the scrub tooltip is a floating
      material pill shown only while actively dragging, rather than a
      permanent center label. Automatically respects the member filter
      above, since `byCategory` already takes `selectedMemberId`.
- [x] **Split by shares (ratio split).** Done 2026-09-10. 5th `SplitType`
      case, `.shares` — divide by whole-number ratios (A : 4, B : 2 → A
      owes 4/6). **Kit:** `ShareWeight { memberId, weight }`,
      `Expense.shares` / `AddExpenseRequest.shares` (`[ShareWeight]?`, same
      contract as `items`); `Validation.sharesSplit` (literally
      `percentageSplit` — identical maths, named for call-site clarity) +
      `Validation.validateShares` (≥1 weight, none negative, positive
      total, members exist); new `ValidationError.emptyShares` /
      `.invalidShareWeight`. 8 kit test cases incl. fuzz. **Worker:**
      schema **v11** — `expenses.split_type` CHECK widened + `expenses.shares`
      (nullable JSON) added, one `expenses`-table rebuild (same dance as
      v8); `assertSharesValid`; `parseExpenseBody` enforces shares ⟺
      splitType shares; migration test + 3 route/DO cases. **App:**
      `AddExpenseView` "Shares" segment — per-member number field + a
      `Stepper`, a live "4/10 · ₹400" line per member, and a "Split into N
      shares" footer; picked "Shares" seeds every member at weight 1; edit
      rehydrates the stored weights directly (no back-computing).
      **CSV / JSON export / CloudKit backup:** unchanged — `splitType`
      isn't in the CSV, and `shares` rides `Expense`'s Codable for JSON /
      backup, same as `items`. `DESIGN.md` §2/§6/§10 updated.
      **Deployed to production 2026-09-10** (version `b40d4b6b`) and
      verified live over HTTPS against `clantab.nakka-labs.workers.dev`: a
      `shares` POST (Ana : 7, Ben : 3 of ₹1000, Ana paid) returned `201`
      with the weights, `getState` round-tripped `splitType: "shares"` +
      the `shares` array, balances resolved to Ana +300 / Ben −300, and
      all-zero weights returned `400 SPLIT_MISMATCH`. The v10→v11 table
      rebuild is additive (copies every column) and unit-tested end to end
      in `group.test.ts` (v1→v11 walk); existing production groups run it
      on next access.
- [x] **Add member inline from Add Expense, + search on the member
      picker.** Done 2026-09-11. `AddExpenseView.members` became
      `@State` (was `let`) so adding someone here updates every picker
      in the sheet immediately, with no round trip through the parent.
      New `AddMemberSheet` (name field → `client.joinGroup`, the same
      add-by-name-only placeholder `GroupSettingsView`'s own "Add
      Someone" already uses) reachable via an "Add Someone" row under
      the Equal split's member list — new members land in every other
      split type too since they all read the same local list. The
      "Paid by" single-payer row is now a `NavigationLink` to a new
      `MemberPickerView` (mirrors `CategoryPickerView`'s existing
      push-a-picker-screen shape) with `.searchable` search-or-add —
      typing a name with no match offers "Add "<name>"" inline, same
      backend call. The Equal/Exact/Percentage/Shares member lists
      (not itemized's per-item participant `Menu` — a `Menu` isn't
      list-shaped, left as-is) gain a plain search field once a group
      has more than 8 members; it only filters which rows are visible,
      every total/validation still sums over the full member list.
- [x] **Member profile screen: settle-up amount + UPI ID.** Done
      2026-09-10. `MemberProfileView` (App) — a read-only `List`: avatar +
      name, "Balance in this group" (per-currency owed/owes, green/red),
      "Settle up" (the simplified-plan edge between you and them, phrased
      "You pay X" / "X pays you", with a "Pay via UPI" `Link` when you owe
      an INR amount and they've set a VPA), and "UPI ID" (the raw VPA,
      selectable + a copy button) when set. All from existing group state.
      Reached via a `NavigationLink` wrapping each `MemberBalanceRow` in
      Group Home's Members section — will be reused from the Friends list
      (item 1) once that lands. Refactor: the `upi://pay` URL builder
      moved out of `SettleUpView` into a pure `UPIPayLink` (ClanTabKit,
      `Logic/`) shared by both screens; `UPIPayLinkTests` (2). `make
      check` green.
- [x] **"Remind" button on an outstanding balance.** Done 2026-09-11. The
      opposite direction of `BalanceAgingScheduler` (only ever nudges
      *you* about what you owe): a new endpoint
      `POST /api/groups/:groupId/members/:memberId/remind`
      (`:memberId` = the debtor; body `{ fromMemberId }`, client-supplied
      attribution — same trust model as `deletedBy`) recomputes the live
      pairwise edge from `simplifiedSettlements` itself (never trusts an
      amount from the client, `AGENTS.md` "Derived Balances"), resolves
      the debtor's identity via the existing `memberIdentity`, and pushes
      just that one person via a new narrow `notifyMember` (the
      single-recipient counterpart to `notifyGroup`'s broadcast) with a
      new `reminderPayload()` ("Priya sent you a reminder — you owe them
      ₹500.00"). Best-effort throughout — no edge, an unclaimed target,
      or no APNs config all just report `{ sent: false }`, never an
      error; no server-side rate limit for v1, only a client-side
      per-tap disable. **Kit:** `RemindRequest`/`RemindResponse`,
      `ClanTabClient.remind`. **App:** a "Remind" button in
      `MemberProfileView`'s existing "Settle up" section, shown only in
      the `!iPay` branch (they owe you) — turns into "Reminder sent"
      once `sent` comes back true, or a one-line error otherwise (e.g.
      they haven't signed in yet). Tests: `notify.test.ts` +8
      (`reminderPayload`, `notifyMember`'s config/multi-device/stale-
      token/no-devices/never-throws cases), `routes.test.ts` +7 (cross-
      group, no-edge, wrong-direction, unclaimed, claimed-but-APNs-
      unconfigured, missing field, no token), `ClanTabClientTests` +1.
      worker 298 · kit 301. **Deployed to production**
      (version `ec880666`) and verified live: cross-group/unknown
      member, wrong-direction, and unclaimed-debtor all correctly
      `{ sent: false }`; missing `fromMemberId` `400`s; no token `403`s.
- [x] **Comments on an expense.** Done 2026-09-11. **Worker:** new
      `comments` table (`id`, `expenseId`, `authorMemberId`, `text`,
      `createdAt`, soft-delete via `deletedAt`/`deletedBy` — same shape
      as `Expense`/`Settlement`, but **no restore path**, a deletion is
      permanent). A brand new table needs no CHECK-widening rebuild, so
      every pre-existing group gets it for free the next time its
      `GroupDO` boots; `SCHEMA_VERSION` still bumped to **12** for the
      historical record. Fetched via their own endpoints
      (`POST`/`GET`/`DELETE .../expenses/:expenseId/comments[/:commentId]`),
      **never embedded in `GroupStateResponse`** — that response is
      polled every ~25s, comments aren't (`DESIGN.md` §9's row-read cost
      model). `addComment` checks the expense exists (`NOT_FOUND`) and
      the author is a real member (`UNKNOWN_MEMBER`); empty text is
      already rejected at the parse layer. **Kit:** `Comment` model,
      `AddCommentRequest`/`Response`, `ListCommentsResponse`,
      `ClanTabClient.addComment/listComments/deleteComment`. **App:** a
      "Comments" section in `AddExpenseView` — shown only while editing
      (a fresh, unsaved expense has nothing to attach a comment to yet),
      fetched via `.task`, a compose row + per-comment `MemberAvatar`,
      swipe-to-delete (any member, matching this app's loose trust
      model — same as expense edit/delete today) and swipe-to-**Report**
      routed through the existing `ReportContentView`
      (`target: .member(authorId)`, a new `contextNote` param pre-fills
      the report's details with the flagged text) — no parallel
      moderation flow, per the original plan. Tests:
      `group.test.ts` +4 (incl. the v11→v12 migration walk),
      `routes.test.ts` +5, `ClanTabClientTests` +3. worker 279 · kit 291
      · iOS build green. **Deployed to production** (version `769bd072`)
      and verified live over HTTPS: two comments posted, listed in
      order, one deleted and gone from the list, an unauthenticated
      POST `403`s.
- [x] **Multiple payers on one expense.** Done 2026-09-11.
      `Expense.payerId: String` → `payers: [ExpensePayment]`
      (`memberId` + `amountMinor`, same shape as `ExpenseSplit`,
      contributions summing exactly to `amountMinor` — mirrors how
      `splits` already works). Kept a `payerId:` convenience init/param
      on both `Expense` and `AddExpenseRequest` for the overwhelmingly
      common single-payer case (the whole existing kit/app test suite
      needed no changes beyond a couple of raw-JSON fixtures), plus a
      computed `Expense.payerId: String?` (`nil` for a genuine
      multi-payer expense) for callers that only handle one payer.
      **Worker:** schema **v13** — `expenses.payers` (nullable JSON),
      plain `ALTER TABLE ADD COLUMN` (no CHECK to widen, no rebuild). A
      single-payer expense still writes only `payer_id`/`amount_minor`
      (no redundant blob, matching every existing row exactly); a
      multi-payer expense stores the array, `payer_id` becoming a
      harmless first-payer placeholder never read once `payers` is
      non-null. The read path (`toExpense`) synthesizes `payers` from
      `payer_id` when the column is `NULL` — **no data rewrite** for
      pre-existing rows. `assertPayersSum` mirrors `assertSplitsSum`.
      `removeMember`'s `MEMBER_IN_USE` check now also scans the
      `payers` JSON blobs — `payer_id` alone only ever names the first
      payer, so a non-primary payer could otherwise be removed out from
      under their own expense. `Balances.compute`/`computeBalances`
      credit each payer their own contribution instead of crediting one
      payer the full amount. **App:** `AddExpenseView`'s "Paid by"
      gains a "Split the cost between payers" toggle revealing
      per-member amount fields (same UI shape as the exact split);
      an uneven equal/percentage/shares/itemized split's remainder now
      goes to the largest contributor when multi-payer, not one fixed
      id. `ActivityRow` reads "Ana & Ben paid for X" / "Ana & 2 others
      paid for X" for 2 / 3+ payers (the leading avatar still shows the
      first); push notifications use the same phrasing. **CSV:**
      export's "From" column uses the Splits column's own
      `"name:amount; ..."` shorthand for 2+ payers;
      `CSVImport.parseClanTab` detects that shape on re-import and
      skips the row with a warning — a multi-payer expense can't
      round-trip losslessly, same limitation already documented for
      Splitwise/Settle Up imports. **PDF report:** untouched — it's
      built entirely from `Balances`/`Insights` output, never reads
      `payerId` directly, so multi-payer expenses already fold in
      correctly with no changes needed. Tests: kit +11 (`Balances`,
      `Validation`, `Export`, `CSVImport`), worker +6 (a
      `group.test.ts` "multiple payers" block + a `routes.test.ts` HTTP
      round-trip); golden fixtures updated to the new shape (both
      languages read the same files). kit 297 · worker 285 · iOS build
      + `ClanTabTests` green. **Deployed to production** (version
      `0038bc30`) and verified live over HTTPS: a 2-payer expense
      round-trips its `payers` array, balances resolve correctly for
      all three members, removing a *non-primary* payer correctly
      `409`s `MEMBER_IN_USE`, and a mismatched payer total `400`s
      `SPLIT_MISMATCH`.
- [x] **Tax/tip proportional split on itemized expenses.** Done
      2026-09-11. Itemized's most common real complaint — tax/tip split
      evenly instead of by what each person actually ordered — fixed at
      the same point `Validation.itemizedSplit` already turns items
      into exact shares. **Kit:** `itemizedSplit`/`validateItems` gain
      optional `taxMinor`/`tipMinor` params (both default `0`, so every
      existing call site — and every existing itemized expense —
      resolves identically). The surcharge is divided by each member's
      own item subtotal — `floor(surcharge * theirSubtotal /
      itemsGrandTotal)` per member, the whole rounding remainder to
      `remainderRecipient` — the same shape `percentageSplit`/
      `sharesSplit` already use for their own remainders, just applied
      on top of the items pass rather than in place of it.
      `Expense`/`AddExpenseRequest` gain optional `taxMinor`/`tipMinor`
      (nil for every non-itemized expense, or an itemized one with
      neither set). **Worker:** schema **v14** —
      `expenses.tax_minor`/`.tip_minor` (nullable), plain `ALTER TABLE
      ADD COLUMN` (no rebuild). `assertItemsValid` now checks items +
      tax + tip (not items alone) sum to `amountMinor`; the resolved
      `splits` — already proportional, computed client-side — are still
      checked separately by the existing `assertSplitsSum`, so the
      server never needs its own copy of the proportional-distribution
      math. `taxMinor`/`tipMinor` are rejected outside `splitType:
      "itemized"`, same gate as `items`/`shares`. **App:**
      `AddExpenseView`'s itemized flow gained "Tax"/"Tip" amount fields
      below the line items; the existing "must add up to the amount"
      check now covers items + tax + tip together, not items alone.
      Tests: `ValidationTests` +7 (proportional split, zero-tax/tip
      no-op, remainder-to-recipient, sum-check pass/fail, negative
      rejected), `group.test.ts` +5 (incl. the v13→v14 migration walk),
      `routes.test.ts` +1, `ClanTabClientTests` +1. worker 303 · kit
      308. `make check` green. **Deployed to production**
      (version `048292df`) and verified live: a 750/250 (3:1) itemized
      dinner with 60 tax + 40 tip resolves to 825/275 (75/25 of the
      surcharge, not an even 50/50), balances match; items+tax+tip not
      summing to the amount `400`s (`SPLIT_MISMATCH`); `taxMinor` on a
      non-itemized expense `400`s (`BAD_REQUEST`).
- [x] **"What's New" sheet, versioned.** Done 2026-09-11. A new,
      separate `WhatsNewStoring` (`ClanTabKit/Storage/`, mirrors
      `OnboardingStoring`'s shape exactly — `UserDefaultsWhatsNewStore`
      / `InMemoryWhatsNewStore`) tracks the last-seen `CFBundleVersion`
      as an `Int?` (`nil` distinct from `0` — "never recorded", not
      "recorded build 0"); kept separate from `OnboardingStoring`'s own
      one-time "finished the walkthrough" bool rather than folding one
      into the other, since they're independent signals with different
      lifetimes. Pure logic in `Logic/WhatsNew.swift`: a hand-edited
      `WhatsNew.releases: [WhatsNewRelease]` (one entry so far, build 9
      — this round's headline items in user-facing language, same
      "condense the technical writeup" shape as this file's own "Done"
      entries elsewhere); `WhatsNew.shouldShow(lastSeenBuild:
      currentBuild:hasCompletedOnboarding:)` gates on onboarding being
      finished (a fresh install gets onboarding, not a changelog for
      updates it never saw) and at least one release strictly newer
      than `lastSeenBuild`. **App:** `RootView` evaluates this once
      from its existing launch `.task` (deliberately not `init`, which
      SwiftUI can re-run on its own and must never re-trigger a
      side-effecting "mark seen") — a `nil` `lastSeenBuild` (fresh
      install, or one that predates this feature) seeds itself silently
      rather than dumping the whole history on someone who never asked;
      otherwise a new `WhatsNewView` sheet lists the unseen releases,
      newest first, and its `onDismiss` (covers both the "Done" button
      and a swipe-away) advances the stored build. New
      `RootView.currentBuildNumber()` reads `CFBundleVersion` the same
      way `SettingsView`'s existing version label already does. Tests:
      `WhatsNewStoreTests` (4), `WhatsNewTests` (6). worker unaffected ·
      kit 317. `make check` green (app/kit-only — nothing to deploy).
- [x] **Empty-state calls-to-action.** Done 2026-09-10. Group Home's
      "No Expenses Yet" and Recurring Reminders' "Nothing on Repeat Yet"
      `ContentUnavailableView`s switched to the closure form with an
      `actions:` button ("Add an Expense" → opens the Add Expense sheet;
      "New Reminder" → opens the new-reminder sheet). `StartView`'s "No
      groups yet" already pairs its copy with the always-docked
      Create / Join buttons directly below it — left as-is. The
      remaining zero-states (Insights, Recently Deleted, cross-group
      "All Square", filtered no-match) have no meaningful action from
      that state and keep plain copy. `make check` green.
- [x] **Returning-user balance summary.** Done 2026-09-11. Friends
      already shipped by the time this came up, so this goes straight
      to the aggregated cross-group number rather than a per-group
      placeholder — reusing `DashboardTotals.compute` (already built
      for the dashboard's always-on header) against `KnownGroup`'s
      already-synced `myBalances`, no new network call. **Kit:** new
      `ReturnGapStoring` (`Storage/`, mirrors `SyncNudgeStoring`'s
      shape) tracks a *rolling* `lastOpenAt`, advanced every launch —
      unlike `firstLaunchAt`'s one-time stamp, this is what lets a gap
      be detected each time. Pure `Logic/ReturnGap.shouldShowWelcomeBack`
      (3-day threshold; `nil` `lastOpenAt` — fresh install or
      pre-feature — never shows it). **App:** `RootView` evaluates this
      once from the launch `.task` (same shape as the What's New check
      just above it) and always records the open afterward, win or
      lose, so the gap resets the moment the card is shown once — the
      same "recompute, then advance the clock unconditionally" shape
      `BackupNudge` already uses for its own recurring timer. New
      `WelcomeBackCard` (dismissible, `Surface.card` background — unlike
      the nudge cards on Group Home, `StartView` is a plain `ScrollView`
      with no `List` row chrome to lean on) sits above the dashboard's
      existing `DashboardTotalsHeader`, reusing its `line(for:)`
      formatting so the two numbers are guaranteed to agree; renders
      nothing once fully settled up. Tests: `ReturnGapTests` (4),
      `ReturnGapStoreTests` (3). worker unaffected · kit 324. `make
      check` green (app/kit-only — nothing to deploy).
- [x] **One-time contextual coach marks.** Done 2026-09-11. **Kit:**
      new `CoachMarkStoring` (`Storage/`, same UserDefaults-flag idea as
      `OnboardingStoring`, keyed by tip id instead of singular — every
      seen id in one array under one key, so `resetAll()` needs no
      fixed id list to enumerate). **App:** a reusable
      `.coachMark(id:text:edge:)` view modifier (`Components/CoachMark.swift`)
      — a small dismissible callout bubble, shown once per id, ~0.5s
      after the attached view first appears. The store rides in via a
      new `\.coachMarks` environment key (mirrors `\.avatarImageLoader`)
      set once at `ClanTabApp`'s top level, rather than threaded through
      every intermediate view's `init` — a tip can live arbitrarily deep
      in the tree it's meant to explain. Wired to 3 tips (Friends
      already shipped by the time this came up, so all three from the
      original plan apply now): the bubble-view swipe on Group Home, the
      inline add-member button on Add Expense, and the Friends toolbar
      button on `StartView`.
- [x] **Settings → "Show tips again."** Done 2026-09-11, bundled with
      the above. `OnboardingStoring` gained a `reset()` method (only two
      conformers, safe to extend); a new "Show Tips Again" row in
      Settings' "App" section calls `onboarding.reset()` +
      `coachMarks?.resetAll()` together, with a confirmation alert.
      Tests: `CoachMarkStoreTests` (4), `OnboardingStoreTests` +2 (the
      new `reset()`). worker unaffected · kit 329. `make check` green
      (app/kit-only — nothing to deploy).
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

### UX audit, build 9 — flagged + fixes decided 2026-09-11

Full write-up (severity, screenshots, what's already working) at
https://claude.ai/code/artifact/e2a61b0e-2b27-4839-9d77-0527cb9206e5 —
a fresh-install walkthrough (blocked at sign-in, no test account
available) plus a full read of every `Screens/`/`Components/` file.
Bracketed numbers match that doc's own numbering (not priority) and its
severity tag. Every item below now carries a **decided** fix direction —
owner has greenlit major UX/IA changes, so nothing here is gated on a
further product call; CLI should implement, not re-litigate. **Standing
decision, 2026-09-11: DESIGN_BIBLE.md's portfolio-wide consistency rules
(color formula, spring curve, icon/gradient conventions, etc., adopted
2026-09-05–09-07 across the app portfolio) do NOT constrain any fix
below.** ClanTab is optimized on its own merits from here on — deviate
from Bible rules freely wherever it makes this app better; matching
sibling apps in the portfolio is no longer a goal for this app.

- [x] **[6, critical] Group Home toolbar overloaded — fix: replace the
      single-stack nav with a 4-tab bottom bar.** Done 2026-09-12.
      1. New persistent `TabView` in `RootView` — Home (`StartView`,
         unchanged content), Friends, Insights (new — see below), Settings
         (now a tab, not a sheet). Friends/Insights are hidden pre-auth
         (`if auth.isSignedIn`) since neither means anything signed out —
         Home and Settings alone cover that state, matching Settings'
         own existing sign-in-prompt branch. **Bigger architecture change
         than the 3 steps below describe**: group drill-down used to be a
         full `content` swap (`AppRoute` as `RootView`'s one `@State`,
         `.id(route)` forcing a rebuild on every change — the
         "same-switch-case-same-identity" workaround from the 2026-09-09
         group-switching fix). That's gone. `AppRoute` (now just
         `.createGroup`/`.joinGroup`/`.claimMember`/`.group` — `.start`/
         `.friends` don't exist anymore, folded into tab selection) is a
         genuine `NavigationStack(path:)` array pushed under the Home
         tab; a new `MainTab` enum tracks the selected tab separately.
         `NavigationStack`'s own value-based push identity makes two
         different `.group(groupId:)` values naturally distinct
         destinations with fresh `@State` — the old `.id(route)` hack
         is structurally unnecessary now, not just unneeded. Opening a
         group from *any* tab (e.g. a friend's shared group) switches to
         Home and pushes there, so there's exactly one place a group
         screen can live, and the tab bar now stays visible and tappable
         the whole time you're inside a group — a real improvement over
         "one tap away" (`GroupHomeView`'s "Your Groups" button is fully
         gone, not just relocated; the standard back-swipe/chevron
         replaces it, working for free from `NavigationStack`).
      2. `GroupHomeView.toolbar` now carries exactly two items: Add
         Expense (`+`) and one "More" menu (`ellipsis.circle`) —
         `groupSettingsButton` + `shareMenu` + `activityFilterMenu`
         (previously three separate things, one of them a menu
         confusingly iconed/labeled "share" but holding Group Settings
         too) collapsed into one, `Section`-grouped into Filter / Share /
         Data / Settings (a `Menu`'s `Section` renders its own divider —
         no manual `Divider()` needed). Resolves [7] and [30].
      3. The Settings gear and "Your Groups" icon are gone from
         `GroupHomeView`'s toolbar entirely (see the architecture note
         above for how "Your Groups" is really gone, not relocated).
         Resolves [32].
      4. `BalanceHeroView` gained an optional `onSettleUp` closure — a
         "Settle Up" button on the card itself, shown only when
         `viewModel.myBalances` is nonzero (the signed-in member
         specifically has something to settle, not just "the group has
         *a* settlement somewhere," which is what the old Members-list
         row gated on). The separate "Settle Up" row and the "Spending
         Insights" `NavigationLink` are both deleted from Group Home's
         `List` outright. Resolves [12].
      5. New `InsightsHubView` (`Screens/`) is the promoted top-level tab
         — every known group in one list (reusing the emoji/initial
         badge look from `GroupsListView`), tapping one fetches that
         group's state and drills into the existing, unchanged
         `InsightsView`. **Scoped deliberately, not the full "global
         view" a literal reading might imply**: a genuine blended
         cross-group chart needs a backend aggregate endpoint nothing
         today provides — same call already made for the dashboard's
         parked "cross-group spend graphs" item. This hub is "global
         entry point, drills into per-group detail," not a promise of
         blended charts; that stays parked until real usage data
         justifies the backend work. `InsightsView` itself gained a
         `navigationTitleText` (group emoji + name) since it's now
         reached with no enclosing screen already carrying that context
         — it used to just say "Insights" because `GroupHomeView`'s own
         title covered the group name.
      6. `FriendsView`/`SettingsView` lost their "Done" toolbar buttons
         (nothing to dismiss anymore, both are tab roots now);
         `SettingsView.onDone` is repurposed to switch back to the Home
         tab right after a successful account deletion, since there's no
         sheet for it to close. `StartView` lost its Settings/Friends
         toolbar buttons (and the coach mark pointing at the Friends
         one) — both were icon-only affordances the tab bar's own
         labeled items make unnecessary, and a tab bar item doesn't need
         a coach mark the way an icon-only button did.
      7. Not done (out of scope for this item specifically): `WhatsNewView`
         copy and onboarding copy — checked both, neither references the
         old toolbar/menu/tab structure by name, so there was nothing
         stale to fix; a "what's new" entry describing this restructuring
         itself is a separate, deliberate addition once the whole UX-audit
         batch lands, not per-item churn to that shared list.
      **Verified end to end in the Simulator** (a seeded two-member
      group, real dev session): signed-out shows exactly Home + Settings;
      signed-in shows all 4; Friends and the Insights hub (list → drill
      into a real group's charts, correct title, correct data) both
      work; opening a group from Home shows the 2-item toolbar with no
      Settings/Your-Groups icons; the "More" menu's Filter/Share/Data
      sections all render; the Settle Up CTA on the hero opens the
      existing sheet correctly; the tab bar stays visible and the back
      chevron pops correctly while inside a group. `make check` green
      (kit + worker + iOS build/tests, including the pre-existing
      `RootViewDeepLinkTests` — its pure `launchRoute`/`resolveDeepLink`
      functions needed no changes, only how `RootView` consumes their
      output).
- [x] **[7, moderate] "Group Options" menu mixes sharing with data
      admin.** Resolved by [6] step 2 (done 2026-09-12, above) — no
      separate item.
- [x] **[8, moderate] Friends and Settle Across Groups are two
      disconnected screens for the same job.** Done 2026-09-12.
      `PeopleView`/`PersonSettleView` deleted outright — `FriendDetailView`
      now carries everything they did: a "By Group" section (per-group
      amount + direction, fetched via a new `AuthViewModel.peopleAcrossGroups()`
      and matched to this friend by id — `Friend.groups` itself only carries
      group identity, not amounts) and a "Settle All" button
      (`AuthViewModel.settleAll(_:)`, the same bulk-`addSettlement` loop
      `PersonSettleView` used to run). `CrossGroupSummary` (`Components/`)
      extracted from the deleted `PeopleView.summary` static func — the
      one piece of it still needed, now shared by `FriendsView`'s row and
      `FriendDetailView`'s balance line.
      1. Done — see above. `FriendDetailView`'s "Balance" line reads a new
         `currentNet` computed from the freshly-loaded `edges` once
         they're in, not the stale `friend.net` passed in from the list —
         caught live in the Simulator: without this, settling left
         "Balance" saying "Sam owes you ₹300" directly above a "By Group"
         row that had already flipped to "Settled up."
      2. Done — the `NavigationLink("Settle Across Groups")` row removed
         from `SettingsView`'s Account section.
      3. Done — see [34] below.
      **Found and fixed live, not hypothetically:** the original
      `PersonSettleView.settleAll()` this replaces called `addSettlement`
      with neither an access token nor a bearer token and always 403'd —
      apparently never exercised end to end against a group whose token
      wasn't already locally cached, which is exactly the common case for
      a cross-group settle (the edge comes from `/api/auth/people`, not
      from having opened the group). Fixed at the root: `ClanTabClient
      .addSettlement` gained a `bearer` parameter (the `post` helper
      already supported one; the public wrapper just never exposed it),
      and `AuthViewModel.settleAll` passes the session token through it —
      leaning on the server's existing claimed-session dual-auth
      (`requireGroup`, `DESIGN.md` §1/§8) instead of requiring a token
      that was never going to be there. Verified with two real claimed
      identities sharing a group: "Settle All" 403'd before the fix,
      succeeded after, and both "Balance" and "By Group" updated in
      place with no need to leave and reopen the screen.
      **Verified end to end in the Simulator.** `make check` green (kit +
      worker + iOS build/tests, incl. `CrossGroupSummaryTests` — renamed
      from `PeopleViewTests`, same coverage).
- [x] **[9, minor] No persistent navigation anchor.** Resolved by [6]'s
      tab bar (done 2026-09-12, above) — no separate item.
- [x] **[1, critical] No way to preview or try the app before signing
      in.** Done 2026-09-12. New `PreviewGroupHomeView` (`Screens/`) —
      not `GroupHomeView` itself fed fake data (`ClanTabClient` is a
      concrete `actor` and `GroupViewModel` always hits the network in
      `load()`; making that fakeable would mean threading test-only
      seams through production networking for one pre-auth screen), but
      the same row components (`BalanceHeroView`, `MemberBalanceRow`,
      `ActivityRow`) over static sample data instead — visually
      identical, no network. Sample data is internally consistent, not
      just plausible-looking: 3 members and 3 expenses run through the
      real, pure `Balances.compute` so every balance shown actually
      derives from the sample ledger. `StartView`'s welcome hero gained
      a "See how ClanTab works" button opening it as a sheet.
      1. Done — the button + sheet described above.
      2. Every interactive element in the preview (Add Expense, the
         Settle Up CTA, member rows, activity rows) calls one shared
         `prompt()` → an alert ("Sign In to Continue" / "This sample
         group is read-only. Sign in to create or join a real one.")
         with "Sign In" (dismisses the preview, landing back on
         `StartView`'s own sign-in buttons — no separate sign-in sheet
         to hand off to, they're already right there) and "Keep Looking
         Around" (dismisses just the alert).
      3. No literal "nothing is usable until you sign in" copy existed
         to remove — the existing "Sign in to create or join a group."
         line was already accurate and stays; the "wall" was structural
         (no preview affordance existed at all), fixed by adding one.
      **Verified end to end in the Simulator**: the button renders on
      the welcome screen; tapping it opens "🏖️ Goa Trip" with the
      sample banner, a real "You are owed ₹2,100" hero (Alex/Priya/Rohan
      balances matching the sample ledger exactly), 3 members, and a
      dated activity feed; tapping "Settle Up" shows the sign-in alert
      with the exact expected copy; tapping "Sign In" dismisses cleanly
      back to the welcome screen's sign-in buttons. `make check` green
      (kit + worker + iOS build/tests).
- [x] **[2, critical] One error message for every sign-in failure
      mode.** Done 2026-09-11. New `SignInErrorMessage` (`Components/`,
      pure — unit-testable without driving the actual auth UI):
      `forApple`/`forGoogle` both return `nil` on cancel (silent, as
      before), a dedicated "No Apple ID is signed in on this device…"
      message for `ASAuthorizationError.unknown` (Apple's own code for
      "no Apple ID configured" — there isn't a more specific one),
      "No internet connection…" for anything whose error chain bottoms
      out at `NSURLErrorDomain` (walks `NSUnderlyingErrorKey` a few
      levels — Apple's frameworks often wrap a plain `URLError`), and
      the existing generic fallback otherwise. Wired into all three
      Google failure paths (session error, missing callback code, the
      token-exchange `catch`) and Apple's one. Tests:
      `SignInErrorMessageTests` (9) — cancel-is-silent, the Apple
      "unknown code" case, a direct `URLError`, and a wrapped one, for
      both providers. **Not yet verified live** (no Apple ID
      signed in on the Simulator, offline) — folds into the TestFlight
      pass; `make check` green (app build + tests).
- [x] **[3, moderate] Google sign-in's web-chrome break in tone.** Done
      2026-09-12 — kept `ASWebAuthenticationSession` (no SDK, per
      `AGENTS.md`) and softened the jump instead of accepting it as-is.
      `GoogleSignInButton` now has an `isPresenting` state, set the
      instant the button is tapped: the button's own content swaps to a
      spinner + "Continuing to Google…" for 350ms (`Task.sleep`) before
      `presentSession()` builds the PKCE URL and calls `session.start()`,
      so the system sheet's arrival reads as the next step in something
      the app already started, not an unannounced context switch.
      `isPresenting` clears on every terminal path (success, failure,
      cancel, missing-callback). Also set
      `session.prefersEphemeralWebBrowserSession = false` explicitly
      (was implicitly `false` already, but undocumented) — a returning
      user with an existing Google web session skips the credential
      prompt, which is the fast path the audit asked for; there's no
      separate "sheet presentation style" knob `ASWebAuthenticationSession`
      exposes beyond that. Verified live in the Simulator (signed-out
      `StartView`, real network to `accounts.google.com`, cancelled
      before completing so no dev identity was created): screenshots
      show the button's ProgressView + "Continuing to Google…" label
      on screen, then ~1s later the system's "'ClanTab' Wants to Use
      'accounts.google.com' to Sign In" sheet. `make check` green.
- [x] **[4, moderate] Onboarding carousel doesn't preview real UI.** Done
      2026-09-12. `OnboardingView`'s 3 SF Symbol pages replaced with real
      cropped screenshots, added as `OnboardingGroupHome` /
      `OnboardingAddExpense` / `OnboardingSettleUp` image sets
      (`Assets.xcassets`). Captured from the actual running app in the
      Simulator (dev-scaffolding recipe): a real "Goa Trip" group seeded
      through the worker with the same sample members/expenses as
      `PreviewGroupHomeView`'s pre-auth preview (Alex/Priya/Rohan, 3
      expenses), so the two static "here's the app" moments — this
      carousel and item [1]'s preview — tell a consistent story. Each
      screenshot cropped to just the illustrative content (no status bar
      or tab bar) and displayed via `Image(_:).resizable().scaledToFit()`
      in a rounded, bordered, drop-shadowed frame in place of the old SF
      Symbol circle. Page copy unchanged — each still matches its screen
      (Group Home → "A group for every split", Add Expense (filled in
      with a sample "Scuba diving trip" row) → "Add expenses as they
      happen", Settle Up → "Settle up, sorted"). Verified live at both
      the standard Simulator size and on an iPhone SE (3rd generation) —
      375pt wide, the narrowest currently-supported device (iOS 17
      deployment target) — all three pages stay fully legible. `make
      check` green; dev scaffolding (local worker, `AppConfig.apiBaseURL`,
      ATS entry, `#if DEBUG` session block, `NoOpGroupBackup`/in-memory
      token store swaps) fully reverted — `git status` shows only the
      `OnboardingView.swift` change and the three new image sets.
- [x] **[5, minor] No "why sign in" line on the welcome screen.** Done
      2026-09-12 — added "So you don't lose your groups if you switch
      phones." as a second line under `signInSection`'s existing "Sign
      in to create or join a group." in `StartView.swift`, echoing
      `SyncNudgeCard`'s copy ("Sign in with Apple so you don't lose your
      groups if you switch phones.") rather than repeating it verbatim,
      since this screen is provider-neutral (both Apple and Google
      buttons sit below it). Verified live in the Simulator. `make
      check` green.
- [x] **[10, moderate] Group Home fills in piecemeal as it loads — only
      the hero gets a placeholder.** Done 2026-09-12. New
      `GroupHomeSkeleton` enum (`Components/`) — `memberRows()` reuses the
      real `MemberBalanceRow` over three placeholder members (cheaper and
      more future-proof than a parallel row shape; the row doesn't care
      whether its data is real), `activityRows()` is a small generic row
      matching `ActivityRow`'s layout (not the real component — that one
      needs an actual `Expense`/`Settlement` to build an `ActivityItem`
      from, not worth constructing for a placeholder). Both
      `.redacted(reason: .placeholder)`, same modifier the hero already
      used. `GroupHomeView.body`'s `else` branch (state still `nil`) now
      renders "Members"/"Activity" sections full of these instead of
      being simply absent.
      **Verified in the Simulator** — temporarily added a 4s artificial
      delay to `GroupViewModel.refetch()` (reverted after) to actually
      catch the loading frame: the whole screen now shows a coherent
      skeleton (hero + 3 member rows + 3 activity rows, all redacted)
      instead of the hero card floating alone over blank space. `make
      check` green.
- [x] **[11, moderate] Balance-bubble view discoverable only via a
      one-time coach mark.** Done 2026-09-12. A small `chevron.right`
      overlaid at `.bottomTrailing` on the hero `TabView`, next to the
      page dots — `.tertiary` foreground so it reads as a hint, not a
      button (it isn't tappable, just an affordance). Coach mark kept
      as-is alongside it, unchanged. **Verified in the Simulator** on a
      group with the bubble page active: the chevron sits to the right
      of the page dots, persisting regardless of whether the one-time
      coach mark has already fired. `make check` green.
- [x] **[12, minor] "Settle Up" / "Spending Insights" read as data
      rows, not actions.** Resolved by [6] steps 1 and 4 (done
      2026-09-12, above) — no separate item.
- [x] **[13, minor] Undo toast has no countdown before it
      disappears.** Done 2026-09-12 — `GroupHomeView`'s `undoBanner`
      overlay now shows a linear countdown bar under the "Deleted
      "X"… Undo" row: `UndoBanner` gained `createdAt`/`expiresAt`, and
      the bar is a `ProgressView(timerInterval: createdAt...expiresAt,
      countsDown: true)` (`.progressViewStyle(.linear)`, empty labels).
      Ties the visual to wall-clock time rather than a manually-animated
      width, so it can't drift out of sync with a backgrounded/stalled
      view. The toast's own auto-dismiss (`showUndo`'s `Task.sleep`) and
      the bar's `expiresAt` both read a single new `undoDuration`
      constant (`nonisolated`, so the non-actor-isolated `UndoBanner`
      struct can read it) — one 5s value, not two. Verified live:
      swiped-to-delete an expense, watched the bar shrink continuously,
      and the toast auto-dismissed exactly when it hit zero. `make
      check` green.
- [x] **[14, critical] Add Expense has no date field at all.** Done
      2026-09-11. New `@State private var date = Date()` — defaults to
      "now" at sheet-open (adding), overridden to `expense.date` only
      when `editing != nil` (duplicating and a recurring-reminder log
      both keep today's date, same as their already-blank amount — that
      was the existing `editing?.date ?? Date()` behavior at save time,
      now just user-adjustable). A plain `DatePicker("Date", …,
      displayedComponents: .date)` in the "Expense" section, after
      Category; `save()`'s `AddExpenseRequest(date:)` now sends the
      state var instead of the old `editing?.date ?? Date()` literal.
      Checked step 3: the two other `AddExpenseRequest(` call sites
      (`AddExpenseIntent` — Siri, "now" is correct there; `ImportCSVView`
      — supplies the parsed file date) are independent paths, already
      correct, out of scope. Step 4: a non-"now" date already round-trips
      through `ClanTabClientTests` (`Date(timeIntervalSince1970: 0)`) —
      the gap was UI-only, so no new wire-level test was needed; the new
      `_date = State(initialValue: expense.date)` edit-rehydration path
      is UI state (no `AddExpenseViewTests` file exists for any of this
      view's `@State`, same as every other field here). **Verified in
      the Simulator**: Add Expense opens with "Date" defaulted to the
      current day, tapping it opens the native calendar with today
      highlighted. `make check` green (app build + tests).
- [x] **[15, critical] Split-type segmented control gives 5 modes
      equal weight.** Done 2026-09-11. `splitDetail`'s `switch` is
      untouched, as planned — only how `splitType` is *chosen* changed.
      While on Equally/Exact/%, the "Split" section shows the 3-way
      segmented control plus a "More Split Types (Shares, Items)" row;
      the moment `splitType` is Shares or Itemized (picked here, or
      rehydrated editing an existing one) it swaps to a "Split type:
      Shares · Change" summary row instead — a segmented control with no
      matching tag for the current value would've shown nothing
      selected. New `MoreSplitsSheet` (`Components/`) — Shares/Items up
      top, Equally/Exact/Percentages under "Common" with a checkmark on
      the current type, so "Change" from a Shares/Items expense isn't a
      dead end (the checklist's 2-step version left no way back). Every
      seeding side effect (weight-1 shares, the first blank line item)
      moved into one `selectSplitType(_:)` called from both the segmented
      control and the sheet, replacing the old `Picker.onChange`. New
      `SplitType+Label` extension (`shortLabel`/`fullLabel`/`detail`) —
      app-side display copy, kept out of the UI-free kit. **Verified in
      the Simulator** end to end: opened on Equally, picked "More Split
      Types" → sheet showed Shares/Items + Common with the checkmark on
      Equally, picked Shares → sheet closed, summary row read "Split
      type: Shares" with the per-member weight-1 editor seeded below;
      "Change" reopened the sheet with the checkmark now on Shares;
      picked Equally → cleanly back to the 3-way segmented control, no
      dead end. `make check` green (app build + tests).
- [x] **[16, moderate] Multi-payer toggle is styled as a footnote.**
      Done 2026-09-12. `AddExpenseView`'s "Split the cost between payers"
      button switched from `.font(.footnote)` to `.buttonStyle(.bordered)`
      + `.controlSize(.small)` — reads as a real mode switch now. Also
      applied to "More Split Types (Shares, Items)" (`CHECKLIST.md` UX
      audit [15], shipped 2026-09-11) — it used the identical `.footnote`
      styling and would have read as the same fine print the moment this
      item flagged the pattern; leaving one fixed and the other not would
      have been a visible inconsistency introduced in the same batch.
      **Verified in the Simulator**: both buttons render as clear bordered
      pills in the Expense/Split sections. `make check` green.
- [x] **[17, moderate] Add Expense is the single most overloaded screen
      in the app.** Done 2026-09-12.
      1. Unchanged — amount, description, payer, category, split type
         ([15]'s 3-way control) all stay exactly where they were.
      2. Receipts and Comments (already `isEditing`-only) collapsed into
         one `DisclosureGroup("More Details")`, closed by default on a
         fresh expense (`_isShowingMoreDetails = editing != nil`).
         Simplified one clause of the decided rule: "open by default
         when editing... that already has any of that content" would
         need knowing whether an expense already has comments, which
         isn't knowable synchronously — comments load via their own
         `.task` fetch, after the sheet has already rendered. Landed on
         "open whenever editing at all," not "open only if content
         already exists," since the alternative (silently hiding an
         existing comment thread behind a closed disclosure because it
         loaded async after the closed/open decision was already made)
         is worse than showing an empty-but-open section occasionally.
         **Deliberately did not move** the inline "Add Someone" button
         under the Equal split's member list, despite it being named in
         the original wording — moving a person-adding action away from
         the member list you're actively looking at would undercut the
         round-2 item that put it there for exactly the opposite reason
         (add someone without leaving the sheet), and unlike
         Receipts/Comments it's a bare action with no "already has this
         content" state the disclosure's open/closed rule is built
         around.
      3. Not touched here — tracked separately under [19], unstarted.
      Extracted `receiptsRows`/`commentsRows` (plain row content, no
      longer their own `Section`s — a `DisclosureGroup`'s content reads
      oddly with a nested `Section` inside it) with an inline caption
      `Text` standing in for the `Section` header each used to have.
      **Verified in the Simulator**: a fresh Add Expense shows "More
      Details" collapsed right below the Split section; tapping it
      expands to show the Receipts row (with its own "Receipts"
      caption) correctly, Comments correctly absent (not editing).
      `make check` green.
- [x] **[18, minor] Itemized split's per-item participant picker is a
      hidden Menu, one item at a time.** Done 2026-09-12 —
      `AddExpenseView.itemizedSplitRows` replaced the `Menu` with an
      inline horizontally-scrolling row of `MemberAvatar`s per line item:
      full color + a green checkmark badge when included, desaturated +
      dimmed when not, tap to toggle. Who's sharing an item is visible at
      a glance across every row without opening anything, and toggling
      someone is a single tap instead of Menu → scroll → tap → dismiss.
      A red "No one — tap someone above to add them" line still appears
      when a row's participant set is empty, same warning the old Menu
      label used to carry. Also **fixed a latent accessibility bug**
      surfaced while wiring this up: the row's
      `.accessibilityElement(children: .combine)` (present before this
      change) collapsed the whole item — name field, amount field, and
      now three-plus avatar buttons — into one opaque "Line item X"
      VoiceOver stop with no way to reach or activate any child
      individually. Removed it; each field and avatar is its own
      reachable stop now. Removed the now-unused `participantSummary`
      helper. Verified live: added an itemized expense, toggled a member
      off and back on, watched the avatar dim/highlight and the
      checkmark badge appear/disappear each time. `make check` green.
- [x] **[19, minor] Inline `+`/`-` calculator has no affordance before
      you focus the field.** Done 2026-09-12 — went with "keep the
      buttons visible pre-focus": the `+`/`−` buttons next to the amount
      `TextField` no longer live behind `if amountFocused`, so they're
      there from the moment the sheet opens, hinting the field takes an
      expression before anyone's tapped in. Tapping either one now also
      sets `amountFocused = true`, so they're a valid way to *start* an
      expression, not just continue one already being typed — pressing
      "+" on a fresh empty field focuses it and is a no-op otherwise
      (same guard `appendOperator` already had). Verified live: opened
      Add Expense, saw both buttons before touching the field, tapped
      "+" cold and typed "12 + 8" straight through. `make check` green.
- [x] **[20, critical] Group Settings mixes routine and irreversible
      actions with identical visual weight.** Done 2026-09-11.
      Name/currency/emoji/cover/default-split/members/UPI/"Report a
      Problem" stay the normal `Section`s at the top, untouched.
      Regenerate Link, Archive/Unarchive, and Leave This Group — three
      separate `Section`s before, each with its own footer — collapsed
      into one "Danger Zone" `Section` with a red-tinted header; new
      `dangerZoneRow(icon:title:caption:isLoading:action:)` gives each
      row a leading red SF Symbol (rotate-arrows / archivebox /
      leave-icon) plus its title and consequence line stacked
      underneath, replacing the old per-`Section` footer. Archive stays
      in the grouping per the decided spec even though it's reversible
      — the row's own caption still says so. Step 3: `confirmingLeave`/
      `confirmingRegenerate` fire from the same closures as before,
      untouched. **Verified in the Simulator**: scrolled to the bottom
      of Group Settings — red "Danger Zone" header, all three rows with
      warning icons and their consequence text rendering correctly below
      the routine sections. `make check` green (app build + tests).
- [x] **[21, moderate] Remove Member fails silently after the swipe.**
      Done 2026-09-12.
      1. New `GroupSettingsView.isRemovable(_:myMemberId:expenses:settlements:)`
         (`static`, free of `self` — testable without standing up the
         view) mirrors the server's own `removeMember` rule exactly: not
         the signed-in member's own claim, not a payer or split
         participant on any expense (including a non-primary multi-payer
         slot), not a party to any settlement. The "Remove" swipe action
         is omitted (not shown disabled — SwiftUI has no good "disabled
         swipe action" affordance) when it's already known to fail.
         Tests: `GroupSettingsViewTests` (7 cases) — self-claim, payer,
         split participant, non-primary payer, settlement party, and a
         sanity check that only *other* members' activity doesn't
         false-positive.
      2. Turned out to already be true on inspection: `remove(_:)`'s
         `catch { errorMessage = friendlyMessage(for: error) }` already
         surfaces the server's own specific message verbatim
         (`ClanTabClientError.server(_, message)` → that exact string) —
         not a generic fallback. The one case client-side checks *can't*
         cover — a member claimed by a *different* identity, since
         `Member` deliberately never exposes that (`DESIGN.md` §8) —
         already gets its specific reason ("This member is linked to an
         account...") this way.
      **Also found and fixed while testing this, not part of the
      original scope but directly in its way:** reaching "Group
      Settings" at all now took a scroll to the bottom of the "More"
      menu's ~11 rows (Filter, 3× Share, 6× Data, then finally
      Settings) — the same "the thing you need is buried" complaint [6]
      was meant to fix, one level down. Reordered so "Settings" leads
      the menu instead of trailing it.
      `make check` green (kit + worker + iOS build/tests). **Not fully
      verified live**: confirmed the Members section and the reordered
      menu render correctly in the Simulator, but idb couldn't trigger
      the actual swipe-to-reveal gesture on a member row (same class of
      limitation as its trouble with the iOS 26 `.searchable` bar and
      native `Menu` popovers noted elsewhere) — the omission logic
      itself is covered by the 7 unit tests instead.
- [x] **[22, minor] Destructive settings rows don't look destructive.**
      Resolved by [20] step 2 (done 2026-09-11, above) — no separate item.
- [x] **[23, critical] "Mark as Paid" has no confirmation.** Done
      2026-09-11. `settlementRow`'s button now sets a new
      `@State confirmingSettlement: SimplifiedSettlement?` instead of
      calling `markPaid` directly; a `confirmationDialog` (same
      `presenting:`-driven pattern as `GroupSettingsView`'s Leave/
      Regenerate) spells out the payer, payee, and amount plus "ClanTab
      just records this as settled — it doesn't move any money," with
      "Mark as Paid" / "Cancel" actions. **Verified in the Simulator**
      end to end against a real seeded balance: tapping "Mark as Paid"
      showed the dialog with the exact expected copy ("Sam pays Dev
      ₹500. ClanTab just records this as settled…"); dismissing it
      without confirming left the settlement un-recorded (the row still
      read unpaid) — confirms both the copy and that nothing fires until
      the second tap. `make check` green (app build + tests).
- [x] **[24, minor] UPI pay links are invisible until someone finds
      the field.** Done 2026-09-12 — a one-time dismissible row in
      `SettleUpView`, right below the settlement list: "Get paid via
      UPI — Add your UPI ID under Group Settings → My UPI ID, so
      whoever pays you here gets a one-tap link." Shown only when the
      signed-in member is owed money in this plan (`toId` on some
      settlement), in INR specifically (UPI's only currency), and
      hasn't set their own `upiVpa` — the exact case where the existing
      "Pay via UPI" link (`upiPayURL(for:)`) never has anything to show
      them, so they'd otherwise never learn the field exists. Reuses
      `\.coachMarks` (`hasSeen`/`markSeen`) for the one-time-per-device
      bookkeeping, same store the floating coach-mark bubbles use, but
      rendered as a plain dismissible `Section` row instead of an
      anchored overlay — Group Settings is a different screen, so
      there's nothing on *this* screen to visually point at. Extracted
      into its own `upiNudgeSection` computed property — folding the
      `Section` straight into `body`'s `List` hit the type-checker
      complexity limit, a recurring pattern in this codebase (see
      `GroupSettingsView`'s `joinCodeSection`). Verified live: seeded a
      real INR group where the signed-in member is owed money with no
      UPI ID set, saw the nudge, dismissed it, reopened Settle Up and
      confirmed it stayed dismissed. `make check` green.
- [x] **[25, critical] Claiming a member identity is one confirmation
      tap, no verification.** Done 2026-09-11. Step 1 turned out to
      already be true, not a gap: `ClaimMemberView`'s picker only ever
      renders whatever `GET /api/groups/:id/claimable` returns, and
      `GroupDO.claimable()` (`worker/src/group-do.ts`) already filters
      to `identity_sub IS NULL` server-side — an already-claimed member
      was never offered as an option, on this or any other screen (the
      audit's own methodology was a code read blocked at sign-in, so it
      read `ClaimMemberView.swift` alone without the worker route behind
      it). No code change for step 1. Step 2: reworded the
      `confirmationDialog` — title "You're \(name)?", body now says
      plainly what claiming does ("links their whole expense history and
      balance to your sign-in, visible on every device you sign in on")
      and is honest about the escape hatch: there's no per-member undo,
      only "delete your account in Settings and start over" (checked
      first — there is no unclaim/reclaim path anywhere in the app, so
      the fix doesn't claim one that doesn't exist). **Not yet verified
      live** — exercising the actual claim flow needs a second signed-in
      identity claiming an unclaimed member, the same "needs a real
      Bearer session" gap already called out for the Friends work above;
      folds into the TestFlight pass. `make check` green (app build +
      tests, confirmationDialog code path matches the already-verified
      pattern in `GroupSettingsView`/`SettleUpView` above).
- [x] **[26, moderate] Join code is shown exactly once and never
      again.** Done 2026-09-12. Step 1 turned out unnecessary on
      inspection: `GroupSummary.joinCode` is a required field on every
      `GroupStateResponse`, not just `CreateGroupResponse` — the server
      already returns the live code on every fetch, and `GroupHomeView`'s
      "More" menu already had a `ShareLink("Share Join Code (...)")`
      reading it live (`Group Home dashboard`/`state.group.joinCode`).
      Nothing to persist client-side that the server doesn't already
      hand back for free. Step 2's actual gap: `GroupSettingsView` itself
      never showed it. New "Join Code" section (monospaced, selectable,
      with a copy button — same shape as `MemberProfileView`'s UPI ID
      row) added there, reading `state.group.joinCode` live like the
      Share menu already does.
      **Compiler note**: the extracted section had to become a whole
      `joinCodeSection` computed var, not just its inner row — adding it
      inline pushed `GroupSettingsView.body` (already a large `Form`)
      over the type checker's complexity ceiling ("unable to type-check
      this expression in reasonable time"), the same reason this file
      already extracts `coverImageSection`/`defaultSplitSection`/etc.
      **Verified in the Simulator**: opened Group Settings on a real
      seeded group — "Join Code" shows the correct live code
      (`QSQN3M`), matching what `CreateGroupResponse` returned at
      creation. `make check` green (kit + worker + iOS build/tests).
- [x] **[27, moderate] Insights charts give no cue that they're
      touchable.** Done 2026-09-12. One `.coachMark(id:
      "insights.chartsAreInteractive", text: "Tap or drag a chart to see
      exact values.")` attached to `overTimeChart` — the first chart on
      screen, so whichever one someone reaches first already explains
      the shared scrub gesture; not one per chart (`memberDonut`/
      `categoryPie` weren't touched, matching "a one-time coach mark,"
      singular, in the decided fix). Only reachable inside
      `InsightsView`'s non-empty branch, so it's automatically gated on
      "with expenses present" for free. **Verified in the Simulator**
      against a real group with expenses: the bubble appears over the
      Over Time chart on first visit with the exact expected text.
      `make check` green.
- [x] **[28, minor] Member-tap-to-filter instructions sit below the
      charts they explain.** Done 2026-09-12 — `InsightsView`'s "By
      member" `Section` moved "Tap a member to filter every chart to
      just their share." out of the section `footer:` (which trailed
      the donut and every member row) into the first line of the
      section's own content, right under the "By member" header and
      above the donut. Same `byMember.count > 1` gate as before — no
      point explaining a filter a single-member group can't use.
      Verified live: opened Insights on a real seeded group, scrolled
      to "By member", saw the hint immediately under the header, above
      the donut and rows. `make check` green.
- [x] **[29, critical] CSV import has no duplicate-import guard.** Done
      2026-09-12 — see "De-dupe guard on CSV import" in the Feature
      backlog section below for the real fix (`CSVDuplicateCheck`).
- [x] **[30, minor] "Group Options" menu has almost no grouping.**
      Resolved by [6] step 2 (done 2026-09-12, above) — no separate item.
- [x] **[31, moderate] Welcome-back card and the balance header repeat
      the same totals back to back.** Done 2026-09-12. New
      `StartView.isShowingWelcomeBackTotals(showWelcomeBack:groups:)`
      (`static`, testable without standing up the view, same pattern as
      `GroupSettingsView.isRemovable`) — true only when the welcome-back
      card is actually about to render a number, not just whenever it's
      the "eligible" launch. That distinction matters: both
      `WelcomeBackCard` and `DashboardTotalsHeader` already render
      nothing at all once every currency is settled (`totals.isEmpty`),
      so naively hiding the header whenever `showWelcomeBack` is true
      would leave a fully-settled returning user with *no* totals
      display at all, not just a de-duplicated one.
      `DashboardTotalsHeader` is now wrapped in
      `if !isShowingWelcomeBackTotals`. Tests: `StartViewTests` (3) — the
      real-duplicate case, `showWelcomeBack` false, and the settled-but-
      eligible case that must *not* hide the header. `make check` green.
      Not separately verified live in the Simulator — reproducing the
      real 3-day-gap trigger condition wasn't worth forcing; the
      predicate is a pure, fully-tested boolean over already-verified
      components (`WelcomeBackCard`/`DashboardTotalsHeader` both shipped
      2026-09-11 with their own Simulator passes).
- [x] **[32, minor] Duplicate of [6]** — resolved by [6] step 3 (done
      2026-09-12, above), not a separate fix.
- [x] **[33, minor] Generic errors give no retry or diagnosis.** Done
      2026-09-12.
      1. `friendlyMessage(for:)` (`ClientErrorMessage.swift`) now checks
         for a transport-level `URLError` first — walking
         `NSUnderlyingErrorKey` a few levels down, the same technique
         `SignInErrorMessage.isOffline` already used for the sign-in
         buttons (kept as an independent copy — different callers,
         different test files) — before it ever reaches
         `ClanTabClientError`'s generic `.invalidResponse`/
         `.decodingFailed` case. A `URLError` never actually reaches
         `ClanTabClient` at all (it's thrown straight out of
         `URLSession` by `transport.send`, uncaught), so it used to fall
         all the way to `error.localizedDescription` — inconsistent
         tone, and indistinguishable from a real server/decoding
         failure. Now: "No internet connection. Check your connection
         and try again." specifically. 6 new unit tests
         (`ClientErrorMessageTests`) — direct offline, timeout, wrapped
         offline, and confirming `ClanTabClientError`/`ValidationError`
         cases are unaffected.
      2. Retry affordance on `AddExpenseView` and `SettleUpView`
         specifically (not app-wide, per the decided scope) — a "Retry"
         `Button` right in the error `Section`, next to the message.
         `AddExpenseView`'s just re-runs `save()`, since the whole form
         is still right there. `SettleUpView`'s needed a new
         `failedSettlement` state (set alongside `errorMessage` in
         `markPaid`'s `catch`, cleared at the start of the next attempt)
         so "Retry" resubmits the *same* settlement without the user
         having to scroll back and find its row again.
      Verified live end-to-end: filled out Add Expense, killed the local
      worker to force a real transport failure, submitted — got "No
      internet connection…" with "Retry" right there; restarted the
      worker, tapped "Retry", the same request went through
      (`POST .../expenses 201 Created` in the worker log) and the sheet
      dismissed normally. `make check` green (kit + worker + iOS
      build/tests, new tests included).
- [x] **[34, minor] What's New oversells Friends/1:1 as one feature.**
      Done 2026-09-12, alongside [8] above. The build-9 release's Friends
      bullet reworded from "see everyone you split with across every
      group, and settle up 1:1 without a shared group" to "one screen for
      everyone you split with — see the full breakdown, settle up, and
      start a 1:1 tab with no shared group needed," matching the now-true
      one-screen experience [8] shipped.

### UI audit, fresh eyes pass — all fixable items done 2026-09-12

Full write-up (severity, screenshots, what's already working) at
https://claude.ai/code/artifact/830354ef-bdf4-4998-8c25-fe3436df765a —
a live walkthrough of Home, Add Expense, Settle Up, Group Settings,
Insights, Friends, and Settings against a real seeded 5-member,
two-currency group, at both the default text size and the largest
accessibility text size iOS offers. Unlike the "UX audit, build 9"
section above (structure/flow/IA), this pass is about whether the
screens *render correctly* at the sizes people actually use them at.

- [x] **[1, critical] Compound labels truncate instead of wrapping at
      accessibility text sizes.** Done 2026-09-12. One root cause behind
      five separate symptoms: `BalanceHeroView`'s "You are owed" label
      clipped to "You are o…", `ActivityRow`'s "category · date" line
      truncated both halves ("Shop…", "11 Sep…"), the amount `TextField`
      on Edit Expense rendered its own value as a bare "…", the currency
      `Picker` lost its label entirely (just a chevron, no code), and
      "Paid by" wrapped a name mid-letter ("Meer" / "a") for lack of
      column width. Fixes: `GroupHomeView`'s hero/bubble `TabView` height
      was a bare `250` regardless of content — now `@ScaledMetric
      (relativeTo: .body)`, so it grows with text size instead of
      clipping the hero's own labels. `BalanceHeroView`'s three status
      labels get `.fixedSize(horizontal: false, vertical: true)`.
      `ActivityRow.metadataLine` and `AddExpenseView`'s amount row /
      "Paid by" row all gained the same `dynamicTypeSize.isAccessibilitySize`
      branch already used elsewhere in the codebase (`SettleUpView.
      settlementRow`) — stack vertically instead of competing for one
      row's width. Verified live at Accessibility XXXL against a real
      seeded expense: "You are owed" and "Lodging" / "8 September 2026"
      both wrap in full, the currency picker shows "INR"/"USD" clearly,
      and an edited expense's amount reads "5000.00" in full, not "…".
      `make check` green.
- [x] **[2, critical] Coach-mark bubbles have no size ceiling — one
      measured 563pt tall and fully covered the balance card.** Done
      2026-09-12. `CoachMarkBubble` now caps its own text scaling at
      `.dynamicTypeSize(...DynamicTypeSize.accessibility1)` — a
      supplementary one-time hint doesn't need to track the full
      accessibility range the way primary content must. Separately,
      `CoachMarkModifier` swapped its fixed `-44`/`+44` pixel offset for
      an `alignmentGuide` that measures the bubble's own height each
      time (`d[.bottom] + gap` / `d[.top] - gap`) — the old fixed offset
      only cleared the anchor for whatever height it was tuned against,
      so even a 2-3 line bubble at the *default* text size spilled down
      over the "Add Someone" button on Add Expense and the row above it.
      Verified live at Accessibility XXXL: the Home hero card's "Swipe
      for a bubble view…" tip no longer covers the balance amount or
      Settle Up button — it sits below the (now correctly-sized) card,
      same as at any other text size. `make check` green.
- [x] **[3, moderate] Two different treatments for the same class of
      destructive action.** Done 2026-09-12 — Group Settings' "Danger
      Zone" (red section header, icon per row, a line of consequence
      under each) was the pattern that worked; `SettingsView`'s "Delete
      Account" used to be red text one row below "Sign Out" with no
      separating header — the least emphasis of any destructive action
      in the app, despite being the most irreversible one. The row
      itself (icon, red title, consequence line) was duplicated
      per-screen code in `GroupSettingsView`; extracted into a shared
      `DangerZoneRow` component so both screens draw from one
      definition, and gave `SettingsView` a second, `DangerZoneRow`-only
      "Danger Zone" section (`person.crop.circle.badge.xmark`) below its
      neutral "Account" section, moving the consequence text off the
      section footer and onto the row itself to match. Verified live:
      Settings now shows a red "Danger Zone" header with the same
      icon+title+caption row shape as Group Settings' Regenerate/Archive/
      Leave trio, and that trio itself is pixel-identical post-refactor.
      `make check` green.
- [x] **[4, moderate] The Friends tab has no explanation of what it's
      for.** Done 2026-09-12 — with 0-1 entries the screen used to be a
      single row (or nothing) followed by a full screen of blank space,
      unlike every other lightly-populated screen in the app ("No
      Expenses Yet," the CSV import picker), which pairs empty space
      with a sentence of context. The zero-friends case already had one
      (`ContentUnavailableView`'s description) — the gap was everything
      above zero. Wrapped the populated list in a `Section` with a
      footer explaining what counts as a friend and what tapping one
      does; a footer works the same whether there's 1 row or 20, so it's
      shown regardless of count rather than only while sparse. Verified
      live with exactly one claimed friend: the row is followed by the
      new footer, then genuine blank space that now reads as "that's
      everything," not as an unfinished screen. `make check` green.
- [ ] **[5, moderate, unconfirmed] The group's "…" menu runs to 11 rows
      across 4 sections — confirm every row is reachable on a real
      device.** `~2k tokens` (CLI, investigation) — decided: simulator
      automation couldn't reliably activate a row it had to scroll a
      native `Menu` to reach (a tap at the row's own coordinates
      dismissed the menu instead), which may be purely an automation
      limitation rather than something a real finger or VoiceOver hits.
      Confirm on a real device before deciding whether any row needs to
      move (e.g. into Group Settings, which already holds equivalent
      settings-shaped actions). Deeper-pass update 2026-09-12: reproduced
      twice more, on two different rows ("Recently Deleted",
      "Recurring Reminders"), each time at freshly re-queried,
      confirmed-correct accessibility-tree coordinates — while other
      rows in the same menu ("Filter Activity") activated fine at their
      own coordinates. That pattern (works near the top, fails further
      down the same menu) looks less like a one-off automation fluke and
      more like something worth an actual finger test before relying on
      simulator results alone either way.
- [x] **[6, minor] Full-width, left-aligned capsule buttons read as
      list rows wearing a button's clothes.** Done 2026-09-12 —
      "Split the cost between payers" and "More Split Types (Shares,
      Items)" on Add Expense are `.buttonStyle(.bordered)`, which a List
      row stretches to the full row width with left-aligned text — a
      shape that reads naturally hugging short, centered content, less
      so stretched edge-to-edge (and visibly over-rounded once 2-line
      text forced a taller capsule at large text sizes). Kept the real
      button styling (`CHECKLIST.md` UX audit [16] deliberately made
      these look like buttons, not fine print) and fixed the shape
      instead of dropping it: wrapped each in `HStack { Spacer(); ...;
      Spacer() }` so the capsule hugs its own text and centers in the
      row rather than stretching to fill it. Verified live at both
      default and accessibility-XXXL text sizes: both capsules now hug
      their text and center, including the 4-line-wrapped case that used
      to look most stretched. `make check` green.
- [x] **[7, minor] "Report a Problem"'s subtitle explains itself from
      the developer's side.** Done 2026-09-12 — "Apple requires this for
      apps with shared user-generated content" was a compliance
      rationale, not a reason a person would tap the row, unlike every
      other row in that section, which says what happens, not why the
      row exists. Reworded to "Report this group if its name or content
      is inappropriate." Verified live in Group Settings. `make check`
      green.
- [x] **[8, minor] A member owing in one currency and owed in another
      loses the at-a-glance color read.** Investigated 2026-09-12 — not
      a bug, an accepted trade-off. Vikram's row showing both a red
      `₹1,270` and a green `$22.50` is correct, and the VoiceOver label
      already composes them into one sentence ("Vikram owes ₹1,270, and
      is owed $22.50") — the cost of genuinely supporting multi-currency
      groups, not something to fix.

**Deeper pass, 2026-09-12** — extended the above after fixing [1] and
[2], covering what the first pass skipped: dark mode (Home, Add
Expense, Settle Up, both Insights charts — all clean, good contrast,
no issues); extra-small Dynamic Type (Insights list, Insights detail,
Add Expense — all render tightly with no wasted space or truncation,
as expected for a design already built to survive the much harder
accessibility-XXXL end); accessibility-tree traversal order on Add
Expense and Group Home (both read top-to-bottom in visual order — no
element ordering surprises, though this checks tree order, not a full
VoiceOver swipe-gesture pass); and previously-unvisited screens
(CreateGroupView, FriendDetailView, MemberProfileView for both self and
another member, Filter Activity, Group Settings' Members section — no
new issues, though MemberProfileView-for-self is sparse enough it may
be worth a future look for anything worth surfacing there). The one
substantive result was strengthening [5] above with a second and third
reproduction. No new bugs found; nothing here changed any code beyond
[1] and [2], already recorded above. Screens still not exercised by
automation: RecentlyDeletedView/RecurringRemindersView content (blocked
by [5]'s own menu-reachability issue), ReportContentView, the category
picker, multi-payer entry, the CSV import screen itself, and the
emoji/cover-image pickers.

### Rescan for new findings — 2 real bugs found and fixed, 2026-09-13

Asked to scan the app again after the fresh-eyes audit above was fully
closed out, this time reaching for the screens that audit's own
"still not exercised" note flagged. Set up a 3-member group with real
expenses to walk through the category picker, the multi-payer toggle,
split-type switching, and the onboarding carousel — all clean, no new
UI findings. But the same session surfaced two real, unrelated bugs one
level down from the UI, both while checking whether a change one
member makes shows up for another member watching the same group live:

- [x] **[1, moderate] `fetchGroupState`'s foreground poll could get
      stuck on stale, cached data indefinitely.** Done 2026-09-13 —
      `URLSessionTransport` sent every request through `URLSession
      .shared` with the default `.useProtocolCachePolicy`, and the
      worker sends no `Cache-Control` header on any response. Caught
      live: added an expense to a group already open in the simulator,
      and the foreground poll kept returning `cache_hit=true` in
      Console for 5+ minutes straight — the exact same byte count every
      time, the group's state from *before* the expense, never once
      reaching the network again. This is the ordinary "someone else
      adds an expense while you're looking at this screen" case, not an
      edge case — once one `GET` response for a group gets cached, nothing
      short of an app relaunch would ever show that group's live state
      again. Fixed with one line at the transport layer:
      `request.cachePolicy = .reloadIgnoringLocalCacheData` before every
      request, so a poll always means a real network round-trip, matching
      the sync model's own assumption (`DESIGN.md` §7) that a poll
      reflects the server's current state. Verified live end-to-end:
      posted a second member's expense against a group already open in
      the app, and it appeared on its own within one poll cycle, no
      interaction needed.
- [x] **[2, moderate] A malformed expense `date` can permanently break
      a group for everyone in it.** Done 2026-09-13 — found by accident
      chasing [1]: a couple of test expenses created with a bare
      `"date": "2026-09-10"` (no time component) were accepted by the
      worker's `requireString` check, but the app's `JSONDecoder
      .dateDecodingStrategy = .iso8601` (`ISO8601DateFormatter`'s
      default options) requires a full date-time and rejects a bare
      date. The real app's own UI never produces a bare date, so this
      couldn't happen through normal use — but the worker had no
      defense against a bad one arriving some other way (a bug in a
      future app version, a hand-built request, a future import path).
      Once stored, the effect is severe: *every* member's next
      `fetchGroupState` for that group fails to decode the whole
      response, and there's no way to fix it through the app either,
      since loading the edit screen to fix the bad expense needs that
      same decode to succeed first — the group is stuck for good.
      Added `requireISODate` (`worker/src/lib/parse.ts`) — same shape
      as `requireString`, plus a regex + parse check for a full ISO
      8601 date-time — and use it for the expense `date` field (shared
      by both add and update, `parseExpenseBody`). A new worker test
      confirms a bare date is now rejected with `BAD_REQUEST` instead
      of silently stored. `make check` green (345 ClanTabKit tests, 304
      worker tests).

Splitwise/Tricount/Settle Up/Splid, primary sources only:

- [x] **De-dupe guard on CSV import.** Done 2026-09-12 — found 2026-09-08
      while fixing Settle Up import (`docs/csv-import-formats.md`). Every
      imported row gets a fresh client-generated id, by design, so a
      partial import is safe to retry — but that also means importing the
      *same* file twice (or the same trip exported from two apps by two
      group members) silently posted every row again.
      **Interim done 2026-09-09:** `ImportCSVView`'s review screen showed
      an amber caution above the Import button — a re-import was no longer
      silent, though it wasn't blocked.
      **The real fix, done now:** new `CSVDuplicateCheck` (`ClanTabKit`,
      pure) implements the "same expense" definition this item always
      wanted — same currency, amount within a small tolerance (another
      app's own remainder-distribution can land a paisa/cent off what
      ClanTab would compute, same rounding slack `CSVImport.parseSettleUp`
      already allows), the same resolved payer, a matching description
      (case/whitespace-insensitive), and within 36h of the same moment
      (wide enough to absorb a source app's own timezone-naive export
      landing on the "wrong" side of midnight UTC) — checked against the
      group's active (non-trashed) ledger. Same shape for a settlement,
      minus the description signal. 14 new swift-testing cases covering
      every branch (exact match, each field's mismatch, both tolerance
      boundaries, soft-deleted rows excluded, both `DraftExpense`/
      `DraftSettlement` convenience wrappers).
      `ImportCSVView` now takes the group's `existingExpenses`/
      `existingSettlements` (from `GroupHomeView`'s already-loaded
      `viewModel.state`) and flags every likely-duplicate row on the
      review screen — a new "N rows already in this group" section
      listing them, with a "Skip likely duplicates" toggle (on by
      default, the safer default for a guard whose whole point is
      stopping an accidental double-post) that actually excludes them
      from what gets posted, not just from what's shown. A row whose
      payer is being created fresh can never be flagged — that member
      doesn't exist in the ledger yet to match against. The finished
      screen now notes how many were skipped. The amber caution stays,
      reworded to describe what the check catches and its real limit
      (a differently-worded description from the source app can still
      slip through) rather than claiming there's no guard at all.
      Extracted the new review-screen `Section`s into their own computed
      functions (`duplicatesSection`/`stillOnlyBestEffortSection`) —
      folding them straight into `review`'s `Form` hit the same
      type-checker complexity ceiling this codebase keeps running into
      (see `GroupSettingsView.joinCodeSection`, `SettleUpView.upiNudgeSection`).
      **Verification**: the detection logic itself is exhaustively covered
      by the 14 kit tests above and the whole thing builds/type-checks
      cleanly end to end (`make check` green: kit + worker + iOS build/
      tests). The review screen's live behavior (opening a real duplicate
      file twice and watching the flagged section/toggle) wasn't
      independently re-verified in the Simulator this session — reaching
      "Import CSV" requires scrolling a native `Menu` popover to an
      off-screen item, the same idb limitation already documented for
      item [21]'s swipe-to-remove verification (a synthetic tap at the
      item's reported coordinates dismissed the menu instead of
      activating it, confirmed by checking the worker's request log
      showed nothing fired).
- [x] **Balance bubble/circle-pack view.** Done 2026-09-09. `CirclePack`
      in the kit (`Logic/CirclePack.swift`) — pure, view-free: `(id, weight)`
      pairs → `[PackedCircle]` (centre + radius) laid out by an Archimedean
      spiral, heaviest item centred, the rest dropped at the first
      non-overlapping spot, ties broken by `id` (so it's deterministic), then
      the whole cluster uniformly scaled down to fit the target box.
      Radius scales by `sqrt(weight/maxWeight)` so **area** tracks the
      balance; a zero balance becomes a `minRadius` dot. 6 swift-testing
      cases (empty/degenerate, single-centred, sqrt radii, fits-box,
      no-overlap, order-independence). `BalanceBubbleView` (App) renders it
      with `GeometryReader` + positioned `Circle`s: owed = washed fill +
      accent ring, owing = solid accent, settled = grey dot; initials at
      r≥20, amount at r≥36; per-member `MemberColor`, one currency only (the
      one with the largest-magnitude balance — never blended). Wired as a
      second **swipeable** Group Home page inside a `TabView(.page)` next to
      the balance hero, shown only once ≥2 members have a nonzero balance in
      the dominant currency (`showsBubblePage`). Kit-only logic, no worker /
      DESIGN.md contract change. Verified in the Simulator on a seeded
      5-member group (screenshot).
- [x] **Splid import — investigated 2026-09-10, not actionable as scoped.**
      The item assumed Splid has a CSV export sharing Settle Up's header
      shape, so the work was "get a sample, check `parseSettleUp` against
      it." That premise was wrong — it came from `Future.csv` being taken
      for a Splid file before it was confirmed to be Settle Up. What's
      actually true (sources in `docs/csv-import-formats.md`):
      - **Splid has no CSV export.** Its App Store listing says "Download
        summaries as PDF or Excel\* files / \*Excel export available via
        in-app purchase" (Splid Plus, ~$3.99). PDF free, spreadsheet paid,
        CSV never — on any platform.
      - The `.xlsx` layout is undocumented and behind the paywall; `.xlsx`
        is zip-of-XML that `CSVImport.decode` can't read at all. A real
        importer here needs an XLSX reader in the kit first (none exists),
        then a parser against an unknown sheet layout.
      - There's a reverse-engineered JSON API (`splid-js`, active) with
        invite-code access and a full model — but it's unofficial with no
        documented ToS, the same "don't build against a scraped backend"
        case as the Tricount tool.
      No `parseSettleUp` change, no fixture (nothing to fixture). If Splid
      import is ever genuinely demanded it's a from-scratch effort down one
      of those two roads — each far larger than the ~15k this item assumed,
      each gated on inputs we don't have. Same call as Tricount: not worth
      starting without a demand signal.
- [x] **Tricount import — investigated 2026-09-10, leave unbuilt (no demand
      signal).** Full findings + sources in `docs/csv-import-formats.md`.
      - **No self-serve file export.** Tricount's FAQ confirms CSV/PDF export
        was removed as a deprecated Premium feature; you now email
        `support@bunq.com` and they send CSV or ODF. The current
        support-issued CSV schema is unseen (nobody's posted one), and a
        file importer for it only helps someone who already emailed support
        — not anyone switching in from Tricount going forward.
      - **The realistic path is the public share link, not a file.** Every
        tricount can generate a `tricount.com/...` link that renders the
        whole ledger in a browser (no app, no sign-up) — a feature Tricount
        promotes. Its backend returns rich JSON (payers, per-member share +
        allocation type, multi-currency, category, timestamp); third-party
        tools (marcomc/tricount-exporter et al.) already consume it. The
        endpoint is undocumented with no ToS blessing, but the capability
        itself is intentional — lower risk than Splid's reverse-engineered
        sync protocol.
      - **If ever prioritized:** a share-link import (worker route: link/ID
        → fetch public JSON → transform to drafts), ~40–60k, against an
        undocumented endpoint. Tricount's genuine multi-payer expenses can't
        round-trip through our single-payer `DraftExpense` (same limit
        `parseSplitwise` documents — skip-with-warning). The
        `Paid by X / Paid for X` CSV that exporter tools normalize to is
        *their* invented shape, not Tricount's — not worth targeting.
      - No `CSVImport` change; header detection already can't misfire on any
        of these shapes (falls through to `unrecognizedFormat`). Same call
        as Splid: not worth starting without demand.
- [x] **Itemized expense entry, manual.** Done 2026-09-10. A 4th
      `SplitType.itemized` alongside equal/exact/percentage. **Model
      (`ClanTabKit`):** `LineItem { id, name, amountMinor, participantIds }`
      (`Model/LineItem.swift`); `Expense.items: [LineItem]?` (nil for every
      other split type). **Resolution:** `Validation.itemizedSplit` — each
      item split equally among its own participants (`equalSplit`'s exact
      remainder rule, leftover to the payer when they share the item, else
      the item's first participant), summed per member; `Validation.validateItems`
      checks ≥1 item, each a positive amount with ≥1 real member, and the
      items summing exactly to `amountMinor` (no separate tax/tip bucket — a
      shared surcharge is its own line). Client resolves items → exact
      `splits` before dispatch exactly as `percentage` does; the items ride
      along and are stored for display / re-edit. 13 kit test cases incl.
      fuzz. **Worker:** schema **v8** — `expenses.split_type` CHECK widened
      + `expenses.items` (nullable JSON) added, one `expenses`-table rebuild
      (same dance as v2); `assertItemsValid`; `parseExpenseBody` enforces
      items ⟺ splitType itemized; migration + 7 route/DO test cases.
      **App:** `AddExpenseView` "Items" segment — per-item name + amount
      fields, a participant menu ("Shared by everyone" / "Shared by Ana,
      Ben"), Add Item / swipe-to-delete, a running "X unassigned" footer with
      a "set amount to Σ items" shortcut; edit rehydrates the items, dup
      regenerates their ids. **CSV export** unchanged (splitType isn't in the
      CSV; `Splits` already carries the resolved outcome — same as
      percentage); **JSON export / CloudKit backup** carry `items` for free
      via Codable. `DESIGN.md` §2/§3/§6/§10 updated. Verified in the
      Simulator: v7→v8 migration on a live group, an itemized POST resolving
      to correct balances, and the edit sheet rehydrating all line items
      with their shared-by labels.
- [x] **Default split config per group.** Done 2026-09-09. **Model:**
      `DefaultSplit { weights: [DefaultSplitWeight] }` (ClanTabKit) — a
      percentage split (weights positive, distinct, summing to 100);
      `.resolved(for: members)` drops weights whose member left and returns
      `nil` if that breaks the sum. `nil` on a group = "split equally".
      **Worker:** `group_meta.default_split` (JSON, a new key — no
      `SCHEMA_VERSION` bump); `PATCH /api/groups/:id` takes
      `{ defaultSplit: {...} | null }`, validated (shape + sum + members
      exist → 400/404); `GroupSummary.defaultSplit` on `getState`.
      **Kit:** `GroupSummary.defaultSplit`, `ClanTabClient.updateGroup(defaultSplit:)`
      (a `FieldUpdate`). **App:** a "Default Split" section in Group
      Settings — shows the current split ("Split equally" / "Dev 70% ·
      Sam 30%"), a "Change" → per-member `%` editor with a live
      "adds up to 100%" check and Save / Split Equally. `AddExpenseView`
      gains a `defaultSplit:` param; a *fresh* Add Expense (not edit /
      duplicate / recurring) opens on `.percentage` pre-filled from
      `resolved(for:)`. **Verified end-to-end in the Simulator:** set
      70/30 in settings → PATCH stored → Add Expense opened on the
      Percentage tab, Dev 70% / Sam 30%. Tests: `DefaultSplitTests` (3,
      kit) + `routes.test.ts` +2. `make check` green. `DESIGN.md` §2 updated.
- [x] **Read-only web link for balances.** Done 2026-09-09.
      **Worker:** `GET /g/:groupId/balances` — a `noindex` HTML page (same
      iOS-card styling as the "Open in ClanTab" fallback) showing each
      member's per-currency balance ("Dev is owed ₹1,250" / "Sam owes …" /
      "settled up") and the simplified settle-up plan, nothing else. All
      interpolated names/emoji HTML-escaped. Rather than reuse the write
      token (which would make "view-only" a lie), a **separate**
      `group_meta.view_token` — `POST /api/groups/:id/view-link` mints it
      (idempotent), and `requireReadableGroup` accepts it *only* for this
      page; a caller holding just the view token gets 403 on every mutating
      route (tested). **App:** `GroupViewModel.loadViewLink()` mints it
      best-effort on Group Home appear; `shareMenu` gains a
      "Share View-only Balances" `ShareLink` pointing at
      `<apiHost>/g/:id/balances?token=<viewToken>` (the API host, not the
      branded Universal-Link host — a view-only link must always open the
      web page, never the app's claim/join flow). **Verified:** rendered
      the page via curl + headless Chrome; view token opens it, can't
      write. Tests: `routes.test.ts` +4. `make check` green. `DESIGN.md`
      §2/§8 updated.
      (Follow-up: a "Revoke view links" action that rotates the view
      token; the branded `clantab.nakka.dev` host via an AASA
      `/g/*/balances` exclude.)
- [~] **Offline queueing for adding an expense.** Investigation done
      2026-09-09 (see `DESIGN.md` §7).
      **Fails fast, never hangs.** `URLSessionTransport` uses
      `URLSession.shared` (`waitsForConnectivity` is `false` for `.shared`),
      so offline → `URLError.notConnectedToInternet` thrown immediately; a
      mid-request drop is bounded by the 60s request timeout; nothing waits
      indefinitely. `AddExpenseView.save()` catches it, shows the message,
      and **keeps the sheet open with the form intact** — retry works once
      you're back online, or Cancel loses the typed data.
      **Backend is ready.** `GroupDO.addExpense`/`addSettlement` are
      idempotent on the client `id` (`readExpenseById(req.id)` → replay
      returns the existing row), and DO requests are serialized — a stored
      request is safe to replay any number of times. (The `id` is generated
      fresh per `save()` call, so idempotency only protects a *stored*
      request, not a user re-tap — harmless either way.)
      **The cost is optimistic display, not the network.** The app has
      **no optimistic UI by explicit design** (`DESIGN.md` §7), so showing
      a queued expense in the feed and reflecting it in balances is a real
      architecture change. Plus edge cases: member deleted server-side,
      group left, account deleted, double-tap, editing a not-yet-synced row.
      **Real estimates (the `~20k` guess was low):**
      - *Clearer message + a "Try Again" button, no queue* — `~10k`.
        Marginal: Apple's "The Internet connection appears to be offline."
        is already shown.
      - *Single-slot deferred retry* — `~25–30k`. Stash the one failed
        request per group, a "1 expense didn't send — Retry" banner on
        Group Home, auto-flush on foreground / reachability. No feed
        changes, no optimistic balances, add-only. Covers the realistic
        case (added in a dead zone, syncs when signal returns).
      - *Full offline queue* — `~100–140k`. Multi-item persistent queue +
        syncer with transient-vs-permanent classification + optimistic feed
        & balances + failure surfacing + edge cases. Comparable in scope to
        "Itemized expense entry"; reverses a deliberate v1 non-goal.
      **Recommendation:** current behaviour isn't broken. Do the single-slot
      retry only if there's a signal people add expenses offline; don't
      build the full queue without demand.
- [x] **Balance-aging nudge.** Done 2026-09-09. `BalanceAging`
      (ClanTabKit, pure) — `reconcile(current:groupId:balances:)` folds the
      member's fresh per-currency balances into a `[key: BalanceAgingEntry]`
      map (`key` = `"<groupId>\t<currency>"`, `entry` = `{ owedSince,
      nudged }`): a currency newly in the red past `minimumMinor` (₹1/$1)
      starts a clock and gets a one-shot nudge scheduled for
      `owedSince + threshold` (14 days); a cleared currency drops out and
      its nudge is cancelled; once the threshold passes the entry is marked
      `nudged` so it fires **once per debt episode** — clearing and
      re-incurring re-arms. State-driven, not a calendar cadence.
      `BalanceAgingStore` (UD + in-memory). App: `BalanceAgingScheduler`
      mirrors `RecurringReminderScheduler` (one-shot `UNCalendar`/`UNTimeInterval`
      trigger by fire date, `userInfo["groupId"]` opens the group like any
      notification tap) — **never prompts**, only schedules when
      notifications are already authorized. `BalanceAgingObserver` glues the
      two, fed from `GroupViewModel.updateCaches` (group open) **and**
      `AuthViewModel.reconcileGroupBalances` (every group, opened or not).
      Tests: `BalanceAgingTests` (10, kit) + `BalanceAgingObserverTests`
      (3, app). `make check` green.
      (Follow-up ideas: an in-app card on Group Home for the same
      condition; nudge the "you're owed, chase them" direction too.)
- [x] **PDF export.** Done 2026-09-09. **Kit:** `GroupReportModel.build(from
      state:)` (pure) gathers the report's numbers from the same
      `Insights` / `Balances` output every screen uses — total, date range,
      counts, per-member and per-category spend (in the currency with the
      most spend, others noted), and the simplified settle-up plan resolved
      to names + formatted amounts. **App:** `GroupReportView` lays it out
      at A4 point size (a plain document look, not the brand-gradient recap
      card); `GroupReportPDF.write(from:)` rasterises it straight into a PDF
      `CGContext` via `ImageRenderer` — no PDFKit needed to *make* a PDF.
      A `ShareLink("Export PDF Report", item: url)` sits alongside Export
      CSV / JSON in the Group Options menu. **Verified in the Simulator:**
      the share sheet shows "…-report · PDF Document · 35 KB"; pulled the
      file off the device — a valid one-page PDF, all sections rendering
      (header, stats row, settle-up, by-member/by-category bars, footer).
      Tests: `GroupReportTests` (4, kit). `make check` green.
- [x] **Inline calculator on the amount field.** Done 2026-09-09.
      `MoneyFormat.evaluate(_:)` (ClanTabKit) — `+`/`-` left to right, each
      term through the existing `minorUnits(from:)` (integer minor-unit
      math, no `Double`); `nil` for an incomplete expression (`"12 +"`), a
      non-numeric term, or a negative result. A bare number evaluates
      identically, so it's a drop-in for the amount field's parse.
      `AddExpenseView`'s amount field switched to it, plus a `@FocusState`
      that surfaces small `+` / `−` buttons in the row while editing (the
      `.decimalPad` has no operator keys) and resolves `"12 + 8.50"` →
      `"20.50"` on blur (a bare number is left alone). **Verified in the
      Simulator**: buttons appear on focus, `+` appends, the expression
      resolves on Done. Tests: `MoneyFormatTests` +4 (kit). `make check`
      green.
- [x] **Archive a group.** Done 2026-09-09. **Worker:** `group_meta.archived_at`
      (nullable ISO timestamp, a new key — no `SCHEMA_VERSION` bump, same as
      `emoji`); `PATCH /api/groups/:id` takes `{ archived: boolean }` and the
      server stamps / clears the timestamp itself; `GroupSummary.archivedAt`
      and the `/api/auth/groups/balances` per-group row both carry it.
      Group-wide, reversible, any member can toggle; purely organizational —
      **doesn't block mutations.** **Kit:** `GroupSummary.archivedAt`,
      `KnownGroup.archivedAt` + `.isArchived` (cached like `emoji`),
      `ClanTabClient.updateGroup(archived:)`, `KnownGroupsStoring.setArchivedAt`,
      `GroupBalanceSummary.archivedAt`. **App:** an "Archive Group" /
      "Unarchive Group" button in Group Settings (its own section, blue —
      distinct from the red "Leave This Group"); `GroupViewModel` +
      `AuthViewModel.reconcileGroupBalances` cache the state; `StartView`
      splits the list into active + an "Archived (N)" `DisclosureGroup`
      (collapsed), and `DashboardTotalsHeader` gets only the active groups so
      an archived group's balance drops out of the cross-group totals.
      **Verified end-to-end in the Simulator** (archive → group leaves the
      list + totals, appears under the disclosure with its emoji + balance;
      button flips to Unarchive). Tests: `routes.test.ts` +2,
      `auth-routes.test.ts` balances test extended, `KnownGroupsStoreTests`
      +2. `make check` green.
      (Follow-up: a subtle "Archived" hint on Group Home itself.)
- [x] **Image storage backend (R2).** Done 2026-09-10 — built, tested,
      deployed, and verified with a live presigned PUT+GET round-trip
      against `clantab-media-preview` (real R2). A length-mismatched
      PUT is rejected 403, so the size cap is enforced by R2, not just
      advisory. `deleteExpense` cleanup left for the receipt item (§6).
      Unblocks the three items below (profile photos, group cover
      images, receipt attachments) and any future "attach an image"
      feature. Was parked 2026-09-06 for the zero-card invariant —
      unparked once monetization was decided. Cost is negligible: R2
      has no egress fee, free tiers 10GB / 1M writes / 10M reads per
      month (~$3-15/mo even at 1M users). Built once, all three
      surfaces below wire to the one endpoint.
      1. ✅ Owner enabled R2 + created `clantab-media` /
         `clantab-media-preview` buckets + an Object Read & Write API
         token.
      2. ✅ `r2_buckets` binding `MEDIA` in `wrangler.jsonc`
         (`bucket_name` / `preview_bucket_name`). Keys:
         `avatars/<sha256(sub)>`, `groups/<groupId>/cover`,
         `expenses/<groupId>/<expenseId>/<recordId>` — derived
         server-side, never from the client.
      3. ✅ `POST /api/media/presign` (`src/index.ts`,
         `src/lib/media.ts`, `src/lib/s3-presign.ts` — hand-rolled
         SigV4, zero deps, checked vs. AWS's documented vector).
         Session required; group-scoped ops require *claimed
         membership*, not just the capability link. 5-minute
         presigned PUT / GET; the Worker never proxies bytes.
      4. ✅ Upload validation: JPEG/PNG/WebP whitelist, 5MB cap,
         `Content-Type`/`Content-Length` signed into the PUT URL so
         the client can't deviate. `test/media.test.ts` (16).
      5. ✅ `R2_ACCOUNT_ID` / `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY`
         set as prod secrets + in `worker/.dev.vars`; deployed
         (version `0103d3e9`). Deployed endpoint 401s without a
         session (not 503), confirming creds are wired.
      6. ⏳ Delete-on-delete: wired per-surface as each of the three
         items below ships (nothing to orphan until then; expenses
         soft-delete to trash and are never purged, so receipt
         cleanup hangs off account-deletion / group-deletion, not
         `deleteExpense`).
- [x] **Profile photos (replacing/supplementing initials avatars).**
      Done 2026-09-10 across worker + kit + app; all unit tests green
      (worker 253 / kit 268 / app 129). **Verified end-to-end in the
      Simulator** with a temporary debug button standing in for
      `PHPickerViewController` (which idb can't drive): pick → 512 px
      JPEG → presign → real R2 PUT (`clantab-media-preview`) → commit →
      fan-out; relaunch → `getState` `avatarKey` → presigned view URL →
      photo renders on the member row; "Remove Photo" reverses it. The
      OS picker sheet itself is Apple's code, unchanged.
      1. ✅ `ProfileImage` (app) — centre-crop + downscale to 512 px +
         JPEG q0.7 before upload (`ProfileImageTests`, 4).
      2. ✅ Upload via the presign flow; `members.avatar_key` is
         denormalised from the identity (schema v9), seeded at claim,
         kept current by the `/api/auth/avatar` fan-out (worker half,
         committed 6ebb54d). `GET /api/auth/avatar` → the caller's own
         key for Settings.
      3. ✅ `MemberAvatar` shows the photo (via `AvatarImageLoader`, an
         env-injected memory cache with a generation counter so a
         same-key photo swap still re-renders), falls back to
         `MemberColor` initials. Every `MemberAvatar(member:)` call
         site lights up for free; name-only sites keep initials.
      4. ✅ Settings → Account: `PhotosPicker` add/change + "Remove
         Photo"; `AuthViewModel.setAvatar/removeAvatar/fetchMyAvatarKey`.
      Follow-ups: disk cache for avatars (memory-only today); show
      other members' photos on the name-only surfaces (SettleUp,
      Insights, PeopleView) if worth the plumbing; a real hands-on pass
      through the actual `PHPickerViewController` on a device (the debug
      button bypassed only that sheet).
- [x] **Group cover image.** Done 2026-09-10 across worker + kit + app;
      all unit tests green (worker 256 / kit 271 / app 133).
      **Verified end-to-end in the Simulator** (debug button standing in
      for `PHPickerViewController`): pick → 16:9 1280px JPEG → presign →
      real R2 PUT (`clantab-media-preview`, confirmed a 1280×720 JPEG
      landed) → `PATCH { coverImage: true }` → relaunch → dashboard row
      thumbnail + Group Home banner both load fresh from the presigned
      view URL; "Remove Cover" clears the record and the UI. Only remaining
      real-device check is the actual OS picker sheet.
      1. ✅ Worker: `cover_key` `group_meta` row (no schema bump);
         `PATCH /api/groups/:id` `{ coverImage: true | null }` commits
         (with an R2 head-check) / removes (deletes the R2 object).
         `GroupSummary.coverKey` surfaces it. The `groupCover` /
         `receipt` presign gate was **relaxed from claimed-membership
         to the standard `requireGroup` capability check** — a guest
         who can rename the group can also set its cover (`presignMedia*`
         now takes an `accessToken`).
      2. ✅ Kit: `CoverImageUpdate` (.commit/.remove), `updateGroup(
         coverImage:)`, `GroupSummary.coverKey`, `KnownGroup.coverKey`
         + `setCoverKey`. `CoverImage` (app) — 16:9 crop + 1280px + q0.75.
      3. ✅ Group Settings: a "Cover Image" section — `PhotosPicker`
         add/change + "Remove Cover". `GroupCoverImage` view (reuses
         `AvatarImageLoader`) shows it on the dashboard row (rounded-
         square badge) and as a banner at the top of Group Home.
- [x] **Photo attachment on an expense (receipts).** Done 2026-09-10
      across worker + kit + app; all unit tests green (worker 258 /
      kit 272 / app 136). **Verified end-to-end in the Simulator**
      (debug button for `PHPickerViewController`): Add Expense →
      Receipts → attach → thumbnail with remove badge → save. Server
      stored `attachments: [expenses/<gid>/<clientUUID>/<random>]`
      (`assertReceiptKeysBelong` passed); the R2 object is a real
      JPEG; `getState` returns it. The activity-feed paperclip,
      `ReceiptViewer`, and edit-removes-receipt→R2-delete weren't
      visually driven (idb can't scroll the iOS-26 `.searchable`
      List) — paperclip is a trivial glyph, viewer reuses the
      avatar/cover loader path, and the delete-on-edit is covered
      end-to-end in `routes.test.ts`.
      Plain photo attachment only; OCR stays parked.
      1. ✅ Worker: `expenses.attachments` (schema v10, nullable JSON
         array). POST/PUT expense body takes `attachments: [key]`;
         `assertReceiptKeysBelong` rejects a key for another expense;
         an *add* with attachments must send `id`. A `PUT` that drops
         a key deletes its R2 object (the only cleanup point —
         expenses soft-delete, never purge; Restore keeps them).
      2. ✅ Kit: `Expense.attachments` / `AddExpenseRequest.attachments`
         (`[String]?`). `ReceiptImage` (app) — fit 2000px long edge,
         q0.8, **no crop** (receipts must stay legible).
      3. ✅ Add/Edit Expense: a "Receipts" section — multi-select
         `PhotosPicker`, thumbnail strip with per-item remove; expense
         id fixed up front so receipts upload before the first save.
         `ReceiptThumbnail` + `ReceiptViewer` (pinch-zoom full screen,
         via `AvatarImageLoader`). Activity feed row gets a paperclip.
      Follow-up: a receipt removed during an *add* that's then
      cancelled leaves an R2 orphan (rare; no client delete-object
      API). Camera capture (picker only for now).

### Friend playtest, round 3 — accepted 2026-09-13

Real-device feedback on build `1.0 (10)` (the build that carried the
round-2 batch to TestFlight), 17 raw items, triaged in chat 2026-09-13.
Scope decided deliberately, same shape as round 2: the real bugs and
already-half-built wiring ship before submission; the three genuinely
new, large pieces of scope (merge duplicate members, a universal
identity-level display name, linking Apple+Google accounts) are
**not** ship-blocking — see "Parked" below. Anything the triage found
already shipped-and-working-as-designed (Insights as its own tab, the
minimized Group Home toolbar, the 3-way split-type control) is noted
but not reopened; the audits that made those calls were deliberate.

**Batch closed 2026-09-13** — all 13 in-scope items done, `make check`
green throughout (kit + worker + iOS build/tests), committed on
`round3-playtest-batch`. Only the Owner-only real-device re-verify
remains (below), same shape as round 2's closeout.

- [x] **[bug] Delete Account doesn't actually sign the account out
      locally.** Done 2026-09-13. The worker's delete was already correct
      — `handleAuthDeleteAccount` unclaims every membership and wipes the
      `UserDO` — but `AuthViewModel.deleteAccount()` never cleared
      `KnownGroupsStore` (each group's cached access token included), and
      `RootView`'s groups list is driven from that local cache, not a
      fresh fetch. Signing back in with the same identity re-showed every
      old group, still openable with its cached per-group access token.
      Fixed with a new `KnownGroupsStoring.forgetAll()` default-extension
      method (built on the existing `forget`, so it works for both the
      real and in-memory conformances for free) called from
      `deleteAccount()`'s two success paths (the normal one and the
      already-`INVALID_SESSION` one) — deliberately *not* from plain
      `signOut()`, which should still let the same identity see its
      groups again on a normal re-sign-in. Two new `AuthViewModelTests`
      cases cover both success paths. `make check` green (kit + worker +
      iOS build/tests). Still needs the real-device re-verify: the
      existing "Delete Account" TestFlight-pass step now specifically
      exercises sign-back-in showing zero groups, not just "signed out."
- [x] **[bug] "Delete this settlement" confirmation renders unanchored.**
      Done 2026-09-13, **then reverted the same day** — real-device
      feedback found the per-row fix made the dialog disappear
      immediately, unable to interact with it at all: setting
      `pendingDelete` from a `.swipeActions` button also retracts that
      row's revealed swipe UI, and a `.confirmationDialog` living on the
      row instance that's mid-retraction gets torn down with it. Reverted
      to the original list-level `.confirmationDialog` (`presenting:
      pendingDelete`, `deleteTitle` back to a plain computed property) —
      "delete works everywhere, dialog occasionally mis-anchors on a wide
      size class" beats "delete is unusable everywhere." A real fix (an
      anchor-preference host, `CoachMark`'s own pattern) is still owed if
      the mis-anchor complaint recurs, but isn't worth the complexity
      until it does. iOS build + `make check` green.
- [x] **[bug] Coach marks clip inside `List`/`Form` rows.** Done
      2026-09-13. `CoachMark` deliberately overlays outside its anchor's
      own bounds, which two of the three live coach marks need to do from
      inside a `List`/`Form` row (`InsightsView`'s over-time chart, Add
      Expense's "Add Someone" row) — rows clip their own content, so the
      bubble got cut off. Reworked to an anchor-preference pattern: `.
      coachMark` now just marks a `CoachMarkAnchorKey` preference instead
      of drawing an `.overlay` in place; a new `.coachMarkOverlayHost()`
      (added once per screen, at the same level as that screen's own
      top-level content — `GroupHomeView`, `InsightsView`, `AddExpenseView`)
      reads the preference and draws the bubble as a sibling layer to
      every row, unaffected by any row's own clipping, using the same
      bubble-height-aware `alignmentGuide` math as before. Fixes all
      three call sites uniformly, not just the two reported. iOS build +
      `make check` green.
- [x] **[bug] Add Expense's +/- buttons render at different sizes.**
      Done 2026-09-13. No explicit frame on `amountOperatorButtons`;
      "plus" and "minus" SF Symbols have different intrinsic bounding
      boxes so `.bordered` sized the two capsules differently. Added a
      shared 20×20 `.frame` on each glyph. iOS build green.
- [x] **Cover photo + emoji in the create-group flow.** Done 2026-09-13.
      Both already existed post-creation (`GroupSettingsView`'s
      `emojiPicker` + `coverImageSection`, backed by the working R2
      presign flow) — just never offered during `CreateGroupView`. Added
      a "Make It Yours" section to the "created" confirmation stage
      (after the join code, before "Continue") — same emoji chip set
      (`GroupSettingsView.emojiOptions`, already internal, reused as-is)
      and the same presign → upload → commit cover flow, each pick
      applying immediately rather than needing a separate Save (no
      `isDirty` concept needed for a one-shot creation step). Both
      optional; "Continue" always works regardless. iOS build +
      `make check` green.
- [x] **Edit settlement.** Done 2026-09-13. Server (`updateSettlement`)
      and kit (`ClanTabClient.updateSettlement`) were fully wired; the
      client never added the UI. A settlement has no description/category
      — just from/to/amount/currency (date is preserved server-side) — so
      it got its own small form, `EditSettlementView`, rather than reusing
      `SettleUpView` (that screen is the suggested-payments *plan*, a
      different concept from an already-recorded settlement). Wired into
      `GroupHomeView`: tapping a settlement row and a new per-row "Edit"
      swipe action (settlements previously only had "Delete") both open
      it. iOS build + `make check` green.
- [x] **1:1 expense/settlement history on a group member's profile.**
      Done 2026-09-13. `MemberProfileView` showed only a net balance.
      Added a "Together in This Group" section: every expense where both
      the viewer and the member appear among payers/splits, and every
      settlement between the two of them, newest first — reusing the
      existing `ActivityItem`/`ActivityRow` from `GroupHomeView`'s own
      feed rather than a new row type. `GroupHomeView` now also passes
      `state.expenses`/`.settlements`/`.members` through (defaulted to
      `[]` on the type itself, so no other call site needed touching).
      Cross-group history stays out of scope — the Friends tab already
      gives a cross-group net total. iOS build + `make check` green.
- [x] **Insights: a way back to a specific group from the group page.**
      Done 2026-09-13. The build-9 audit deliberately promoted Insights
      to its own tab and removed the in-group entry point — didn't
      reverse that — but Group Home now has a way back in: a "View
      Insights" item in the existing "More" menu's Filter section (next
      to the filter controls, since both act on the same activity data),
      opening `InsightsView` as a sheet. `InsightsView` needs no groupId/
      client of its own — it's a pure view over `expenses`/`members`/
      `groupName`/`groupEmoji`, all of which Group Home already has
      loaded, so no new fetch. iOS build + `make check` green.
- [x] **Insights: personal owe/owed totals, not just spend.** Done
      2026-09-13. The hub (`InsightsHubView`) showed a bare groups list
      with no numbers at all. Added the cross-group `DashboardTotalsHeader`
      (same component the dashboard uses, over `DashboardTotals.compute`)
      above the list, plus a per-row balance line on each group
      (`GroupsListView.balanceLine(for:)`, reused as-is) — so the hub
      shows "You owe ₹500 overall" up top and each group's own owe/owed
      next to its name, not just names. Per-category owe/owed (as opposed
      to per-category *spend*, which already exists in `InsightsView`)
      would need new domain logic attributing settlement deltas to
      categories — skipped for now per the original scope note ("do this
      part only if the hub-level number isn't enough on its own"); the
      two additions above already answer the actual complaint. iOS build
      + `make check` green.
      **Superseded 2026-09-13** (see "Real-device findings" below) — a
      follow-up report made clear the actual ask was replacing the
      groups-list-that-drills-in design entirely, not just adding
      numbers to it; that's the real redesign.
- [x] **Smart category suggestion from expense description.** Done
      2026-09-13. No suggestion logic existed anywhere. Added
      `CategorySuggestion.suggest(for:)` (pure `ClanTabKit`, a
      first-match keyword table over the same 9 default categories,
      case-insensitive substring match — "Uber to airport" → Transport,
      "Costco run" → Groceries, etc.), wired to `AddExpenseView`'s
      description field via `.onChange`. Only fires while `category ==
      .uncategorized` — the one value that only ever means "nothing's
      been picked yet" (an edit/duplicate/recurring-template always sets
      a real category up front) — so it can never fight a category the
      user, or another flow, already set. 4 new kit tests. No backend/LLM
      infra needed or used. iOS build + `make check` green.
- [x] **Add Expense: more visual weight as the primary action.** Done
      2026-09-13. The build-9 audit intentionally minimized Group Home's
      toolbar to two items — didn't reverse that (the toolbar `+` stays,
      for VoiceOver/quick access). Added a floating 56pt accent-circle
      button, bottom-trailing, as the unmissable-at-a-glance version;
      hidden while the undo banner shows since that card spans the same
      bottom edge and the two would otherwise collide. iOS build +
      `make check` green.
- [x] **Rename "Split the cost between payers".** Done 2026-09-13.
      Copy-only — the button's styling/placement already went through
      two polish passes; just the label/icon was stale. Now `Label("Add
      Payer", systemImage: "plus")` when off, "Paid by one person" to
      toggle back. iOS build green.
- [x] **Friends list: explain, don't just show empty.** Done 2026-09-13.
      Working as designed — `peerSettlements` only surfaces co-members
      with a claimed identity — but the copy actively misled: both the
      empty state and the populated list's own footer said "share a
      group and they'll show up," when only a co-member who has *signed
      in* ever does. Reworded both to say that plainly and point at the
      actual fix (share the group's invite link so they can join).
      Didn't build the heavier "surface unclaimed co-members with a
      per-member invite affordance" — that needs either a new worker
      endpoint or an extra `fetchGroupState` per known group just to
      power an empty-state hint; accurate copy alone directly answers
      what the playtester actually hit. iOS build + `make check` green.
- [x] **Re-check split-type control on build 10 before touching it.**
      Verified 2026-09-13, no code change. `AddExpenseView`'s current
      `Section("Split")` is exactly what both prior audits already
      produced: a 3-way segmented control (Equally/Exact/%) for the
      common case, a real centered `.bordered` "More Split Types" button
      (not a footnote) behind `MoreSplitsSheet` for the rarer Shares/
      Items modes. Nothing in the current implementation matches "looks
      like fine print" or "cluttered" — this reads as stale feedback
      from before build 9, not a new issue on build 10. Leaving as-is
      rather than speculatively restyling an already-fixed control.

### Real-device findings, builds 11/12 — 2026-09-13

Owner feedback while running the round-3/merge-members TestFlight pass
on an actual device — the first time this session's own fixes got a
real touchscreen and real photo data, not just the Simulator/`idb`.
Two rounds of feedback landed the same day; both are folded into this
one section rather than split across two, since it's all the same
device pass.

- [x] **[bug, regression] Settlement/expense delete confirmation
      disappeared immediately — unusable.** Done (reverted) 2026-09-13.
      Caused by this same session's earlier "anchor the dialog to its
      row" fix, above — see that item for the root cause and the revert.
- [x] **[bug] Insights' member breakdown rows never showed a photo, and
      rendered smaller than Group Home's member rows.** Done 2026-09-13.
      `InsightsView.breakdownRow` called `MemberAvatar(name:size: 22)` —
      the name-only initializer, which `MemberAvatar`'s own doc comment
      says never resolves a photo (`avatarKey` stays `nil`) — instead of
      passing the actual `Member` it already had in hand
      (`entry.member`). Changed the row to take an optional `Member`
      instead of a bare name string and call `MemberAvatar(member, size:
      28)`, matching `MemberBalanceRow`'s size exactly. iOS build +
      `make check` green.
- [x] **Balance bubble sizing still reads as inconsistent.** Done
      2026-09-13 — a real bug, confirmed with a screenshot from the
      round-2 "bubble-graph legibility floor" fix
      (`CirclePack.minNonZeroRadius`). That fix's floor was a hard
      `max(minNonZeroRadius, …)` **clamp**, applied to every
      below-floor circle — so two visibly different small balances (the
      screenshot's `AV`/`ID`, roughly ₹150 and ₹50) both collapsed to
      the *exact same* 20pt radius, reading as "these sizes don't mean
      anything." Verified the mechanism by replaying the screenshot's
      real weights (₹14,468.60 / ₹11,761.85 / ₹3,266.42 / ~₹500 / ~₹150
      / ~₹50) through the actual formula: everything under ~₹300 landed
      at an identical raw radius before the floor even kicked in.
      Reworked `CirclePack.layout` to apply the floor as a **shift**
      instead: find the smallest post-scale nonzero radius, and if it's
      under the floor, raise every below-floor circle by exactly enough
      that the smallest one reaches the floor — each one keeps its size
      *relative to the others* (the point-difference between any two is
      unchanged) rather than collapsing to one constant. A circle
      already at or above the floor (the common case, unaffected). New
      kit test replays real below-floor weights and asserts they stay
      distinct, not identically clamped. `make check` green.
- [x] **Duplicate expense doesn't fill the amount.** Done 2026-09-13 —
      was working as designed (`AddExpenseView`'s duplicate-init path
      had its own comment explaining the blank-amount decision), but
      asked the Owner given real usage now argues the other way:
      confirmed, changed. Duplicating now pre-fills the amount along
      with everything else it already carried over (description,
      payer(s), split, category, currency); the date still doesn't
      carry over — today's date is still the right default for a fresh
      copy being logged now, not the original's date. No existing tests
      covered this (no unit tests exist for `AddExpenseView`'s init
      logic). iOS build + `make check` green.
- [x] **Member profile's "Balance in this group" showed only a bare net
      figure, no breakdown of who makes it up.** Done 2026-09-13. Added
      every settle-up edge touching this member against *anyone* in the
      group (not just against the viewer, which the existing "Settle
      up" section below already covers for its own pay/remind actions)
      — "Priya owes ₹500" / "Ana is owed ₹200" per counterparty, then
      the net total each currency's edges add up to, set apart with a
      bold "Total" row. `SimplifiedSettlement` was already passed in
      whole; this was a display gap, not a data gap.
- [x] **Insights tab (from the tab bar) must show personal data and
      graphs, not a list of groups leading into group data.** Done
      2026-09-13 — reopens/supersedes the round-3 batch's "Insights:
      personal owe/owed totals" item above, which only added numbers to
      the existing groups-list-that-drills-in design; this is the
      actual redesign that item stopped short of. Reworked
      `InsightsHubView` from "every known group, tap one to open its own
      spend charts" to real personal aggregates: the existing cross-group
      `DashboardTotalsHeader`, plus new `PersonalInsights` (`ClanTabKit`)
      — my own share of spend by category, summed across every group's
      own `Insights.byCategory` result (each computed with *that*
      group's correct member id, then merged; a single call across
      combined multi-group expenses would silently mis-filter, since
      member ids are per-group) — rendered as a pie chart + breakdown
      rows, same visual language as the per-group `InsightsView`. A
      "By group" section still lists each group's own balance line, but
      informationally — no `NavigationLink` into that group's charts
      anymore; a specific group's own spend/category/member breakdown
      is reached from that group's own page instead (`GroupHomeView`'s
      "View Insights", from the round-3 batch). 4 new kit tests
      (`PersonalInsightsTests`) cover the cross-group-id-isolation case
      directly — the one a naive single-call implementation would get
      wrong silently. `make check` green.
      **Follow-up bug, same day:** Owner reported the new personal
      charts showing nothing at all on build 13 ("insights has been
      completely removed"). Found two real defects on review: (1)
      `reload()`'s `myMemberIds` dictionary used
      `Dictionary(uniqueKeysWithValues:)`, which **traps** on a
      duplicate key — safe today only because `AuthViewModel.upsertGroup`
      happens to dedupe, a fragile invariant for data that ultimately
      comes from the network; switched to `uniquingKeysWith:`. (2) a
      real race: `auth.groups` (needed to resolve *my* member id per
      group) loads via its own network round-trip, and if this tab's
      `.task` ran before that resolved, every group got silently
      skipped with nothing to re-trigger the aggregation for the rest of
      the session. Added `.onChange(of: auth.groups)` to re-aggregate
      whenever the membership list changes. Also added a visible
      "Couldn't load your personal spending" message for the case where
      every fetch genuinely fails, instead of silently showing just the
      "By group" list with no charts above it and no explanation. Not
      yet confirmed against the real device that either was the actual
      cause — both are real defects regardless. `make check` green.

### End-user flow audit — 2026-09-13, fresh pass

Owner asked for a full functional flow audit "purely from an end user
POV" across every screen, independent of the code-level defect list
already tracked separately (see the D-ticket set in the system-map
artifact — CSV EU-locale corruption, the "…" menu's possibly-unreachable
bottom rows, `InsightsHubView`'s missing tests). This round is genuinely
new findings from walking the app screen-to-screen as a user would, not
a restatement of those.

- [x] **Remove the Insights tab.** Done 2026-09-13, owner decision — not
      v1.1-into-v1.0 scope creep, a deliberate cut. Two of the tab's four
      sections were literally the same component/data Home's dashboard
      already shows (the cross-group total header, the per-group balance
      list); the only non-duplicate content was the "You spent" total +
      by-category pie. It was also the single most fragile screen in the
      app — broke fully in build 13, got an unconfirmed fix in build 14
      the same day — with no demonstrated demand behind it (this app has
      no telemetry; it was built same-day off one playtest note).
      `MainTab` dropped from 4 cases to 3 (home/friends/settings);
      `RootView`'s `TabView` no longer constructs `InsightsHubView`.
      Grep-confirmed no other file still references `MainTab.insights`
      or `case insights`; brace-balance checked on the edited file.
      `InsightsHubView.swift`/`PersonalInsights.swift` were deliberately
      left in the tree as dead code rather than deleted outright, pending
      D14's decision below — since resolved: `InsightsHubView.swift`
      deleted, its logic absorbed into `MySpendingView.swift`.
      **Verification note, resolved 2026-09-13:** this entry originally
      shipped unverified — the session that wrote it had no Swift/Xcode
      toolchain. A later session (this one) does, and has since run
      `make check` for real, successfully, across every commit through
      D14 below — so this change, and everything built on top of it, is
      confirmed actually compiling and passing, not just claimed.
- [x] **[D14] Decide the fate of the category-spend chart.** Done
      2026-09-13, owner decision: rebuild small (option (a), the
      recommended path in `docs/system-map.html`'s D14 ticket). New
      `Screens/MySpendingView.swift` — the "You spent [total]" figure +
      by-category pie/breakdown, reached via a new "My Spending" row in
      Settings' Account area (signed-in only), not a tab of its own.
      Reuses `PersonalInsights` (kit, untouched) and every line of
      `InsightsHubView`'s surviving chart/row code verbatim, **including
      both of D6's fixes** (the `uniquingKeysWith` dictionary build and
      the `auth.groups`-load race's `.onChange`) — carried over exactly,
      not re-derived. Deliberately drops the two duplicate sections
      (`DashboardTotalsHeader`, the "By group" balance list) that were
      the actual reason the old tab got cut — this screen is only the
      part that was genuinely unique. `InsightsHubView.swift` deleted
      (it had no dedicated tests to carry over, per D6's own finding);
      `SettingsView`/`RootView` updated (`client` threaded through,
      `RootView`'s stale "kept as dead code" comment corrected). A
      leftover stale doc-comment on the *per-group* `InsightsView`
      (still referencing the removed tab by name) fixed as a drive-by.
      `make check` green end to end (kit + worker + iOS build/tests),
      run for real.
- [x] **[flow, moderate, D9] "My UPI ID" shown regardless of group
      currency.** Done 2026-09-13. `GroupSettingsView`'s "My UPI ID"
      `Section` gained the same `currency == "INR"` gate
      `SettleUpView`'s UPI nudge and `UPIPayLink.url` already use — a
      USD/EUR group no longer prompts every member for a UPI ID that
      can never activate for them. Reads the form's own live `currency`
      `@State`, not `state.group.currency`, so switching currency in the
      same session hides/shows it immediately, no save required. `make
      check` green.
- [x] **[flow, moderate, D10] "Remind" has no cooldown or history across
      visits.** Done 2026-09-13. New `RemindHistoryStoring` (kit,
      `Storage/` — `UserDefaults`-backed `[String: Date]` per edge key,
      same shape as `BalanceAgingStoring`) + pure `RemindHistory` (kit,
      `Logic/` — `isInCooldown` (4h) and a hand-rolled `relativeLabel`
      ("2h ago"/"3d ago"), dependency-free rather than
      `RelativeDateTimeFormatter` since this package also runs on Linux
      CI). `MemberProfileView.remindSent` (`@State Set`, reset on every
      screen close) replaced with `lastRemindedAt: [String: Date]`
      seeded from the store on `.task` and written back through it on
      every successful send — survives closing and reopening the
      screen, which is the actual bug. The button now reads "Reminded
      2h ago" (disabled) instead of a session-only checkmark, and
      re-enables once the cooldown passes. Defaulted
      (`remindHistory: RemindHistoryStoring = UserDefaultsRemindHistoryStore()`)
      so `GroupHomeView`'s one call site needed no change. Tests:
      `RemindHistoryTests` (10, kit — cooldown boundary, every
      `relativeLabel` bucket, clock-skew floor, both store
      conformances). kit 368. `make check` green (kit + worker + iOS
      build/tests).
- [x] **[flow, minor, D11] "Invite" is split across two different
      screens.** Done 2026-09-13. `GroupSettingsView.joinCodeSection`
      gained a `ShareLink("Share Invite Link", ...)` row using the exact
      same `AppConfig.groupShareURL(groupId:accessToken:)` Group Home's
      own "…" → Share menu already builds — one obvious place to invite
      someone regardless of which screen you land on. `make check`
      green.
- [x] **[flow, minor, D12] Graphs are one tap inside an overflow menu, not
      on Group Home itself.** Decided 2026-09-13, owner call per the
      ticket's own "decide, don't fix blindly" framing: **leave it in the
      menu.** "View Insights" is one tap away already; not worth spending
      Group Home's limited screen real estate on a more visible entry
      point without real demand. No code change.
- [x] **[flow, minor, D13] Group Options mixes five different concerns in
      one long Form.** Decided 2026-09-13, owner call: **leave it as one
      Form.** Real but minor and not urgent per the ticket's own framing —
      sectioning ~9 rows is cosmetic risk on the single most load-bearing
      settings screen right before submission, for a problem nobody's
      actually complained about yet. No code change.

### Code-level defect audit — 2026-09-13 (system-map D1-D8)

Found during a separate code-level review (architecture, god-objects,
data-corruption risk) the same day as the flow audit above, tracked
with full brainstormed options in `docs/system-map.html`'s D section --
condensed here to the recommended fix + steps. `D2` (the "..." menu's
unreachable rows) already has its own entry elsewhere in this file;
`D6` (InsightsHubView tests) is intentionally not repeated here -- moot
now that the Insights tab is removed, see above.

- [x] **[D1, critical] CSV import can silently corrupt EU-locale
      amounts.** Done 2026-09-13. `parseSignedAmount` used to strip every
      `,` unconditionally before parsing -- `"12,50"` (EU decimal comma)
      read as `1250` *major* units (125000 minor, a 100x error), no
      warning. Fixed exactly as scoped: with no `.` anywhere in the
      string, a comma followed by *exactly* 2 trailing digits can only be
      a decimal point -- a genuine thousands group is always exactly 3
      digits, so `"1,234"`/`"1,234.00"` still parse unchanged. Also added
      the suggested safety net -- `flaggingImplausibleAmounts` (applied to
      every format's `Result`) groups an import's expense/settlement
      amounts by currency and, once a currency has ≥4 rows, flags (never
      drops) any amount more than 25x above or below the group's median,
      catching a bad parse this specific fix doesn't anticipate. **Found
      while testing, scope corrected:** a combined EU style
      (`"1.234,56"`, thousands-dot + decimal-comma) isn't `nil`-safe as
      first assumed -- the existing comma-strip silently reads it as
      `1.23` (`"1.23456"` truncated to 2 fractional digits), same
      pre-existing behavior as before this fix, not a new regression.
      Left alone per the ticket's own scope (`docs/csv-import-formats.md`:
      genuinely ambiguous without a real locale signal, "don't build it
      blind") -- documented honestly there instead of claimed as fixed.
      Tests: `testParseAmountEUDecimalComma` (6 cases, incl. the existing
      US-style cases unchanged), `testClanTabEUDecimalComma` (a full
      quoted-CSV round-trip), `testImplausibleAmountFlagged` +
      `testPlausibleAmountsNoWarning`. kit 358 (26 in `CSVImport` alone).
      `make check` green end to end (kit + worker + iOS build/tests, run
      for real in this session -- not the "shell has no toolchain" caveat
      from the Insights-tab-removal item above).
- [x] **[D3, low] Recurring SwiftUI type-checker-ceiling workarounds --
      write the house rule down.** Done 2026-09-13. Added the house rule
      to `AGENTS.md`'s "Conventions" section, naming all 6 prior sites
      (SettleUpView, ImportCSVView, GroupSettingsView x4, AddExpenseView)
      and the same threshold the ticket specified (~80 lines or 3+ nested
      conditionals) -- extract before the compiler forces it, not a
      dedicated refactor pass. Docs-only; no code changed.
- [ ] **[D4, low, not before submission] GroupDO: one class, 34
      methods, every group concern.** ~30-40k tokens, opportunistic
      only. 1357 lines -- members, expenses, settlements, comments,
      trash, tokens, claim/merge, avatars, and balance computation all
      on one class. Do NOT split into multiple Durable Objects (breaks
      the atomic expenses+settlements read the balance math needs) --
      instead split the *file* into modules (members.ts / expenses.ts /
      settlements.ts / comments.ts) the class delegates to, zero
      runtime/schema change. Acceptance bar: worker tests pass
      unmodified. Pick this up opportunistically, never as its own
      pass, and never before the App Store submission.
- [x] **[D5, low, decent ROI] AddExpenseView: 1438 lines doing five
      jobs.** Done 2026-09-13, half as scoped. The itemized line-items
      editor moved to `Components/ItemizedSplitEditor.swift` -- `ItemDraft`
      + the whole itemized-rows body (line items, tax/tip, the running
      total vs. the expense amount) -- 1438 -> 1311 lines. Every binding
      handed down is the same `@State` `AddExpenseView` already owned, so
      this is a pure move; the total/mismatch math it shares with
      `canSubmit`/`save()` now lives in one place (`ItemizedSplitMath`)
      instead of two, so the two can't drift.
      **Scope corrected on the other half:** there is no "recurring-
      template section" to extract -- grepped and read `init` directly.
      Recurring-template *creation* is `NewRecurringReminderView.swift`,
      a wholly separate screen; all `AddExpenseView` does with a
      `RecurringTemplate` is pre-fill ~8 `init` lines (amount/description/
      payer/currency/category) when logging a fresh expense from one, one
      branch of the same `editing`/`duplicating`/`recurringTemplate`/
      `defaultSplit` guard chain that has to read as one flow. There's no
      view body to move and nothing to name `RecurringOptionsSection` --
      splitting 8 lines of a cohesive init into another file would add
      indirection, not remove complexity. Left in place; documented here
      instead of building a component that doesn't correspond to real
      code.
      `make check` green end to end (kit + worker + iOS build/tests, run
      for real).
- [x] **[D7, low, cheap] print() in production instead of real
      logging.** Done 2026-09-13. All 5 `print()` calls (AuthViewModel,
      CloudKitBackup x3, AppDelegate) replaced with a file-local
      `Logger(subsystem: "com.clantab.app", category: …)` (one category
      per file — "Auth"/"CloudKitBackup"/"Push"), `.error` for every
      failure path and `.info` for CloudKitBackup's existing "backup ok"
      success line (previously used for real-device verification, per
      `CHECKLIST.md`'s CloudKit backup item above). No behavior change —
      pure logging swap, visible via Console.app/sysdiagnose on a real
      TestFlight build instead of nowhere. `make check` green (kit +
      worker + iOS build/tests).
- [ ] **[D8, low, watch only] worker/src/index.ts: 1657 lines, 46
      inline route handlers.** No dedicated budget. Still
      Ctrl+F-navigable; not urgent. When next touched, move the
      handler being edited out into routes/*.ts by resource (groups /
      auth / media / admin) -- pays for itself over time, never as its
      own pass.

### Owner feedback batch — 16 items, 2026-09-13 (ideated, not yet built)

Ideation pass only — every item below is scoped against the actual current
code (grepped/read this session, not guessed), nothing implemented yet.
None of these are added to the ship-blocking gate above; they're a v1.1-
shaped backlog unless the owner says otherwise. Two calls worth flagging
explicitly before treating this as "all safely deferrable":

- **R4 is a live bug, not a feature request** — any member can rename any
  other member today, claimed identities included. Cheap to fix in
  isolation, worth pulling forward regardless of what happens to the rest
  of this batch.
- **R5 and R15 aren't missing features** — Merge and CloudKit backup both
  already exist and already work; the report is a pure discoverability
  gap. Don't rebuild either — just surface them.

- [ ] **R1. Universal, identity-level display name.** Already fully scoped
      under "Parked → v1.1 backlog" above (`UserDO.user_meta`, `PATCH
      /api/auth/profile`, `fanOutDisplayName`, claimed-member-proof
      `updateMember`, Settings "Your Name" field) — re-requested by the
      owner in this same terms ("set once, editable in Settings, same
      across all groups"), nothing new to design. `~50-70k`. Note the
      overlap with R4 below: both need the server to know whether a
      member is claimed before it'll refuse an edit — R4's minimal fix
      is a strict subset of this plan's step 3, so if R1 gets picked up
      first, R4 falls out of it for free.
- [x] **R2. Split-by control reads as two different UI patterns stitched
      together.** Done 2026-09-13, owner chose the `Menu`/dropdown option
      over making `MoreSplitsSheet` the sole entry point. Replaced the
      3-way segmented `Picker` + "More Split Types" button + `.shares`/
      `.itemized` summary-row branch with one `Menu { ForEach(SplitType
      .allCases) { ... } }` (added `CaseIterable` to the enum) — same
      "`Menu` wrapping a `Picker`-like set of choices" shape
      `GroupHomeView.activityFilterMenu` already used elsewhere, so this
      isn't a new pattern for the app. `selectSplitType` untouched, as
      the item predicted — presentation-only. Deleted `MoreSplitsSheet`,
      no callers left; fixed a pre-existing doc-comment mis-attachment
      found while touching this code (a comment describing
      `appendOperator` was sitting above `selectSplitType` instead).
      `make check` green (kit + worker + full iOS build/XCTest).
- [ ] **R3. Group Options is one ~9-row Form covering five concerns.**
      `~10-15k` for the grouping alone. This is D13, already surfaced
      and explicitly declined pre-submission ("leave it as one Form... a
      problem nobody's actually complained about yet") — the owner is
      now the one complaining, so reopen it. Concretely: pull "Share
      Invite Link" + "Export" (CSV/PDF) rows out into their own
      `NavigationLink`-pushed sub-screens ("Share & Export"), leaving
      the top-level Form with Group info, Members, Default Split,
      Recurring Reminders, Danger Zone — same pattern already used for
      Recently Deleted/Recurring Reminders elsewhere in this screen
      family. Two sub-screens is enough to matter; don't over-fragment
      into one screen per row.
- [x] **R4. [bug, moderate→high] Any member can rename any other
      member, including a signed-in one.** Done 2026-09-13.
      `GroupDO.updateMember` now refuses the `displayName` half of the
      patch when `identity_sub IS NOT NULL` (`MEMBER_IN_USE`, same code
      `removeMember` already uses) — `upiVpa` still goes through
      unconditionally, and a caller patching both at once no longer has
      the `upiVpa` half silently dropped by the early return. Added
      `isClaimed: boolean` to the wire `Member` (`worker/src/lib/types.ts`
      `toMember`, always present — not an optional-when-set field like
      `upiVpa`/`avatarKey`) and mirrored it on the Swift `Member`
      (non-optional, no default — every construction site now says so
      explicitly). `GroupSettingsView.memberRow`'s tap-to-rename `Button`
      is now a no-op and hides the pencil icon when `member.isClaimed`;
      swipe-to-Merge/Report stay available regardless. New worker test:
      "PATCH refuses to rename a claimed member → 409 MEMBER_IN_USE, but
      still allows their UPI VPA." Doing the `isClaimed` field now (R1's
      step 5) means R1 later reuses it rather than re-touching `Member`.
      Touched ~40 test call sites/fixtures across both Swift targets and
      `test-fixtures/balances/*.json` (shared with the worker's own
      parity tests) to add the new required field — `make check` green
      (kit 365 · worker 315 · full iOS build + XCTest).
- [x] **R5. Merge duplicate members — findability, not existence.**
      Done 2026-09-13. Chose the icon-button option over a long-press
      context menu — this row is already one `Button` (rename), and a
      `.contextMenu` on top of a `Button` row isn't a pattern used
      anywhere else in this codebase. Added a small `arrow.triangle.merge`
      icon `Button` (`.buttonStyle(.borderless)`, same isolation
      `joinCodeSection`'s copy button uses) next to the pencil, shown
      whenever `state.members.count > 1` — same gate the swipe action
      already used. The swipe action stays; this is a second route, not a
      replacement. `make check`'s iOS build green.
- [ ] **R6. Profile/cover photo cropping is silent and automatic —
      no user control.** `~20-30k`. Confirmed in `ProfileImage.swift`/
      `CoverImage.swift`: every upload gets a hardcoded centre-crop
      (square for profile, 16:9 for cover) with no preview and no way
      to reposition or zoom before it's applied — if the interesting
      part of the photo isn't centred, there's no recourse. Add an
      interactive crop step between picking and uploading (drag to
      reposition, pinch to zoom, fixed aspect matching the target) —
      either a small custom `UIViewRepresentable` around
      `UIScrollView`+`UIImageView` (no extra dependency) or a thin SPM
      cropper if one fits the existing zero-third-party-UI-dependency
      posture. Applies to both profile and group cover; receipts
      (`ReceiptImage.swift`) stay auto-resize-only, they're not a
      user-facing crop case.
- [x] **R7. Tapping a member's profile picture doesn't show it larger.**
      Done 2026-09-13. `MemberProfileView`'s header `MemberAvatar` is now
      a `Button` (only when `member.avatarKey != nil` — no point opening a
      viewer for an initials-fallback circle) that presents a
      `fullScreenCover` reusing `ReceiptViewer` as-is (it was already
      generic — `key`/`accessToken`/`initialImage`, nothing receipt-
      specific), so pinch-to-zoom/double-tap/dismiss all come for free.
      Note: the "full-resolution" image is actually the same ≤512px
      upload `ProfileImage.jpegData` already produces on upload — there's
      no separate high-res copy stored server-side, so this fixes the
      real complaint (no way to see it larger at all) without revealing
      new detail. `make check`'s iOS build green.
- [x] **R8. Tapping an activity row jumps straight into editing —
      there's no read-only details view.** Done 2026-09-13. New
      `ActivityDetailView`: header (category badge/avatar, title, big
      amount, date), then for an expense — per-payer breakdown (multi-
      payer only; a single payer is already named in the section header),
      category, per-split breakdown, a horizontal receipt strip (reusing
      `ReceiptThumbnail` read-only) when there are attachments, and
      comments (fetched read-only via the existing `listComments` — no
      add/delete UI here, that stays behind Edit); for a settlement —
      from/to (amount/date already in the header, shared by both kinds).
      Toolbar "Edit" button calls the existing `edit(_:)`, dismissing
      this sheet first so `AddExpenseView`/`EditSettlementView` present
      cleanly after. `GroupHomeView.ActivityRow.onTapGesture` now opens
      this (`viewingItem` sheet) instead of calling `edit(item)` directly;
      the row's own swipe-action "Edit" stays untouched, a separate fast
      path. `make check` green (kit + worker + full iOS build/XCTest).
- [x] **R9. No "Share Balances" image card for the plain balance view.**
      Done 2026-09-13. New `RecapCard.Content.balances([Balance])` — takes
      the full per-member, per-currency set (`state.balances`) and picks
      the single dominant currency itself, mirroring
      `BalanceBubbleView`'s own convention exactly, so the call site is
      just `state.balances`. Rendered off-screen in `GroupHomeView` via a
      new `.task(id: viewModel.state?.balances)`, same
      render-then-`ShareLink` plumbing `SettleUpView`/`InsightsView`
      already use. New "Share Balances Card" entry in `moreMenu`'s
      "Share" section — named to not be confused with the pre-existing
      "Share View-only Balances" (a web URL, not an image). `make check`
      green (kit + worker + full iOS build/XCTest).
- [x] **R10. Share cards always include everything — no selection.**
      Done 2026-09-13, across all three `RecapCard` producers (Settle
      Up, Insights, and R9's new balances card — one more than scoped,
      since R9 landed in the meantime). New shared `ShareCardRowPicker`
      (`ShareCardRow`: id/title/subtitle, domain-agnostic) — each call
      site maps its own typed rows (`SimplifiedSettlement` via the
      existing `rowId(for:)`; `MemberSpend`, already `Identifiable`;
      `Balance` by `memberId`) to `[ShareCardRow]`, gets a `Set<String>`
      back (`nil` selection state = "everything," the default), and
      filters before building `RecapCard.Content`. One correctness catch
      on the balances card specifically: filtering `state.balances` by
      the raw selection *before* fixing the dominant currency could let
      deselecting the currency's biggest holder silently flip which
      currency the whole card is about — fixed by narrowing to
      `balancesInDominantCurrency` first, filtering second. Also
      extracted `Balances.dominantCurrency` (ClanTabKit, new tests) since
      this made it the third independent reimplementation of the same
      formula (`BalanceBubbleView`, `RecapCard`, now this) —
      `BalanceBubbleView`/`RecapCard`/`showsBubblePage` all switched to
      it. `make check` green (kit 376 · worker 315 · full iOS
      build/XCTest).
- [x] **R11. No partial settlement.** Done 2026-09-13. The
      `.confirmationDialog` (couldn't host a `TextField`) became a sheet
      presenting new `ConfirmSettlementView` (sibling type in
      `SettleUpView.swift`, same file-sharing precedent as
      `ReceiptViewer`/`ReceiptThumbnail`) — an editable amount defaulted
      to the full suggested `settlement.amountMinor`, a note when it's
      been edited down (or up), Confirm disabled at zero/blank. No
      server change, as scoped — `addSettlement` already accepted any
      `amountMinor`. Caught and fixed one thing the item's own text
      didn't anticipate: "Retry" (UX audit [33]) resubmits `failedSettlement`
      after a failure, and used to always fall back to the *full*
      suggested amount regardless of what had actually been typed — added
      `failedAmountMinor` alongside `failedSettlement` so Retry resubmits
      the exact partial amount that failed, not a silently different one.
      `make check` green (kit + worker + full iOS build/XCTest).
- [x] **R12. "Paid by" should be one multi-select list, not a picker plus
      a mode-toggle button.** Done 2026-09-13. New `PayerPickerView`
      (multi-select sibling of the now-deleted `MemberPickerView`, which
      had no other callers left once this landed) drives a new
      `selectedPayerIds: Set<String>` — the *only* new state, kept
      one-way in sync via `.onChange` into the real save()/validation
      model (`payerId`/`isMultiPayer`/`payerAmountText`, all unchanged),
      exactly the "UI merge, not new state" the item called for. Picking
      exactly one collapses back to the plain "Paid by <name>" row and
      `isMultiPayer = false`; 2+ reveals `payerAmountRows`, now filtered
      to the selection instead of a searchable list of the whole group
      (the picker is the membership control now). The picker itself
      refuses to let the last remaining payer be deselected — an expense
      always needs at least one. `make check` green (kit + worker + full
      iOS build/XCTest); not verified live in the simulator (the memory
      recipe needs temporary source patches to work around sim-only
      CloudKit/Keychain crashes — owner call 2026-09-13 to rely on
      build+test for the rest of this batch instead).
- [x] **R13. Add "View Insights" as a 3rd swipeable page on Group
      Home, not a menu item.** Done 2026-09-13, reopening D12 as the
      owner asked. `InsightsView` is now a 3rd page in the hero
      `TabView`, gated independently of the bubble page's own condition
      (`showsBubblePage`) — Insights shows whenever the group has any
      expense history at all, even settled-up or single-balance, using
      its own `List` (scrolls happily inside the fixed
      `heroTabViewHeight` — no extra wrapper needed). Dropped the "…"
      menu's "View Insights" entry and `isPresentingInsights` sheet, per
      the item's own call to not keep two routes to the same place —
      the `TabView` page is the only one now. Coach-mark copy widened to
      "who owes what, and your spending insights"; **id left unchanged**
      so a dismissed coach mark doesn't reappear for existing users.
      `make check` green (kit + worker + full iOS build/XCTest).
- [x] **R14. Add a manual "Record a Settlement" option, independent of
      Settle Up's suggestions.** Done 2026-09-13, no backend work as
      scoped — `addSettlement` unchanged. New `AddSettlementView`, a
      create-mode sibling of `EditSettlementView` rather than a nullable-
      `settlement` branch on it (their identity — title, what "Save"
      means — differ enough to be confusing shoehorned into one type);
      same field set, **no date** — deviates from the item's literal
      "from, to, amount, currency, date" list, matching
      `EditSettlementView`'s own existing omission instead (the wire
      `AddSettlementRequest` has no `settledAt` field; the worker stamps
      `Date.now()`, unchanged here). Reachable from `moreMenu`'s own new
      `Section` (not the floating `+`, which stays Add-Expense-only —
      the app's one-primary-action convention), gated on
      `state.members.count >= 2` since a settlement needs two distinct
      people. `make check` green (kit + worker + full iOS build/XCTest).
- [x] **R15. CloudKit backup — no visible status or manual trigger
      anywhere.** Done 2026-09-13, visibility only (no manual trigger —
      per the item's own note, a status line answers "prove it's
      working" without needing a button). Every failure path in
      `CloudKitGroupBackup.backUpIfNeeded` used to swallow silently past
      `os.Logger`; added `lastFailure`/`recordFailure`/`clearFailure` to
      `CloudBackupStateStoring` (both stores), called from every non-
      success return/catch in `backUpIfNeeded`, cleared on the next
      success. New pure `CloudBackupSummary.compute(groupIds:stateStore:)`
      in ClanTabKit aggregates every known group into one
      `CloudBackupOverallStatus` (`.neverBackedUp` / `.synced` /
      `.failing`, failure wins iff newer than the last success) — a
      Settings row per group would've been silly. New
      `CloudBackupStatusRow` (`App/ClanTab/Components/`) live-checks
      `CKAccountStatus` first (distinguishes "not signed into iCloud"
      from a real write failure) then falls back to the summary, reusing
      `RemindHistory.relativeLabel` for the "2h ago" phrasing rather than
      hand-rolling another one. New Settings section, signed-in only
      (backup itself only ever runs for a claimed group). `make check`
      green (kit 373 · worker 315 · full iOS build + XCTest).
- [x] **R16. Add a "My Spending" entry point on the Home page too.**
      Done 2026-09-13. Not a toolbar icon — `StartView` deliberately
      dropped its icon toolbar for the tab bar (own comment in that file),
      and `StartView` doesn't hold `client`/`knownGroups`/`auth` as
      properties (it's callback-driven, unlike `SettingsView`), so a new
      `AppRoute.mySpending` case + `onOpenMySpending: () -> Void` closure
      (mirrors `onCreate`/`onJoinWithCode`) is how `RootView` threads the
      dependencies through, same as every other `homeStack` push. A small
      plain row (`Label("My Spending", systemImage: "chart.pie")` +
      chevron) sits between the dashboard totals header and the groups
      list. `make check` green (kit + worker + full iOS build/XCTest).

**Sequencing note, not asked for but worth saying:** R4 is the one item
here I'd actually argue for pulling into the current submission cycle
rather than v1.1 — it's a real, live per-group abuse vector today, and
the fix is a few lines server-side plus removing an affordance
client-side, not a design project. Everything else in this batch is
genuine v1.1-shaped polish/feature work — none of it is a bug in the
"broken today" sense the way R4 is.


### Parked — not dropped, revisit deliberately

- Receipt / bill reading (OCR) — needs on-device Vision work or a paid
  cloud OCR API plus a review/correction UI; not cheap like the rest of
  this list. Confirmed out of scope again 2026-09-06/07.
- Google Drive backup integration — needs its own OAuth scope-
  verification with Google and there's no Android client to justify it
  yet; revisit if an Android build ever happens.
- Pending-approval on an expense someone else added on your behalf —
  new expense-state machine (pending/approved/rejected), touching
  edit/delete/settle-up/export/recurring-reminders wherever they read
  an expense's status, not just a new screen. Highest risk-to-value
  item reviewed 2026-09-10: no actual user asked for this, it only
  came out of the competitive scan, and it doesn't fit how loose this
  app's trust model already is by design. Hold until real friction
  shows up, not on spec.
- JSON/Excel export — still parked 2026-09-10 on re-review. No demand
  signal (nobody asked; competitive-scan-only), CSV already round-trips
  with ClanTab's own format plus Splitwise/Splid import, and a real
  `.xlsx` writer isn't free on iOS — no first-party framework, so it
  means pulling in a third-party SPM dependency for a format nobody's
  requested.

**v1.1 backlog — real demand, scoped and ready, deliberately not v1.0.**
Unlike the plain-bullet items above (open questions or rejected-for-now
ideas), these carry a concrete execution plan each, drafted 2026-09-13
against the actual current schema/endpoints, ready to pick up as ordinary
"To do" items whenever v1.1 work starts. "Merge duplicate members" was
pulled forward and finished same-day (marked `[x]` below) rather than
waiting for v1.1 — the other two are still genuinely parked.

- [x] **Merge duplicate members.** Done 2026-09-13 — pulled forward out
      of the v1.1 backlog same-day, in parallel with the Owner's
      real-device TestFlight pass on build 11. Real demand (round-3
      playtest, 2026-09-13 — two accidental/typo "indra" members in one
      group with no way to combine them).
      **Permanent, with no undo of any kind — confirmed 2026-09-13, this
      is load-bearing for the whole design, not a caveat to add later.**
      Unlike deleting an expense or settlement (soft-delete —
      `deleted_at`/`deleted_by`, restorable from `RecentlyDeletedView`),
      there is no soft-delete concept for a member anywhere in this
      schema, and this plan doesn't add one: step 2 below hard-`DELETE`s
      the losing member row, and the reassignment `UPDATE`s in step 1
      overwrite `member_id`/`payer_id`/`from_id`/`to_id` in place, so
      afterward there is no stored trace of which rows used to belong to
      which of the two original members. `CloudKitGroupBackup`
      (`App/ClanTab/CloudKitBackup.swift`) does **not** help here either
      — grep-confirmed 2026-09-13, it's a write-only snapshot
      (`GroupBackupWriting`) with no restore path anywhere in the app or
      worker, not even a manual one; it exists for a lost-device
      scenario, not an "undo my mistake" feature. So the confirmation in
      step 6 is the *only* safeguard this plan provides — it has to
      actually stop a wrong tap, not just legally cover one, and its
      copy must say plainly that this can't be undone, not just that
      it's "irreversible" in the fine print. If real accidental-merge
      reports show up after this ships, the next move is a proper
      undo window (e.g. holding the pre-merge member/reassignment data
      for N days before the hard delete) — a deliberately separate,
      later decision, not something to half-build now.
      1. [x] Worker: `GroupDO.mergeMembers(keepId, mergeId)` — reassigns
         `expenses.payer_id`, `expense_splits.member_id`,
         `settlements.from_id/to_id`, `comments.author_member_id`, and
         rewrites each `expenses.payers` JSON blob entry naming `mergeId`
         (a non-primary payer on a multi-payer expense). Refuses
         (`MERGE_CONFLICT`) when `keepId`/`mergeId` already share a split
         on the same expense — built as a `JOIN expense_splits a JOIN
         expense_splits b ON a.expense_id = b.expense_id` overlap check —
         rather than silently summing two people who were genuinely both
         on that expense.
      2. [x] Worker: refuses (`MERGE_CONFLICT`) when both members already
         have a non-null `identity_sub`; otherwise carries over whichever
         of `identity_sub`/`avatar_key`/`upi_vpa` the losing side has via
         `COALESCE` (this last field wasn't in the original plan text —
         added since leaving it behind would silently lose data, the same
         principle the plan already applied to identity/avatar). Then
         hard-`DELETE`s the `mergeId` row.
      3. [x] Worker: one `console.log` line before the delete (group name,
         both member ids + display names, which was kept, timestamp) —
         forensic only, verified appearing in `wrangler`/test stdout.
      4. [x] New route `POST /api/groups/:groupId/members/:memberId/merge`
         body `{ into: <keepMemberId> }`, `MERGE_CONFLICT` mapped to a 409
         alongside `MEMBER_IN_USE` in the shared `domainErrorResponse`.
      5. [x] Kit: `ClanTabClient.mergeMembers(groupId:memberId:into:accessToken:)`
         + `MergeMemberRequest`, reusing the existing `JoinGroupResponse`
         (`{member}`) rather than a new response type.
      6. [x] App: a "Merge…" swipe action on `GroupSettingsView`'s member
         row (shown whenever the group has another member to merge into)
         opens a small dedicated target picker — **not** `MemberPickerView`
         as originally planned: that component's own "Add ‘name’" inline-
         create affordance makes no sense for picking an existing merge
         target, so reusing it would have offered a nonsensical action.
         Picking a target sets up a `.confirmationDialog` titled **"This
         can't be undone"** (plain words, matching "Leave this group?"/
         "Delete Account" elsewhere in this screen), whose message names
         both people and what moves where. Hit the codebase's known
         type-checker complexity ceiling twice while wiring this in
         (`GroupSettingsView.body` — same issue `joinCodeSection`/
         `SettleUpView.upiNudgeSection` document) — fixed by extracting
         the new dialog's closures into named functions and pulling the
         member row and the whole Danger Zone section out into their own
         computed properties, same pattern as the section's existing
         `joinCodeSection`/`defaultSplitSection`.
      7. [x] Worker tests: full reassignment across every table (expense
         payer/splits, a multi-payer entry, a settlement, a comment),
         avatar/UPI carry-over, the self-merge no-op, the
         `expense_splits`-overlap `MERGE_CONFLICT`, both-already-claimed
         `MERGE_CONFLICT` (as a direct `GroupDO` unit test in
         `group.test.ts`, alongside the existing claim-flow tests — that
         one needs `claim()`'s identity plumbing, which `routes.test.ts`'s
         plain access-token auth doesn't exercise), 404s, and the missing-
         `into`-field 400. `make check` green throughout (kit + worker +
         iOS build/tests).
      8. [x] Deployed to production 2026-09-13 (`make worker-deploy`,
         version `b898202f-0cdf-4bde-ac57-d4aff405c971`) — smoke-tested
         live (`POST .../members/x/merge` against an unknown group → 404,
         confirming the route is registered, not a 500/mis-route). The
         app-side UI isn't in any TestFlight build yet — build 11 predates
         this work; folded into the next build once the Owner's current
         round-3 pass on build 11 is done.
- [ ] **Universal, identity-level display name.** `~50-70k` — real
      demand (round-3 playtest, 2026-09-13 — per-group names that can
      change anytime "can lead to confusion"). Decided 2026-09-13: one
      central name, **no** per-group override once built. Grounded
      2026-09-13 against `fanOutAvatar`/`setMemberAvatar`
      (`worker/src/index.ts`, `worker/src/group-do.ts`) — "Profile
      photos" already solved the identical propagation problem for an
      avatar key; this is the same shape for a name.
      1. Worker: `UserDO` gains a `user_meta` key (`display_name` —
         no `USER_SCHEMA_VERSION` bump needed, same as
         `avatar_uploaded_at`) + `displayName()`/`setDisplayName()`.
      2. New route `PATCH /api/auth/profile` body `{ displayName }` →
         `fanOutDisplayName(env, sub, name)`, mirroring
         `fanOutAvatar` exactly: set the `UserDO` value, `listGroups()`,
         then concurrently call a new `GroupDO.setMemberDisplayName(sub,
         displayName)` (`UPDATE members SET display_name = ? WHERE
         identity_sub = ?`, mirrors `setMemberAvatar`) on each.
      3. Worker: `GroupDO.updateMember`'s `displayName` patch path
         becomes claimed-member-proof — only a member with `identity_sub
         IS NULL` (a placeholder) can still be renamed that way; a
         claimed member's name now comes solely from the fan-out. Return
         a new `MEMBER_CLAIMED` error otherwise (defense in depth — the
         client shouldn't offer the option at all, see step 6).
      4. Worker: `claim()` seeds the newly-claimed member's
         `display_name` from the identity's central name when one's
         already set (same "seed from identity" pattern `avatarKey`
         already uses there) — the reverse the very first time: if the
         identity has *no* central name yet, bootstrap it from whatever
         name this claim already carries (the placeholder's typed name,
         or `ClaimMemberView`'s "Your display name" field), so almost
         nobody ever needs to see an explicit "set your name" prompt.
      5. Kit: `Member.isClaimed: Bool` (new, safe to expose — just
         `identity_sub IS NOT NULL`, never the subject itself) so the
         client can tell claimed and unclaimed members apart without
         leaking anything.
      6. App: Settings gains a "Your Name" field (calls the new PATCH);
         `GroupSettingsView`'s "Rename Member" only offered when
         `!member.isClaimed`; `ClaimMemberView`'s "Your display name"
         field only appears on someone's first-ever claim anywhere
         (central name not set yet) — every later claim in another group
         just uses it silently, no prompt.
      7. Decide (owner): whether to run a one-time backfill copying each
         already-claimed identity's most-recently-used per-group name
         into the new central field at deploy time, so day-one behavior
         looks intentional rather than blank, vs. leaving it fully lazy
         (bootstraps the first time step 4 or 6 touches that identity).
- [ ] **Link Apple and Google accounts.** `~90-130k`, the largest of the
      three — real demand (round-3 playtest, 2026-09-13). Each identity
      today is a wholly independent `UserDO` keyed by
      `"<provider>:<sub>"` (`MANDATORY_LOGIN_PLAN.md` Part 2) with no
      linking mechanism, and every `UserDO` lookup everywhere
      (`handleAuthApple`/`Google`, `requireSession`, `opaquePersonId`,
      the Friends aggregation) resolves straight from that composite
      string with no indirection to unwind. Benefits from **merge
      duplicate members** above as a subroutine (step 2b), so build that
      one first if both are ever picked up.
      1. Worker: `UserDO` gains a `linked_to` `user_meta` key — the
         composite identity string of the "primary" identity this one
         now redirects to. One level of indirection only (resolution
         always starts from whichever `UserDO` a session's `sub`
         addresses).
      2. New route `POST /api/auth/link`, called *while signed in* as
         the primary identity: body `{ provider, identityToken,
         authorizationCode? }`, verified via the existing
         `verifyAppleIdentityToken`/`verifyGoogleIdentityToken`, giving
         a second `identity2 = "<provider>:<sub>"`.
         a. `identity2 == primary` → no-op.
         b. `UserDO(identity2)` never signed in before → just set its
            `linked_to = primary` and stop; nothing to merge.
         c. `UserDO(identity2)` already exists (the real case — signed
            in with both separately in the past): for each of its
            memberships not already held by primary in that group, a
            new small `GroupDO.reclaimMember(memberId, fromSub,
            toSub)` (`UPDATE members SET identity_sub = ? WHERE
            identity_sub = ?`, checked that `toSub` doesn't already hold
            a member there) + `primary.addMembership(...)`; for a group
            where *both* identities already separately belong, that's
            exactly the "merge duplicate members" case — call
            `GroupDO.mergeMembers` to fold identity2's member into
            primary's. **This makes the merge automatic, not something
            the person confirms per group** — and merge is permanent
            (see that item's own note on why). So `POST /api/auth/link`
            must return the list of groups this would collapse *before*
            committing (a dry-run pass), and the app shows that list in
            one confirmation before calling it for real — linking two
            accounts is not itself irreversible (the sign-in side can be
            undone) but the member-merges it can trigger are, and that
            has to surface once, plainly, not get buried inside "Link
            Google Account" as a side effect nobody agreed to. Copy
            `identity2`'s `devices` rows onto primary's. Finally strip
            `identity2` down to just `identity`/`linked_to`
            (`deleteAll()` then re-set `linked_to`) — its memberships/
            devices have all moved.
      3. Worker: `handleAuthApple`/`handleAuthGoogle`, right after
         `ensureExists`, check `linkedTo()` — if set, mint the session
         for the **linked** identity and read `listGroups()` from *its*
         `UserDO`, not the one just authenticated against. One extra
         `UserDO` read on every sign-in, for everyone, forever — worth
         calling out as a permanent small cost, not a one-time migration
         detail.
      4. Worker: `handleAuthDeleteAccount` must resolve through
         `linked_to` too. Decide (owner): does deleting a linked
         account delete both identities' access, or does it just unlink
         the secondary back to a blank fresh identity? Needs a real
         answer before this ships, not an implementation detail to
         improvise.
      5. App: Settings gains a "Linked Accounts" section — "Link Google
         Account" (shown only signed in with Apple, no Google linked
         yet) reusing `GoogleSignInButton`'s existing token-producing
         flow but a new `AuthViewModel.linkAccount(provider:
         identityToken:)` completion (calls `/api/auth/link` with the
         *current* session's bearer token — must not go anywhere near
         `signIn()`'s session-replacement path) — and the mirror image
         for "Link Apple Account."
      6. Worker tests: fresh-secondary (2a), both-pre-existing-merge
         (2b/2c full path), sign-in-after-link resolving to primary,
         delete-account-while-linked per whatever step 4 decides.

## Non-goals — will not be built

FX / currency conversion · payment processing or money transfer ·
paid cloud AI.

**Reversed 2026-09-10:** "a second cross-group ledger" was a non-goal
here through 2026-09-09. The friend playtest (round 2 above) surfaced
real demand for private 1:1 tabs + cross-group friend balances —
reopened deliberately, not by drift. Cross-group *settling* still fires
one `addSettlement` per underlying group; the new work is a read-side
aggregation layer plus hidden 2-person groups for 1:1 tabs, not a new
write-side ledger.

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

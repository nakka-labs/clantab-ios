# ClanTab — Mandatory Login Plan (Apple + Google, guests removed)

> Scope locked 2026-09-05 after a brainstorm (see chat). Replaces the
> optional-guest / optional-Sign-in-with-Apple model shipped and documented in
> `ACCOUNTS_DESIGN.md` and `DESIGN.md` §13 — those describe what's live today,
> **not this plan**; they get updated when this ships (see "Docs to update"
> at the bottom), per this repo's own stated discipline of not describing
> unshipped behavior. Phone login was considered and dropped (SMS/OTP cost +
> fraud surface + India DLT registration). Email/password was considered and
> dropped (real infra to build — verification, reset flow, a vendor bill —
> and reintroduces PII this app currently doesn't collect, for the smallest
> reach gain of the three options).

**The shape of the change:** every user must sign in — Apple or Google, no
guest tier — before they can create, join, or view a group. This is a
**client-side gate**, not a change to the server's trust model: `GroupDO`
routes stay `groupId`-possession-only (`DESIGN.md` §2/§8, unchanged,
deliberately — same trust model as Spliit). What changes is who's allowed to
reach those routes from the app at all, and that identity is now always
server-backed instead of sometimes-local.

---

## Part 0 — Decisions this plan assumes (confirm before Part 1 starts)

**Critical finding from simulating real usage (2026-09-05), read this
first:** the backend already supports adding a member by name without that
person doing anything (`DESIGN.md` §2: `POST .../members` is "also how the
app adds a placeholder member") — but **no iOS screen exposes it.** Today
the only way to add someone is for *them* to open the invite link and type
their own name (`JoinGroupView`'s guest path). Once guests are removed
(Part 3), that path is gone entirely, which means every trip/flat/family
group member would need their own Apple or Google account just to *exist*
in the ledger — a real regression for the Android-friend, non-tech-savvy-
relative, and one-off-acquaintance cases that make up a lot of real usage.
**Part 2.5 below (Add Member by name) is not optional polish — it's the
fix that makes removing guests not a regression, and needs to ship
alongside Part 3, not after it.**

- [x] **[OWNER]** Confirm dropping the guest tier is final — **confirmed
      2026-09-04.** This removes `JoinGroupView`'s guest path and the local
      per-device identity store entirely (Part 3 below).
- [x] **[OWNER]** Confirm there are ~zero real signed-in users on the
      current `UserDO` keying yet — **confirmed 2026-09-04: app has never
      left internal TestFlight, no real users.** Part 2's `UserDO`
      re-keying is a clean cutover, no migration script needed.

## Part 1 — Google Sign-In (backend + iOS)

**[OWNER]** Create a Google Cloud OAuth client (OAuth consent screen + an iOS
client ID) in Google Cloud Console — needs a real account, not doable from a
cloud session. No Apple-side capability toggle needed; Guideline 4.8 is
already satisfied since Apple stays offered alongside Google.

1. **[CLI]** Worker: `POST /api/auth/google` mirroring `/api/auth/apple`
   (`DESIGN.md` §13) — verify the Google ID token against Google's JWKS
   (`https://www.googleapis.com/oauth2/v3/certs`, `iss` = Google's issuer,
   `aud` = the client ID from Part 1's owner step, not expired), then the same
   `UserDO.ensureExists` + session-mint path Apple already uses.
2. **[CLI]** iOS: a `GoogleSignInButton` component mirroring
   `Components/AppleSignInButton.swift`, driven by `ASWebAuthenticationSession`
   — **not** the official Google Sign-In SDK, to keep the zero-third-party-
   dependency rule (`AGENTS.md`, `DESIGN.md` §7) that Apple's flow already
   respects. More code than the SDK, same discipline as the rest of the repo.
3. **[CLI]** `AuthViewModel` gains a `signInWithGoogle` path alongside
   `signIn` (Apple), sharing the session-storage/refresh logic already built.

## Part 2 — `UserDO` keying (needed once two providers can both exist)

**Already done, verified 2026-09-05 — no new code needed.** Built as part
of Part 1's Google Sign-In work (`4c7fe7f`): `handleAuthApple` /
`handleAuthGoogle` both build `identity = "<provider>:" + sub` and use it as
`UserDO.idFromName`'s key, `mintSession`'s `sub` claim, and `GroupDO`'s
`members.identity_sub` value — the same composite string end to end
(`index.ts`'s "Every identity is addressed everywhere..." comment above
`handleAuthApple`). An Apple and a Google identity can never collide on the
same underlying `sub`.

1. [x] Change `UserDO`'s addressing to `idFromName(provider + ":" + sub)`.
2. [x] The Apple route already used the composite key from the start of the
   Google Sign-In work — no separate follow-up needed.
3. [x] No `USER_SCHEMA_VERSION` bump / `UserDO.migrate()` needed — Part 0's
   "no real users" confirmation means there's no pre-existing bare-`sub`
   data to migrate off of.

## Part 2.5 — Add Member by name (placeholder, no signup required)

The other half of what makes Part 3 safe to ship. Lets a signed-in member
add someone to the group by name alone — a "treasurer" pattern: one
tech-comfortable person can represent Android users, parents, or a
one-trip acquaintance who'll never install the app. That person can sign
in and claim their placeholder later if they ever want to (existing claim
flow, `ACCOUNTS_DESIGN.md` §6) — nothing about this is a dead end.

1. [x] **[CLI]** A simple "Add Member" action in `GroupSettingsView` (and
   optionally as a step in `CreateGroupView`, so a group can be pre-seeded
   with everyone's names at creation) — a name field, calls the same
   `POST .../members` endpoint the join flow already uses, no identity
   attached. **Done 2026-09-05:** an "Add Someone" section in
   `GroupSettingsView`, calling `client.joinGroup` (the same
   `JoinGroupRequest`/endpoint the guest-join path already used). Verified
   against the real deployed Worker in the simulator — added and removed a
   placeholder member end to end. `CreateGroupView` pre-seeding skipped —
   explicitly optional, and the group-settings entry point already covers
   the regression the plan is worried about.
2. [x] **[CLI]** Test coverage: adding a placeholder, then claiming it later
   via the existing claim flow, still works end to end. **Already covered**
   — `worker/test/auth-routes.test.ts`'s "claim flow" suite adds a
   placeholder via the same `POST .../members` endpoint this feature calls,
   then claims it; no separate iOS UI-test harness exists in this repo for
   view-layer coverage (view models / pure logic are the tested layer here).

## Part 3 — Remove the guest tier (iOS)

**Done 2026-09-05.** This was the biggest simplification in the plan, not
just a removal — a lot of code existed solely to handle "no server-backed
identity yet," and none of it was needed once every user is signed in.
iOS build + test green (60/60, up from 56 — net of one dropped test whose
premise no longer applies, plus five new ones); ClanTabKit's own suite green
(113/113) after `IdentityStore.swift` + its tests were deleted. Verified
live in the Simulator: the sign-in gate itself renders correctly (no "Your
Groups" list, no Create/Join buttons, signed out) — completing an actual
Apple/Google sign-in isn't possible in the Simulator (pre-existing
limitation, `NEXT_STEPS.md` Phase 8), so the create/claim/join-fresh flows
themselves are covered by `AuthViewModelTests` + `RootViewDeepLinkTests`
only, pending the on-device TestFlight pass.

1. [x] **[CLI]** `StartView`: gate `Create a Group` / `Join with a Code` behind
   `auth.isSignedIn` — show only the Apple/Google sign-in buttons until
   signed in. `onOpenSettings` / "Signed in with Apple" row goes away (no
   longer a status to check — everyone's signed in). Also closed a gap this
   item implied but didn't spell out: the start screen's "Your Groups" list
   (backed by the local `knownGroups` cache, which outlives a sign-out) and
   `RootView`'s launch/deep-link routing were still reachable while signed
   out — both are now gated on `auth.isSignedIn` too, with a pending-deep-link
   resumed automatically once sign-in succeeds.
2. [x] **[CLI]** Collapse `JoinChoiceView` + `ClaimMemberView`'s guest branch
   into one screen: pick which existing placeholder member is you, or add
   yourself as a new member — both branches now always claim with an
   identity, there's no more "join as guest" outcome. Deleted
   `JoinChoiceView.swift`; `JoinGroupView` now only resolves a join code to a
   `groupId` and hands off to the merged `ClaimMemberView`.
3. [x] **[CLI]** Retire `IdentityStoring` / `UserDefaultsIdentityStore` (the
   per-device `"clantab:" + groupId` local identity) entirely.
   `GroupViewModel.myIdentity` now derives "my member id in this group" from
   `auth.groups` (`GET /api/auth/groups` already returns `{ groupId,
   memberId, displayName }` per `DESIGN.md` §13) instead of local storage.
   Necessary corollary not spelled out in this item: `CreateGroupView` now
   calls `auth.claim(groupId:memberId:)` right after creating a group, so the
   creator's own membership shows up in `auth.groups` too (best-effort — a
   failure there doesn't block entering the just-created group, which is
   still remembered locally either way).
4. [x] **[CLI]** Update/remove tests that assumed a guest path (deep-link
   resolution, `RootView.resolveDeepLink`'s guest branch — now a 3-way
   `openGroup` / `claimMember` / `needsSignIn` split); add Google sign-in
   tests mirroring the Apple ones (`testSignInWithGoogle*`,
   `testLaunchDecisionGoogle*` — these were missing even after Part 1).

**Deliberately left alone, flagged for a followup:** `AuthViewModel`'s
"sync nudge" (`shouldShowSyncNudge` / `dismissSyncNudge` / `SyncNudgeCard` /
`SyncNudgeStoring`, `ACCOUNTS_DESIGN.md` §10) only ever fires for a
signed-out user — which, after this Part, can no longer reach Group Home at
all. It's dead code now, but removing it wasn't itemized above and is a
separable cleanup (its own files/tests) — left in place rather than folded
into this diff.

## Part 4 — Hardening, now that the repo carries more weight

- [x] **[CLI]** Verify GitHub secret scanning + push protection are on for
      the repo (free on public repos) — cheap safeguard now that there are
      two OAuth providers' worth of secrets in play, not just one. **Done
      2026-09-05:** both were off; enabled via the repo API.

## What sequences after this plan

- `NAV_POLISH_PLAN.md` Parts 1-2 — do after Part 3, so `StartView` is
  reworked once, not twice (`NEXT_STEPS.md` Phase 4).
- `ACCESS_TOKEN_PLAN.md` (new) — the shareable-link/credential-decoupling
  work; cheapest done once Part 2.5's sharing story is final
  (`NEXT_STEPS.md` Phase 3).
- `FEATURE_BACKLOG.md`'s push/widget/Siri items — after Part 2's `UserDO`
  re-keying (`NEXT_STEPS.md` Phase 6).

## Docs to update once this actually ships (not now — matches this repo's
own discipline of not describing unbuilt behavior)

- `DESIGN.md` §13 — "Optional Sign in with Apple" → mandatory, Apple +
  Google, new `/api/auth/google` route, new `UserDO` keying.
- `ACCOUNTS_DESIGN.md` — guest tier removed throughout; §6 claim flow
  simplified per Part 3.
- `PLAN.md` Non-Goals — currently says "No passwords or third-party login.
  Identity is optional Sign in with Apple only" — both halves change
  (Google is a third-party login; it's no longer optional).
- `README.md` architecture diagram + `NEXT_STEPS.md` §5 non-goals list.
- **[OWNER]** `docs/appstore/metadata.md` review notes — currently walk a
  reviewer through "the no-login model," which is about to be false. CLI can
  draft the rewrite; owner approves before submission.

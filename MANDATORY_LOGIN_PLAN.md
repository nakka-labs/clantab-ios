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

1. **[CLI]** Change `UserDO`'s `idFromName(sub)` to `idFromName(provider +
   ":" + sub)` — e.g. `"apple:" + sub`, `"google:" + sub` — so an Apple and a
   Google identity can never collide on the same underlying `sub` value.
   Depends on Part 0's second confirmation.
2. **[CLI]** Update the Apple route's existing `UserDO` calls to the new
   `"apple:" + sub` key for consistency.
3. **[CLI]** Extend `USER_SCHEMA_VERSION` / `UserDO.migrate()` if a
   migration path turns out to be needed (Part 0).

## Part 2.5 — Add Member by name (placeholder, no signup required)

The other half of what makes Part 3 safe to ship. Lets a signed-in member
add someone to the group by name alone — a "treasurer" pattern: one
tech-comfortable person can represent Android users, parents, or a
one-trip acquaintance who'll never install the app. That person can sign
in and claim their placeholder later if they ever want to (existing claim
flow, `ACCOUNTS_DESIGN.md` §6) — nothing about this is a dead end.

1. **[CLI]** A simple "Add Member" action in `GroupSettingsView` (and
   optionally as a step in `CreateGroupView`, so a group can be pre-seeded
   with everyone's names at creation) — a name field, calls the same
   `POST .../members` endpoint the join flow already uses, no identity
   attached.
2. **[CLI]** Test coverage: adding a placeholder, then claiming it later
   via the existing claim flow, still works end to end.

## Part 3 — Remove the guest tier (iOS)

This is the biggest simplification in the plan, not just a removal — a lot
of code exists solely to handle "no server-backed identity yet," and none of
it is needed once every user is signed in.

1. **[CLI]** `StartView`: gate `Create a Group` / `Join with a Code` behind
   `auth.isSignedIn` — show only the Apple/Google sign-in buttons until
   signed in. `onOpenSettings` / "Signed in with Apple" row goes away (no
   longer a status to check — everyone's signed in).
2. **[CLI]** Collapse `JoinChoiceView` + `ClaimMemberView`'s guest branch
   into one screen: pick which existing placeholder member is you, or add
   yourself as a new member — both branches now always claim with an
   identity, there's no more "join as guest" outcome. Delete
   `JoinGroupView`'s guest-join path (dead once nobody reaches it
   unauthenticated).
3. **[CLI]** Retire `IdentityStoring` / `UserDefaultsIdentityStore` (the
   per-device `"clantab:" + groupId` local identity) entirely.
   `GroupViewModel.myIdentity` now derives "my member id in this group" from
   `auth.groups` (`GET /api/auth/groups` already returns `{ groupId,
   memberId, displayName }` per `DESIGN.md` §13) instead of local storage.
4. **[CLI]** Update/remove tests that assumed a guest path (deep-link
   resolution, `RootView.resolveDeepLink`'s guest branch); add Google
   sign-in tests mirroring the Apple ones.

## Part 4 — Hardening, now that the repo carries more weight

- [ ] **[CLI]** Verify GitHub secret scanning + push protection are on for
      the repo (free on public repos) — cheap safeguard now that there are
      two OAuth providers' worth of secrets in play, not just one.

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

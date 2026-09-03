# ClanTab — Accounts Design

> Status: **settled — ready to build.** Resolves every open question in
> `LOGIN_ACCOUNTS_BRIEF.md`; the three points that needed an explicit call
> are decided in §15. Next step is to fold this into `DESIGN.md` (a new
> §13) and `BACKEND_PLAN.md` (new DO + routes), then build per §14. The two
> locked decisions from the brief — Sign in with Apple only, placeholder
> members claimed via invite link — are taken as given.

---

## 0. The shape of the change, in one paragraph

Accounts are **purely additive**. The capability-link model
(`AGENTS.md` §"Zero-Login") is untouched: a group is still addressed by an
unguessable `groupId`, members are still just rows with a display name,
and a guest with the link still reads and writes with no account. What's
new is an **identity layer that sits beside the groups, not in front of
them**: a member row can optionally be linked to an Apple ID, and a new
`UserDO` keeps a thin per-identity index of "which groups, as which
member." Signing in lets you *rediscover* your groups on a new phone; it
never *gates* a group. Nothing about the ledger, the balance math, or the
per-group durability guarantees changes.

---

## 1. Identity storage — a new `UserDO`

**Decision: one Durable Object per Apple identity**, addressed by
`env.USER_DO.idFromName(appleSub)` (Apple's `sub` is opaque, stable, and
~44 chars — fine as a DO name).

```sql
CREATE TABLE user_meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);  -- rows: apple_sub, created_at, schema_version

CREATE TABLE memberships (
  group_id     TEXT PRIMARY KEY,   -- one membership per group per identity
  member_id    TEXT NOT NULL,
  display_name TEXT NOT NULL,      -- denormalised at claim time (names don't change today)
  added_at     INTEGER NOT NULL
);
```

RPC: `ensureExists(sub)`, `listGroups() → [{groupId, memberId, displayName}]`,
`addMembership(groupId, memberId, displayName)`, `removeMembership(groupId)`,
`deleteAll()`.

**Why a DO and not D1/KV:**
- **Read-your-writes.** A single-threaded DO gives the same consistency
  the app already relies on for `GroupDO`. Claim a membership → it's
  immediately in `listGroups`. KV is eventually consistent (bad for this);
  D1 works but adds a new binding type and doesn't solve the cross-store
  consistency problem below any better.
- **The "thin index" mitigation from the brief maps directly:**
  `listGroups` returns groupIds + your member id per group and nothing
  else. Group *contents* still come only from `GET /api/groups/:groupId`.

`PRIMARY KEY (group_id)` enforces "one identity holds at most one
membership per group" (you can't claim two placeholders in the same
group).

---

## 2. Keeping `UserDO` and `GroupDO` consistent

Two stores now record membership. There is no distributed transaction
across DOs, so:

**Decision: `GroupDO` is authoritative; `UserDO` is a self-healing cache.
The Worker always writes `GroupDO` first, `UserDO` second.**

- **Claim:** Worker calls `GroupDO.claim(memberId, sub)` (sets
  `members.identity_sub`, idempotent). On success, `UserDO.addMembership(...)`.
  If the `UserDO` write is lost, the `GroupDO` row is already linked and a
  later re-open of the invite link (or a retried claim, which is
  idempotent) repairs the index.
- **Account deletion:** Worker reads `UserDO.listGroups()`, calls
  `GroupDO.unclaim(memberId, sub)` for each, then `UserDO.deleteAll()`.
- A missed `UserDO` write means one group is temporarily absent from
  `listGroups` — recoverable, low-stakes, and the app already tolerates a
  group that 404s or whose membership changed (`GroupViewModel.groupUnavailable`).

No background reconciliation job in v1. Add one only if drift is observed.

---

## 3. Session / token model

**Decision: a stateless, HMAC-signed session token (our own JWT), 30-day
expiry, no server-side revocation.** (§15.1)

- Sign-in verifies Apple's identity token **once** (see §5), then the
  Worker mints `{ sub, iat, exp }` signed with `HMAC-SHA256` using a new
  secret `env.SESSION_SIGNING_KEY`. `exp = iat + 30 days`.
- Every authed request carries `Authorization: Bearer <token>`. The Worker
  verifies signature + expiry **locally** — no DO round-trip — then
  extracts `sub` and proceeds.
- **Refresh:** `POST /api/auth/refresh` (Bearer) → a fresh token. The app
  calls it on launch when the current token is within ~7 days of expiry.
- **On-device storage:** the Keychain, `kSecAttrAccessibleAfterFirstUnlock`
  (survives a reboot, readable by the launch-time refresh even before the
  user unlocks). Never `UserDefaults`.
- **Revocation, client-side:** on every launch the app calls
  `ASAuthorizationAppleIDProvider.getCredentialState(forUserID:)`; if the
  result is `.revoked` or `.notFound` it discards the stored session and
  drops back to guest mode. So revoking ClanTab in iOS Settings kills the
  session on next launch — no server plumbing.
- **Revocation, server-side:** none. Account deletion invalidates
  *effectively* (the `UserDO` is gone, so anything keyed on `sub` returns
  empty/`404`). "Remotely sign out a phone I can't physically reach" is
  **not supported** — the mitigating facts: the 30-day cap, no PII or
  payment data in the ledger (the existing trust model), and the token
  exposing only groupIds, not contents. Revisit only on a real incident.
- **Rate-limit** `POST /api/auth/apple` per-IP (garbage tokens fail fast
  at JWKS verification, but cap the attempt rate anyway).

**Rejected:** verifying Apple's token per-request (it's ~10-min-lived and
meant for one-time verification); an opaque token stored in `UserDO`
(revocable, but adds a DO lookup to every authed request — not worth it
for this threat model).

---

## 4. Auth surface — hybrid, not "auth on everything"

The brief says "every endpoint that used to trust 'you have the link'
also needs auth middleware now." **We deliberately don't do that** (§15.2),
because the brief also says guests stay first-class forever (§9): if a
guest with the link must still read and write, we cannot require a session
token on the group routes.

**Decision: the capability link stays the group-access credential. The
session token gates only the identity-scoped endpoints.**

| Endpoint | Credential |
|---|---|
| `GET /api/groups/:groupId`, `POST .../expenses`, `POST .../settlements`, `POST .../members` | **groupId possession** (unchanged — you're hitting the URL) |
| `GET /api/groups/resolve/:joinCode` | none (rate-limited, unchanged) |
| `POST /api/auth/apple` | Apple identity token |
| `POST /api/auth/refresh`, `GET /api/auth/groups`, `DELETE /api/auth/account` | **session token** |
| `GET /api/groups/:groupId/claimable`, `POST .../members/:memberId/claim` | **session token** + groupId possession |

A claimed member on a **new phone** with no local link gets their
groupIds from `GET /api/auth/groups` (which required their token), then
uses the existing group routes normally. So the session token is the
authed *way to obtain your groupIds* — it doesn't grant access the
groupId itself doesn't already grant.

**Accepted risk (document in `DESIGN.md` §8 alongside the existing
capability-link trust model):** one session token → every groupId that
identity holds → their whole cross-group ledger history. Bounded by: the
30-day token cap; account deletion nuking the index; and the ledger
carrying only self-chosen display names and integer amounts — no emails,
no phone numbers, no payment details, ever. This is a strictly smaller
attack surface than N per-device local link stores holding the same
groupIds today.

---

## 5. Sign-in flow

```
POST /api/auth/apple
Request:  { identityToken: string }   // the JWT from ASAuthorizationAppleIDCredential
```

Worker:
1. Fetch Apple's public keys (JWKS from `https://appleid.apple.com/auth/keys`),
   **cached** (KV `APPLE_KEYS`, ~24h TTL — Apple rotates keys rarely). This
   is the one external HTTP dependency accounts adds, and it's at sign-in
   only, not per-request.
2. Verify the identity token: signature against the JWKS, `iss ==
   https://appleid.apple.com`, `aud == com.clantab.app`, not expired.
3. `sub` = the verified subject. `USER_DO.idFromName(sub).ensureExists(sub)`
   (creates the DO on first sign-in).
4. Mint a session token (§3).

```
Response: 200 {
  sessionToken: string,
  expiresAt: string,            // ISO 8601
  groups: [{ groupId, memberId, displayName }]   // = UserDO.listGroups()
}
```

Apple returns `email` / `fullName` only on the *first* sign-in ever. We
need **neither** — there's no email in the product, and the claim flow
already names the specific membership. Ignore both.

---

## 6. Claim flow

A **placeholder member** is a `members` row with `identity_sub IS NULL` —
i.e. every member that exists today.

```
GET /api/groups/:groupId/claimable        (Bearer)
Response: 200 { members: [{ id, displayName }] }   // this group's placeholders only
```

```
POST /api/groups/:groupId/members/:memberId/claim   (Bearer)
```

`GroupDO.claim(memberId, sub)`:
- member must exist and be a placeholder → else `NOT_PLACEHOLDER` / `ALREADY_CLAIMED`
- no other member in this group may already have `identity_sub == sub`
  → else `IDENTITY_ALREADY_IN_GROUP`
- set `members.identity_sub = sub`

then `UserDO.addMembership(groupId, memberId, displayName)`.

```
Response: 200 { member: { id, displayName } }
```

**App UX:** opening an invite link while signed in and holding no
membership in that group offers two distinct actions — *"Join as guest"*
(today's flow, creates a fresh placeholder) and *"This is me"* (claim).
Claim shows the `claimable` list → pick → an explicit confirmation naming
the membership ("Link **Priya** to your Apple ID? Priya's expenses and
balance become visible on all your devices.") → `claim`. The `memberId`
is in the request path, so a link forwarded around a group chat can never
auto-claim anyone.

Privacy: `claimable` reveals placeholder names to anyone with the link +
an account — but `GET /api/groups/:groupId` already returns the full
member list to anyone with the link, so this is not a new disclosure.

---

## 7. Multi-device — "my groups"

```
GET /api/auth/groups        (Bearer)
Response: 200 { groups: [{ groupId, memberId, displayName }] }
```

The app's local model changes from a single `@AppStorage("clantab.lastGroupId")`
to a **list of groups**:
- **Signed-in users:** the list is authoritative from the server — fetched
  on launch (with the stored token) and after every claim. `displayName`
  is the denormalised name from the `UserDO` membership row.
- **Guests:** unchanged — the local per-group identity store
  (`UserDefaultsIdentityStore`, keyed on `groupId`) stays exactly as
  today. A guest's groups are whatever links they've opened on this device.

A signed-in user on a fresh install: sign in → `groups` comes back → each
group opens via the normal `GET /api/groups/:groupId` route.

---

## 8. Existing data & migration

**Server:** `GroupDO` schema **v5** — `ALTER TABLE members ADD COLUMN
identity_sub TEXT` (nullable), in place, no rebuild (same pattern as v3/v4).
Every existing member becomes a placeholder, which is exactly their
current status. `RegistryDO` unchanged. No `UserDO` migration — they're
created fresh on first sign-in.

**App:** existing local per-group identities keep working with zero
change. Nothing forces sign-in. A user who signs in later can claim their
pre-existing memberships: the app iterates its locally stored `groupId`s,
calls `claimable` for each, and offers "we found you in these groups —
claim them?" as a one-time convenience.

Placeholder-only groups (no member ever claimed) work forever, unchanged.

---

## 9. Unclaimed placeholder history

**Confirmed: claiming only sets `identity_sub`. Nothing is reassigned.**
Every expense, split, and settlement already keys off `member_id`; the
member row simply gains an identity. Zero data movement.

---

## 10. "Locked out without accounts" — cost

**Guests are supported forever — no limit, no expiry, no gate on group
creation.** Accounts are opt-in recovery for people who want cross-device
sync.

**One nudge, once** (§15.3). A single dismissable card on Group Home the
first time the user reaches their **2nd group or 7 days of use**,
whichever comes first: *"Sign in with Apple to keep your groups if you
switch phones."* Dismiss → never shown again (persisted locally). No
follow-ups. The reasoning: credible recovery is the whole point of this
work, and the people who'd benefit most won't go looking in Settings —
but a user with one group and two days in genuinely doesn't need it yet.

Permanent entry points regardless: a "Sign in to sync across devices" row
on the Start screen and in Settings, and the "This is me" option when
opening a link while signed in.

---

## 11. Account deletion (Apple Guideline 5.1.1(v) — required)

```
DELETE /api/auth/account        (Bearer)
```

1. `UserDO.listGroups()` → `[(groupId, memberId)]`.
2. For each: `GroupDO.unclaim(memberId, sub)` — set `identity_sub = NULL`.
   **The member row, its name, and all its expenses/settlements stay.**
   The member reverts to a re-claimable placeholder; other members'
   balances are untouched.
3. `UserDO.deleteAll()` — a future sign-in with the same Apple ID starts
   fresh.
4. `→ 204`.

**"Only claimed member vs. others still active" — it doesn't matter.**
Deletion never touches shared ledger data. A group where the deleted
account was the only claimed member goes back to all-placeholders
(today's model); a group with other claimed members loses nothing except
that one member reverting to a placeholder.

**Also required for App Store submission:** Apple mandates revoking the
Sign in with Apple token on account deletion
(`POST https://appleid.apple.com/auth/revoke`). This needs Apple Developer
config — a Services ID, a Key ID, and a `.p8` signing key — set as Worker
secrets. No cost, but it's a prerequisite for the submission, not
optional.

**App:** Settings → "Delete Account" → confirmation ("Your groups and
expenses stay. You'll lose cross-device sync and can't recover this
account.") → call the endpoint → clear the local session → done.

---

## 12. Cross-group netting — enabled here, not built here

"Settle across all groups with Bob" (`FEATURE_BACKLOG.md`,
`LOGIN_ACCOUNTS_BRIEF.md`) becomes *possible* once the `UserDO` index
exists — two claimed identities can be matched across the groups they
share. It is a **separate downstream phase**: a read-side aggregation over
those groups, reported per currency (never blended — the multi-currency
decision holds), with the actual settle action still firing ordinary
per-group `addSettlement` calls. Nothing in this document builds it.

---

## 13. New wire surface (summary)

```
POST   /api/auth/apple       { identityToken }                → { sessionToken, expiresAt, groups }
POST   /api/auth/refresh     (Bearer)                         → { sessionToken, expiresAt }
GET    /api/auth/groups      (Bearer)                         → { groups: [{ groupId, memberId, displayName }] }
DELETE /api/auth/account     (Bearer)                         → 204

GET    /api/groups/:groupId/claimable                  (Bearer) → { members: [{ id, displayName }] }
POST   /api/groups/:groupId/members/:memberId/claim    (Bearer) → { member }
```

Error codes (new): `INVALID_APPLE_TOKEN` (401), `INVALID_SESSION` (401),
`ALREADY_CLAIMED` (409), `IDENTITY_ALREADY_IN_GROUP` (409), `UNKNOWN_MEMBER`
(404 on `claim`). `NOT_PLACEHOLDER` folded into `ALREADY_CLAIMED` (step 1).

Existing routes: **unchanged.** (`GET /api/groups/:groupId` may accept an
optional `Bearer` for future use, but needs nothing today.)

**Schema:** `GroupDO` v5 (`members.identity_sub`); new `UserDO`
(`user_meta`, `memberships`).

**New Worker config:**
- `USER_DO` — Durable Object namespace binding. ✅ (wrangler migration `v2`)
- `APPLE_AUDIENCE` — `vars` entry (`com.clantab.app`). ✅
- `SESSION_SIGNING_KEY` — HMAC key for session tokens. A `vars` entry with a
  dev value; **prod must override** with `wrangler secret put SESSION_SIGNING_KEY`.
  ✅ (dev)
- ~~`APPLE_KEYS` — KV namespace (JWKS cache).~~ Dropped — replaced by an
  in-process module-level cache (step 3).
- `SIWA_SERVICES_ID`, `SIWA_TEAM_ID`, `SIWA_KEY_ID`, `SIWA_PRIVATE_KEY` —
  secrets, for token revocation on account deletion. ⬜ **prerequisite for
  submission** (the `DELETE` route stubs revocation with a TODO today).

---

## 14. Build order

1. ✅ **`GroupDO` v5** (2026-09-03) — `members.identity_sub` migration +
   `claim` / `unclaim` / `claimable` / `memberIdentity` ops + tests. No wire
   yet. `claim` is idempotent per sub; errors `ALREADY_CLAIMED` (linked to
   someone else), `IDENTITY_ALREADY_IN_GROUP` (you already hold a membership
   here), `UNKNOWN_MEMBER`. (`NOT_PLACEHOLDER` from §6 folded into
   `ALREADY_CLAIMED` — a non-placeholder member is exactly a claimed one.)
2. ✅ **`UserDO`** (2026-09-03) — `idFromName(appleSub)`; `user_meta` +
   `memberships` tables; `ensureExists` / `exists` / `listGroups` /
   `addMembership` (idempotent per group) / `removeMembership` / `deleteAll`.
   New binding `USER_DO` + wrangler migration tag `v2`. + 5 tests.
3. ✅ **Apple JWT verification** (2026-09-03) — `worker/src/lib/apple-auth.ts`:
   `verifyAppleIdentityToken(token, { audience, now?, fetchJwks? })` → `{ sub }`
   or throws `AppleAuthError`. Web Crypto only (RSASSA-PKCS1-v1_5 / SHA-256),
   checks signature + `iss` + `aud` + `exp`. **Deviation from §5:** the JWKS is
   cached in a module-level variable (per-isolate, 24h TTL, one forced refetch on
   a `kid` miss) instead of KV `APPLE_KEYS` — no binding to provision, verify is
   sign-in-only. `fetchJwks` is injectable for tests. + 15 unit tests
   (`test/auth.test.ts`, shared with step 4) using a generated RSA keypair.
4. ✅ **Session tokens** (2026-09-03) — `worker/src/lib/session.ts`:
   `mintSession(sub, key, now?)` → `{ token, expiresAt }`, `verifySession(token,
   key, now?)` → `{ sub }` or throws `SessionError`. HS256 JWT `{ sub, iat, exp }`,
   `exp = iat + 30d`, constant-time signature compare, no DO hit. Config:
   `SESSION_SIGNING_KEY` + `APPLE_AUDIENCE` as `wrangler.jsonc` `vars` (dev value);
   prod overrides the key via `wrangler secret put SESSION_SIGNING_KEY`.
5. ✅ **Worker routes** (2026-09-03) — `index.ts`: `POST /api/auth/apple`,
   `POST /api/auth/refresh`, `GET /api/auth/groups`, `DELETE /api/auth/account`,
   `GET /api/groups/:groupId/claimable`, `POST /api/groups/:groupId/members/:memberId/claim`.
   `requireSession()` Bearer helper → 401 `INVALID_SESSION`; bad Apple token →
   401 `INVALID_APPLE_TOKEN`. `claim` writes `GroupDO` first, then the `UserDO`
   index. Apple server-to-server token revocation (§11) is stubbed with a TODO —
   needs the `SIWA_*` secrets. + 15 route tests (`test/auth-routes.test.ts`).
6. **iOS** — broken into sub-steps:
   - ✅ **6a — ClanTabKit auth foundation** (2026-09-03). `SessionResponse` /
     `GroupMembershipSummary` / `MyGroupsResponse` / `ClaimableMembersResponse` /
     `ClaimMemberResponse` wire types; `ClanTabClient` gains `signInWithApple` /
     `refreshSession` / `myGroups` / `deleteAccount` / `claimableMembers` /
     `claimMember` (Bearer-header plumbing + a 204-tolerant `performNoContent`);
     `StoredSession` (`token` + `appleUserID` + `expiresAt`, with `isExpired` /
     `needsRefresh`) and `SessionStoring` with `KeychainSessionStore`
     (`kSecAttrAccessibleAfterFirstUnlock`) + `InMemorySessionStore`. +19 tests.
     No UI yet.
   - ✅ **6b — sign-in flow** (2026-09-03). `AuthViewModel` (`@MainActor
     @Observable`): `signIn(identityToken:userID:)` → `client.signInWithApple` →
     persist `StoredSession`; `signOut()` clears locally (no server revocation,
     §3); `handleLaunch()` restores the session, maps
     `ASAuthorizationAppleIDProvider.getCredentialState` to a plain
     `CredentialStanding`, and runs the pure `launchDecision` policy
     (`.keep` / `.refresh` / `.discard` / `.none`) — near-expiry → silent
     `refreshSession`, revoked / gone / expired → drop to guest. `credentialStanding`
     is an injected closure so the policy is unit-tested without a real
     credential. `SignInWithAppleButton` on `StartView` (no scopes requested, §5),
     wired through `RootView` → `ClanTabApp` (owns the VM + `KeychainSessionStore`).
     Entitlement: `com.apple.developer.applesignin` via `project.yml`
     (gitignored, generated). **Prerequisite:** enable the Sign in with Apple
     capability on the App ID in the Apple Developer portal before a TestFlight
     build. +13 tests. Can't drive the real Apple sheet in
     the simulator — the credential-state / refresh / decision logic is covered
     by unit tests (`AuthViewModelTests`); the button + build are verified.
   - ✅ **6c — group-list model** (2026-09-03). `@AppStorage("clantab.lastGroupId")`
     is gone. New `KnownGroupsStore` (ClanTabKit): `KnownGroup { groupId, name,
     lastOpenedAt }`, `KnownGroupsStoring` (`all()` newest-first / `remember` /
     `forget`), `UserDefaults`- and in-memory impls. It's the guest's source of
     truth and a signed-in user's offline cache. `AuthViewModel` gains
     `identityStore` + `knownGroups` and `applyGroups()` — fans the server list
     into both local stores (seeds a `GroupIdentity` only when absent, so a
     guest identity is never clobbered); `refreshGroups()` (calls `myGroups`,
     `INVALID_SESSION` → sign out) runs on launch for a surviving session and
     will re-run after a claim (6d). `RootView` reads a merged
     `knownGroups.all()` list; auto-resumes only when exactly one group is
     known, otherwise the start screen shows a "Your Groups" list. `GroupHomeView`
     caches the group name into the store on load; `enterGroup` bumps recency,
     `leaveGroup` (404) forgets. +10 tests (`KnownGroupsStoreTests` ×7,
     `AuthViewModelTests` seeding ×3), 3 existing adjusted. Verified in the simulator:
     create → deep-link-join a 2nd group → relaunch shows both in the list →
     tapping opens the group.
   - ✅ **6d — claim UI** (2026-09-03). New routes `.chooseJoin(groupId)` /
     `.claimMember(groupId)`. `resolveDeepLink` gains an `isSignedIn` dimension:
     a member on this device → open; no membership + signed in →
     `JoinChoiceView` ("This is me" vs "Join as a guest"); no membership + guest
     → today's join flow (unchanged). `ClaimMemberView` fetches
     `claimableMembers`, lists them, confirms ("Link **Priya** to your Apple ID?
     Priya's expenses and balance become visible on all your devices."), then
     `AuthViewModel.claim(groupId:memberId:)` → `claimMember` → seed the identity
     locally + `refreshGroups()`. Empty list / 409 both fall back to "join as a
     guest". +6 tests (`resolveDeepLink` ×2, `AuthViewModel.claim` ×3, +1
     adjusted). Build-verified + logic-tested; the chooser/claim screens can't
     be screenshot-verified without a real device (SIWA doesn't run in the
     simulator). Guest deep-link path re-verified unbroken.
   - ✅ **6e — the one-time nudge card** (2026-09-03). `SyncNudgeStore`
     (ClanTabKit): `firstLaunchAt` (recorded once, on `handleLaunch`) + `dismissed`,
     `UserDefaults` + in-memory impls. `AuthViewModel.shouldShowSyncNudge(now:)`
     — a guest, not dismissed, who's reached `nudgeGroupCount` (2) groups **or**
     `nudgeAfter` (7 days); `dismissSyncNudge()` mirrors into observable
     `syncNudgeDismissed` so the card vanishes reactively. `SyncNudgeCard` on
     Group Home (top section) with a dismiss ✕ and an inline
     `AppleSignInButton` — a new reusable component that also replaced
     `StartView`'s inline SIWA glue. +11 tests (`SyncNudgeStoreTests` ×3,
     `AuthViewModel` nudge ×6, `handleLaunch` first-launch ×1, +1 helper).
     Verified in the simulator: guest with 2 groups sees the card on Group Home
     → ✕ removes it → stays gone across relaunch and other groups.
   - ✅ **6f — Settings + delete-account** (2026-09-03). `SettingsView` (modal,
     owned by `RootView`, reachable from a gear on Group Home and the "Signed in"
     row on the start screen): Account section — guests get the permanent
     sign-in row (§10), signed-in users get "Sign Out" and, in its own section,
     **"Delete Account"** (destructive) with a confirmation dialog and the
     "your groups and expenses stay" caveat (Apple 5.1.1(v), §11); plus a
     Version row. `AuthViewModel.deleteAccount()` → `client.deleteAccount(token:)`
     → `signOut()` (an `INVALID_SESSION` response is treated as already-done; any
     other error keeps the session). +4 tests. Guest Settings verified in the
     simulator; the signed-in view + delete flow are logic-tested (SIWA can't
     run in the simulator). **Step 6 complete.**
7. ✅ **Docs** (2026-09-03). `DESIGN.md` — new **§13 (accounts / auth
   surface)**, plus §7 (identity layer), §8 (session-token exposure, bounded),
   §10 (`UserDO` schema), §12 (shipped bullets). `AGENTS.md` — "no accounts"
   → "guests + optional Sign in with Apple, additive, never gate the group
   routes". `worker/README.md` — `user-do.ts` / `lib/apple-auth` / `lib/session`,
   103-test count, accounts config. `PLAN.md`, `README.md` (intro, architecture
   diagram, repo layout), `READINESS_CHECKLIST.md` (accounts → code-complete,
   owner tasks listed). **Accounts build complete.**

Rough sizing (actual): steps 1–5 (backend) ≈ 2 sessions; step 6 (iOS) ≈ 3
sessions; step 7 ≈ half a session.

---

## 16. Not code — owner tasks before accounts can ship

1. **Deploy the worker** — `make worker-deploy`, then
   `wrangler secret put SESSION_SIGNING_KEY` (the deployed instance is still
   pre-accounts).
2. **Enable Sign in with Apple** on the `com.clantab.app` App ID in the Apple
   Developer portal (the entitlement is in `project.yml`, but the capability
   must be turned on server-side too).
3. **Apple token revocation** — create a Services ID + Key ID + `.p8`, set
   `SIWA_SERVICES_ID` / `SIWA_TEAM_ID` / `SIWA_KEY_ID` / `SIWA_PRIVATE_KEY` as
   Worker secrets, and wire `POST https://appleid.apple.com/auth/revoke` into
   `DELETE /api/auth/account` (§11 — Apple mandates this for submission).
4. **TestFlight pass on a real device** — the Sign in with Apple sheet, the
   claim flow, and `getCredentialState` can't be exercised in the simulator.
5. **Privacy** — update `docs/privacy-policy.md` and the App Store Connect App
   Privacy answers to cover Sign in with Apple (`READINESS_CHECKLIST.md`).

---

## 15. The three judgement calls — decided

**15.1 Session tokens → stateless, 30-day, no server-side revocation.**
The ledger carries no PII and no money movement; the worst case from a
leaked token is someone seeing display names and amounts in groups you're
in. That doesn't justify making the Worker stateful (an opaque token in
`UserDO` costs a DO read on every authed request). The "I want out" path
is covered client-side by the `getCredentialState` launch check (§3) plus
account deletion. Server-side per-device revocation is a "revisit on a
real incident" item, not a v1 requirement.

**15.2 Auth model → hybrid; the capability link stays the group
credential.** Frictionless guests are *why* the placeholder-member
decision exists. Gating group access behind identity would either lock
guests out of the trip-with-non-app-users case or force a second parallel
access model anyway. The hybrid is those two models cleanly layered:
`groupId` possession = access, session token = "find my groupIds." The
privacy exposure (one token → all your groupIds) is real but bounded —
thin index, no contents, 30-day cap, no PII — and strictly smaller than
the N per-device link stores holding the same groupIds today.

**15.3 Nudging → exactly one dismissable prompt, at the 2nd group or 7
days.** Not zero (recovery is the point of the feature and its target
users won't self-serve), not recurring (a user with one group and two
days in doesn't need it). See §10.

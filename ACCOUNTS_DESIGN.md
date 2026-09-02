# ClanTab — Accounts Design

> Status: **proposal for review.** Resolves every open question in
> `LOGIN_ACCOUNTS_BRIEF.md` with a decision + rationale. Once signed off,
> this folds into `DESIGN.md` (a new §13) and `BACKEND_PLAN.md` (new DO +
> routes). The two locked decisions from the brief — Sign in with Apple
> only, placeholder members claimed via invite link — are taken as given.
>
> **Needs your explicit sign-off** (flagged inline as ⚠️): the hybrid auth
> model (§4), and the stateless 30-day session token with no per-device
> revocation (§3).

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

⚠️ **Decision: a stateless, HMAC-signed session token (our own JWT), 30-day
expiry, no per-device revocation.**

- Sign-in verifies Apple's identity token **once** (see §5), then the
  Worker mints `{ sub, iat, exp }` signed with `HMAC-SHA256` using a new
  secret `env.SESSION_SIGNING_KEY`. `exp = iat + 30 days`.
- Every authed request carries `Authorization: Bearer <token>`. The Worker
  verifies signature + expiry **locally** — no DO round-trip — then
  extracts `sub` and proceeds.
- **Refresh:** `POST /api/auth/refresh` (Bearer) → a fresh token. The app
  calls it on launch when the current token is within ~7 days of expiry.
- **Revocation:** stateless tokens can't be individually revoked. Account
  deletion invalidates *effectively* — the `UserDO` is gone, so anything
  keyed on `sub` returns empty/`404`. "Sign out a stolen device remotely"
  is **not supported in v1** — the mitigating facts: 30-day cap, no PII or
  payment data in the ledger (the existing trust model), and the token
  only exposes groupIds, not contents.

**Rejected:** verifying Apple's token per-request (it's ~10-min-lived and
meant for one-time verification); an opaque token stored in `UserDO`
(adds a DO lookup to every request).

---

## 4. Auth surface — hybrid, not "auth on everything"

⚠️ The brief says "every endpoint that used to trust 'you have the link'
also needs auth middleware now." **This proposal disagrees**, because the
brief also says guests stay first-class forever (§9). If a guest with the
link must still read and write, we cannot require a session token on the
group routes.

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

**Confirmed: guests are supported forever, no nudge, no limit, no
expiry.** Accounts are opt-in recovery for people who want cross-device
sync. The only surfaces that *mention* accounts:
- a "Sign in to sync across devices" row on the Start screen and in
  Settings,
- the "This is me" option when opening a link while signed in.

No gate on group creation, no cap on guest groups, no reminder.

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

Error codes (new): `INVALID_APPLE_TOKEN`, `INVALID_SESSION`,
`NOT_PLACEHOLDER`, `ALREADY_CLAIMED`, `IDENTITY_ALREADY_IN_GROUP`.

Existing routes: **unchanged.** (`GET /api/groups/:groupId` may accept an
optional `Bearer` for future use, but needs nothing today.)

**Schema:** `GroupDO` v5 (`members.identity_sub`); new `UserDO`
(`user_meta`, `memberships`).

**New Worker config:**
- `USER_DO` — Durable Object namespace binding.
- `SESSION_SIGNING_KEY` — secret (HMAC key for session tokens).
- `APPLE_KEYS` — KV namespace (JWKS cache).
- `SIWA_SERVICES_ID`, `SIWA_TEAM_ID`, `SIWA_KEY_ID`, `SIWA_PRIVATE_KEY` —
  secrets, for token revocation on account deletion.

---

## 14. Build order

1. **`GroupDO` v5** — migration + `claim` / `unclaim` / `claimable` /
   `memberIdentity` ops + tests. No wire yet.
2. **`UserDO`** — the DO + its RPC + tests.
3. **Apple JWT verification** — JWKS fetch + cache, claim validation,
   tested against a fixture token.
4. **Session tokens** — HMAC mint/verify + tests.
5. **Worker routes** — `/api/auth/*`, `claimable`, `claim` + `routes.test.ts`.
6. **iOS** — `AuthenticationServices` SIWA button; session token in the
   Keychain; the group-list model change; the claim UI; Settings +
   delete-account.
7. **Docs** — `DESIGN.md` §13, `AGENTS.md` (the "no accounts" line becomes
   "hybrid: guests + optional Sign in with Apple"), `PLAN.md`, `README.md`.

Rough sizing: steps 1–5 (backend) ≈ 2–3 focused sessions; step 6 (iOS)
≈ 2 sessions; step 7 ≈ half a session.

---

## 15. Open for your call

- **§3** — 30-day stateless token, no remote sign-out. Acceptable, or do
  you want opaque tokens in `UserDO` (revocable, +1 DO read per request)?
- **§4** — hybrid auth (capability link stays the group credential).
  Acceptable, or do you want identity to actually gate group access
  (breaks the frictionless-guest flow)?
- **§10** — zero nudging toward accounts. Confirm, or do you want a gentle
  "sign in to protect your groups" prompt after N groups / N days?

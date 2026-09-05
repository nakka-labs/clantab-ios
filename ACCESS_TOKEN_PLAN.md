# ClanTab — Access Token Plan (decouple shareable credential from DO identity)

> Scope locked 2026-09-05 after a brainstorm (see chat) and a grounding pass
> over `worker/src/index.ts` / `worker/src/group-do.ts`. Sequenced after
> `MANDATORY_LOGIN_PLAN.md` Parts 2/2.5 in `NEXT_STEPS.md` Phase 3 — not a
> hard dependency (today's Bearer+claimed-member auth already works), but
> cheapest built once against the final "Add Member by name" sharing story
> instead of twice.

**The problem:** `groupId` possession is the *only* credential for every
group-data route (`DESIGN.md` §2/§8, deliberate design — same model as
Spliit/Kittysplit). That's fine for the trust model itself, but it means a
link or 6-character code, once shared, **can never be revoked** without
losing the group's data identity — there's no way to say "that old link is
dead, mint a new one" the way you'd rotate a leaked password. Removing a
member today doesn't revoke their link-based access either (a related gap,
worth knowing about even though this plan doesn't fully close it — a
removed member who kept the link can still read/resolve the group unless
the link itself is rotated).

**The fix:** separate the thing you *share* (a rotatable access token) from
the thing that *permanently identifies the group's data* (`groupId`, the
Durable Object name — never changes, that's what keeps the ledger stable).

## Grounding (why this is cheaper than it first sounded)

- `requireGroup(env, groupId)` in `worker/src/index.ts` is a single,
  centralized helper every group-data route already calls — one chokepoint
  to add token verification, not a scattered change across every handler.
- `group_meta` (`group-do.ts`) is a plain key-value table (`SELECT value
  FROM group_meta WHERE key = ?` / upsert), the same pattern already used
  for `schema_version`. A new `access_token` key needs **no formal schema
  migration** — just a new row.
- The accounts system already has a `bearerToken`/`requireSession` pattern
  for the Bearer-auth surface — reusable as the "Bearer OR access-token"
  dual-auth check this plan needs.

Revised effort estimate after reading the actual code: **~1.5-2.5 days**
(down from an initial, ungrounded "2-4 days" guess).

## Part 1 — Server: separate the token from the groupId

**Done 2026-09-05.** Confirmed with the user before building: query-param
transport (`?token=`) and the Bearer-fallback for claimed members, both as
described below. Worker tests green (153/153, up from 145 — `group.test.ts`
gets a dedicated "access token" suite, `routes.test.ts` and
`auth-routes.test.ts` updated throughout to carry the token now that every
group they create has one). `wrangler deploy --dry-run` validates.

1. [x] **[CLI]** `initGroup` generates a random `access_token` (22 chars over
   the existing 64-symbol id alphabet, ~132 bits — `newAccessToken()`,
   `lib/ids.ts`) and stores it in `group_meta` alongside creation
   (`META_KEYS.accessToken`). Returned from both `initGroup` and `getState`
   via `GroupSummary.accessToken` — nullable, `null` only for a group that
   predates this feature (see Part 4).
2. [x] **[CLI]** `requireGroup` accepts the token as a `?token=` query param
   alongside `groupId`; compares against `GroupDO.currentAccessToken()`.
   `groupId` alone, with no token or the wrong one, → 403 `FORBIDDEN` — but
   *only once a group actually has a stored token*; a group with none
   (pre-existing) stays open, unchanged. Existing Bearer-session auth is a
   valid alternate path for a **claimed member**: `optionalSessionSub` +
   `GroupDO.hasClaimedMember(sub)` — additive, not a replacement, and the
   reason a second device that only ever synced via `GET /api/auth/groups`
   (never saw the original link/code) still works.
3. [ ] **[CLI]** `AppConfig.groupShareURL` / capability-link generation
   includes the token in the generated link. **Deferred to Part 2 (iOS).**
4. [x] **[CLI]** A "Regenerate Link" action: `POST
   /api/groups/:groupId/regenerate-link` (`requireGroup`-gated, same flat
   trust model as every other group route — no special "owner" tier) calls
   `GroupDO.regenerateAccessToken()`, which rotates `access_token` in
   `group_meta` — every previously shared link/code stops working
   immediately. Also the lazy-mint path for Part 4's backward-compatible
   groups. iOS UI for this is Part 2.

## Part 2 — iOS: carry + regenerate

**In progress 2026-09-05, split into smaller commits.** Foundation done: the
network layer that will carry the token, committed and tested (ClanTabKit
116 → 117 tests). Still to do: actually wiring it through `RootView`'s
screens/view models, and the `GroupSettingsView` "Regenerate Link" UI.

1. [x] **[CLI, foundation]** `ClanTabClient`'s group-data methods
   (`fetchGroupState`, `joinGroup`, `addExpense`/`addSettlement`,
   `updateGroup`/`renameMember`/`removeMember`, the edit/delete methods,
   `claimableMembers`/`claimMember`) all gain an `accessToken: String? = nil`
   parameter, appended as `?token=`; a new `regenerateLink(groupId:accessToken:)`
   method. `GroupSummary`/`ResolveJoinCodeResponse` carry `accessToken` on the
   wire. `KnownGroup` gains an `accessToken` field — `remember(...)` updates it
   only when given a non-nil value, so a caller without the current token
   (e.g. mirroring `GET /api/auth/groups`, which doesn't return one) never
   clobbers one learned elsewhere. `AppConfig.groupShareURL` embeds it.
   [ ] **Not yet done:** actually threading it through `RootView` /
   `GroupViewModel` / `CreateGroupView` / `JoinGroupView` / `ClaimMemberView`
   / `GroupHomeView` so a real request ever carries a real token.
2. [ ] **[CLI]** `GroupSettingsView` gains "Regenerate Link" with a clear
   warning dialog — this is destructive to anyone still holding the old
   link/code, not undoable.
3. [ ] **[CLI]** `RootView.resolveDeepLink` / `extractGroupId` parse the token
   portion of a shared URL, not just the groupId.

## Part 3 — Join-by-code stays evergreen

**Done 2026-09-05.** `worker/test/routes.test.ts` gets 2 more cases (returns
the current token; still current after a regenerate). 154/154 green.

1. [x] **[CLI]** `resolveJoinCode` (`worker/src/lib/join-codes.ts`, Workers KV —
   moved off `RegistryDO` in `SHIP_PLAN.md` Track 3 §3) already maps code →
   groupId; the lib itself is unchanged — `handleResolveJoinCode` in
   `index.ts` (which already holds `env.GROUP_DO`) fetches
   `GroupDO.currentAccessToken()` for the resolved `groupId` and includes it
   in the response, so a 6-character code keeps working across a link
   rotation (codes are typed fresh each time, not bookmarked — direct links
   are the thing that goes stale on rotation) — codes as the "always
   current" fallback, links as the revocable one, confirmed as the intent.

## Part 4 — Migration for existing groups

1. [x] **[OWNER → decided 2026-09-05]** Backward-compatible, per the plan's
   own framing ("trivial either way given today's near-zero real user
   count") — implemented as part of Part 1, not a separate step: a missing
   `access_token` in `group_meta` means "open access" (today's behavior,
   `requireGroup` skips the check entirely) until the group visits
   "Regenerate Link" once, which lazily mints one via the same
   `regenerateAccessToken()` call. No deploy-time backfill script.

## Explicitly not doing here

- Not changing who can *see* a group once they have a valid token/groupId —
  the `groupId`-possession trust model itself is unchanged, deliberately
  (`DESIGN.md` §8). This plan is about revocability, not a different trust
  model.
- Not building per-member scoped tokens (e.g. "this link can view but not
  edit") — out of scope, no signal it's needed yet.

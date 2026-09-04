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

1. **[CLI]** `initGroup` generates a random `access_token` (e.g. 22-char
   base62) and stores it in `group_meta` alongside creation.
2. **[CLI]** `requireGroup` accepts the token (query param or header)
   alongside `groupId`; compares against the stored value. `groupId` alone,
   with no token or the wrong one, → 403. (Existing Bearer-session auth for
   claimed members stays a valid alternate path — this is additive, not a
   replacement.)
3. **[CLI]** `AppConfig.groupShareURL` / capability-link generation
   includes the token in the generated link.
4. **[CLI]** A "Regenerate Link" action: worker endpoint rotates
   `access_token` in `group_meta`; every previously shared link/code stops
   working immediately.

## Part 2 — iOS: carry + regenerate

1. **[CLI]** Persist the token alongside `groupId` everywhere `groupId` is
   stored locally (`KnownGroup`, deep-link resolution).
2. **[CLI]** `GroupSettingsView` gains "Regenerate Link" with a clear
   warning dialog — this is destructive to anyone still holding the old
   link/code, not undoable.
3. **[CLI]** `RootView.resolveDeepLink` / `extractGroupId` parse the token
   portion of a shared URL, not just the groupId.

## Part 3 — Join-by-code stays evergreen

1. **[CLI]** `RegistryDO`'s join-code resolution (`registry-do.ts`) already
   maps code → groupId; extend it to also return the *current*
   `access_token`, so a 6-character code keeps working across a link
   rotation (codes are typed fresh each time, not bookmarked — direct links
   are the thing that goes stale on rotation). Confirm this matches the
   intent before building: codes as the "always current" fallback, links as
   the revocable one.

## Part 4 — Migration for existing groups

1. **[OWNER]** Pick one — trivial either way given today's near-zero real
   user count:
   - Backward-compatible: a missing `access_token` in `group_meta` means
     "open access" (today's behavior) until the group owner visits
     `GroupSettingsView` once, which lazily mints one; or
   - A one-time deploy-time pass that mints tokens for every existing group
     up front.

## Explicitly not doing here

- Not changing who can *see* a group once they have a valid token/groupId —
  the `groupId`-possession trust model itself is unchanged, deliberately
  (`DESIGN.md` §8). This plan is about revocability, not a different trust
  model.
- Not building per-member scoped tokens (e.g. "this link can view but not
  edit") — out of scope, no signal it's needed yet.

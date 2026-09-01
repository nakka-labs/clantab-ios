# ClanTab Login / Accounts — Brief

> Status: **decision locked, design not yet written.** This is the pickup
> point for turning the zero-login model into a real-accounts model.
> `DESIGN.md`, `BACKEND_PLAN.md`, `PLAN.md`, `AGENTS.md`, and `README.md`
> all still describe the *old* no-login model below — none have been
> touched for this change yet.

## Why this exists

The zero-login, capability-link model (`AGENTS.md` §"Zero-Login /
Capability Links": groupId + joinCode, identity stored locally per device)
was a deliberate architecture choice. It's now blocking a hard requirement:
credible account recovery and switching phones. A user who loses their
phone or upgrades currently has no way back into their groups — that's not
acceptable for an app meant to be taken seriously and used for real.

## Decision (locked — do not re-litigate)

1. **Sign in with Apple only.** No email/password, no other OAuth
   providers (Google, etc.), no magic links. One identity provider,
   matching Apple's own "if you offer social login you must offer Sign in
   with Apple" rule trivially since it's the *only* option.
2. **Placeholder members, claimed via invite link.** A group member can
   exist as a placeholder (name only, no auth — today's model) and later
   become a real account by claiming that membership through the group's
   invite link, authenticating with Sign in with Apple. This preserves the
   "add anyone to a group instantly, no signup friction" flow that makes
   the app usable for e.g. a trip where not everyone wants to install
   anything or make an account up front — it layers accounts on top
   instead of gating group creation behind them.

## What's still open (needs a DESIGN.md-style pass before building)

- **Identity storage.** Current backend is Durable-Object-per-group
  (`RegistryDO`, `GroupDO` — see `BACKEND_PLAN.md` §3-4). Real accounts
  need an Apple-user-id → identity mapping that's *not* per-group (a
  person can be in many groups). Likely a new `UserDO` or a lightweight
  KV/D1 lookup keyed on Apple's stable user identifier.
- **Session/token model.** Apple gives an identity token (JWT) on
  sign-in. Need to decide: verify it server-side per-request, or issue our
  own short-lived session token after verifying Apple's once. Given the
  Worker is stateless-per-request today, probably the latter.
- **Claim flow mechanics — decided.** Not name-matching, not auto-claim on
  device. Claiming is an explicit, separate action from "join as guest":
  the person opening the invite link picks *which specific placeholder
  membership* they're claiming, gets a confirmation prompt naming that
  membership before it's linked to their Apple ID, and the action is
  distinct from the existing "join group" flow so a link forwarded around
  a group chat doesn't silently let anyone claim anyone.
- **Multi-device for a claimed member.** Once claimed, does the same
  Apple ID on a second device see the same groups? This is the actual
  point of the whole change, so the answer needs to be yes, and needs a
  "GET my groups" endpoint keyed on the verified Apple identity — doesn't
  exist today (today everything is discovered via groupId/joinCode
  the device already has stored locally).

  **This is a real architecture shift, not a bolt-on — worth naming
  plainly.** Today's capability-link model means knowing nothing about a
  person tells you nothing about what groups they're in; each group's
  exposure is scoped to its own link. A "my groups" index tied to one
  Apple ID turns that into a single point that maps a person to every
  group they've ever split money in — compromise one session token (or
  one legal request) and you're looking at their whole ledger history,
  not one group's. Mitigation: keep the index thin — it returns groupIds
  only, resolved through the existing per-group endpoints (which keep
  their own access checks), never a fat blob of every group's contents in
  one response. Every endpoint that used to trust "you have the link"
  also needs auth middleware now, and the index needs to stay consistent
  as memberships are added/claimed/removed — a second membership
  representation to keep in sync with the DO-per-group state.
- **Existing local-only data.** Today's `App/` stores identity locally per
  group (per `AGENTS.md`). Migration path for members who already have
  local groups pre-dating accounts needs a decision — probably: nothing
  breaks, placeholder-member groups keep working exactly as now, claiming
  is purely additive and opt-in.
- **Unclaimed placeholder members' history.** If a placeholder member has
  existing expenses/settlements and later gets claimed, does anything
  need to be reassigned or is the membership row itself just gaining an
  identity? (Leaning: just gaining an identity — the ledger already keys
  off memberId, not identity.)
- **What "locked out without accounts" actually costs us.** Worth
  confirming before building: do unclaimed placeholder members remain
  fully supported forever (the trip-guest case), or is there a nudge/limit
  pushing toward claiming? Leaning toward: fully supported forever, no
  nudge — accounts solve recovery for people who want it, they don't
  become mandatory.
- **Account deletion (Apple review requirement, not optional).** Guideline
  5.1.1(v): any app offering account creation must offer in-app account
  deletion, not just sign-out. Needs a real answer before build, not
  after: what happens to a group where the deleted account was the only
  claimed member vs. one with other claimed members still active?
- **Cross-group netting — confirmed as a downstream phase.** "Settle
  across all groups with Bob": one combined view of what's owed between
  two identities across every group they share, not per-group only
  (per-group minimal-transaction settling already exists — `PLAN.md`
  §2). Depends entirely on the groupId-per-identity index above — name
  matching can't tell two different groups' "Bob" apart, only a claimed,
  linked identity can, so this literally cannot ship before accounts do.
  Reported per-currency, never blended (see `FEATURE_BACKLOG.md`'s
  multi-currency decision — no FX conversion, so "combined" means
  multiple currency totals, not one number). The settle action itself
  stays a set of ordinary per-group `addSettlement` calls through the
  existing write path — this is a read-side aggregation, not a new
  ledger, so it doesn't touch the durability/correctness guarantees
  `DESIGN.md` already makes per group.

## Docs to update once the design above is settled

`DESIGN.md` (the wire/storage contract — needs a new §for auth), 
`BACKEND_PLAN.md` (new DO/KV + endpoints), `PLAN.md` and `AGENTS.md`
(both currently state "no accounts, login systems, or passwords" as a
hard product description — needs updating to reflect the hybrid model),
`README.md` (public-facing "no-login" framing).

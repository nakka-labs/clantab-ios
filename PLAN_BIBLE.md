# Nakka-Labs — Plan Bible

> Status: the one file to read before starting or replanning any app in
> this portfolio. Captures how planning actually happens here — not what
> to build, `PLAN_BIBLE.md`'s counterpart is `DESIGN_BIBLE.md` for how it
> looks. App-agnostic; lives in `clantab-ios` for now since it's the only
> connected repo, same reasoning as `DESIGN_BIBLE.md` — copy or point to
> this file from any future project, don't rewrite it per-repo.

## Why a shared process, not just shared style

`DESIGN_BIBLE.md` keeps four apps looking related without shared code.
This does the same job for *planning* — so a new project's docs don't
reinvent (or worse, half-invent) the same structure, and so a session
picking up a cold project can tell instantly what's decided, what's open,
and who's blocked on what.

## 1. Brainstorm → Lock → Execute — never skip to a checklist

Real scope gets discussed and critiqued before it becomes a plan doc. A
plan doc opens with a locked-and-dated banner ("Scope locked 2026-09-05
after a brainstorm") — that's the signal the discussion phase is over and
execution can start. Skipping straight to a checklist for anything with
real design decisions in it (not a one-line fix) produces a plan built on
untested assumptions.

## 2. Brainstorming has to be honest, not agreeable

A brainstorm that only validates isn't one. Name the worse option, the
real risk, the thing that'll bite later — before the user has sunk cost
into a direction. Critique is the value; agreement is the easy failure
mode.

## 3. Cost is two different currencies

₹ (real money) and effort (time/CLI work) are not the same axis and get
asked about separately. "Cheap" without qualifying which currency is a
category error. The default bias: grind through real effort rather than
spend ₹ — a harder-but-free implementation beats an easier-but-paid one
(hand-rolled OAuth over a paid SDK, on-device work over a metered API,
free-tier infra over a pricier managed service). Effort-only items
default toward yes; a ₹ cost only clears when there's no reasonable
effort-only path around it, and even then it's a real decision, not an
assumed one.

## 4. Every actionable item is tagged [CLI] or [OWNER]

**[CLI]** — the agent can do it alone: code, docs, research, grounding an
estimate in real source. **[OWNER]** — needs a human: an account, a
real-world decision, an app-store click, a tool the agent doesn't have.
Tag every item, in every doc, not just the master index — an untagged
item is an ambiguous item, and ambiguity here is what stalls a project
waiting on the wrong party.

## 5. One checklist per project, full stop — not one-per-feature

Doc sprawl — a plan doc per feature, each with its own "suggested order,"
its own status banner, half of them stale — is a recurring, real failure
mode past 2-3 plan docs, not a hypothetical (it happened here: eleven
planning docs collapsed into one `CHECKLIST.md` on 2026-09-07). One file
per project holds every open to-do and a condensed done history — nothing
else gets created to track sequencing or status, ever, no matter how
tempting a "just for this feature" doc feels in the moment. This is
stricter than "pick one index and let detail docs keep their own order"
— there are no detail docs for *planning* anymore, only the checklist.

This doesn't reach docs that aren't planning/tracking docs: a technical
contract (`DESIGN.md`) or a visual-identity contract (`DESIGN_BIBLE.md`)
is a living reference other code and decisions point to, not a status
tracker, and stays its own file. The test: if the doc's job is "what's
left and what's done," it belongs in the one checklist; if its job is
"how this actually works" or "how this should look," it's a contract, not
sprawl.

## 6. Sequence to minimize rework, not calendar time

When two pieces of work touch the same code or screen, the more
foundational one goes first — even if that makes a smaller, tempting
polish item wait. A slower, single high-quality release beats several
partial ones; it's fine for the timeline to stretch to avoid building the
same thing twice.

## 7. Simulate real usage before calling scope done

Walk concrete user scenarios end to end — not "does the checklist item
exist" but "what actually happens when someone loses their phone
mid-trip." Real gaps show up in a walkthrough, not in a feature-list
review. Do this before declaring a plan complete, not after something
ships and a user finds it.

## 8. Ground technical claims in the actual code before estimating

Read the real chokepoint or file before giving an effort number or
picking an approach — not a vibe estimate. When grounding changes a
number, say so plainly and revise it; don't quietly keep the vaguer
figure because it was said first.

## 9. Verify external platform behavior live, don't trust training memory

Login flows, SDKs, and third-party APIs move. Check current docs before
committing real engineering time to an approach built on how something
used to work, and flag genuinely conflicting or uncertain findings
honestly — a hedge is more useful than false confidence when the source
material itself is unclear.

## 10. Update the banner when a decision is superseded

A locked-and-dated banner is cheap to add and cheap to update. When a
later decision reverses an earlier one, add a dated "Superseded" note
pointing at the new doc immediately — don't leave the old banner claiming
something is still decided. A silently-stale banner is exactly what
causes doc sprawl and contradictory plans later.

## 11. Schedule a fresh-eyes audit — don't assume docs stay in sync

Plan docs rot the same way code does. Periodically re-read every plan doc
in one pass, check ordering and staleness explicitly, and treat finding
drift as expected maintenance, not a sign something went wrong.

## 12. Delete superseded docs; only pull code with a safety net

Once a doc's content is fully absorbed elsewhere, remove it — don't leave
it next to its replacement "just in case." Verify nothing unique is lost
first. Code is different: only remove a file once there's a real
reference check (or better, test coverage) proving it's unused — a repo
with a `make check` pre-push habit already has that safety net; use it
before deleting, don't guess.

## 13. Standard shape of a plan doc

Numbered Parts, each step tagged **[CLI]**/**[OWNER]**. A "Critical
finding" callout for anything that changes the risk picture, placed where
it can't be missed (top of the doc, not buried in a part). A "what
sequences after this" pointer at the bottom so cross-doc dependencies are
explicit — a reader shouldn't have to infer sequencing from context.

## 14. Nothing ships until it looks finished and passes testing + approval

A deploy or App Store submission is never a default next step just
because the checklist's ship-blocking items are checked off. It happens
only after (1) the design/UX polish work that makes the app *look*
finished is actually done, and (2) a real testing pass and owner approval
— both, in that order. A plan doc, this file included, should never
describe shipping as imminent or assumed; state the gate explicitly
wherever shipping is mentioned, the way `CHECKLIST.md`'s own banner does.

## Explicitly not doing (yet)

- No formal project-management tool or ticket tracker across repos —
  markdown docs plus one master index is enough at this scale.
- No time-boxed sprints or deadlines — the quality bar drives sequencing,
  not a calendar. Revisit only if a real external deadline (a launch date
  someone else is depending on) shows up.
- No shared plan-doc template file/generator — the shape in §13 is
  simple enough to hold in a sentence; formalizing it into tooling would
  be solving a problem that doesn't exist yet.

## When to skip all of this

A genuinely small one-off fix or script doesn't need brainstorm → lock →
execute — that apparatus is for real scope with real decisions in it.
Read this file when a new project starts, or when an existing one's plan
docs haven't had a fresh-eyes pass in a while; don't run it for a typo
fix.

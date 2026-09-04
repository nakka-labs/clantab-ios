# ClanTab — Nav Polish + Cross-Platform Guardrails

> Scope locked 2026-09-04 after a brainstorm (see chat). Two sequenced UI
> fixes (Part 1 → Part 2), plus guardrails for Part 3 — no build now, just
> constraints to keep a future non-iOS client cheap. Not a rethink of the
> link/code-is-the-credential, minimal-chrome design center (`PLAN.md`
> Non-Goals) — the account-gated "menu + My Premium" pattern from other apps
> is explicitly **not** the target shape here, even though login itself is
> now mandatory (`MANDATORY_LOGIN_PLAN.md`).
>
> **Sequenced 2026-09-05:** do this *after* `MANDATORY_LOGIN_PLAN.md` Part 3
> (see `NEXT_STEPS.md` Phase 4) — `StartView` gets simplified once, on its
> final signed-in-only shape, not touched now and reworked again once guests
> are removed.

---

## Part 1 — Fix group switching (do first)

**[CLI] — no owner action needed, pure iOS code.**

**Problem:** `RootView.route` is a flat enum (`.start` / `.group(id)`, no
back-stack). Once inside a group, `GroupHomeView`'s toolbar only has Settings
+ filters — there is no way to reach another known group without leaving the
current one (`onLeaveGroup`) or using a deep link. `StartView`'s "Your
Groups" list is stranded on the start screen.

1. Extract `StartView.yourGroupsSection` into a standalone reusable view
   (e.g. `GroupsListView`) that takes `groups: [KnownGroup]`, `onOpenGroup`,
   `onRemoveGroup` — same shape it already has, just not private to
   `StartView`.
2. Add a "Switch Group" entry to `GroupHomeView`'s toolbar (a `Menu` item
   next to/inside the existing primaryAction group, or a second
   `ToolbarItem`) that presents `GroupsListView` in a sheet.
3. Wire selection so tapping a group in that sheet calls the same
   `enterGroup(groupId)` path `RootView` already uses — sets
   `route = .group(newId)` directly, no forced pop through `.start`.
4. No new `AppRoute` case needed — this is presentational (a sheet), not a
   new app state. No `ClanTabKit` / wire / schema changes.
5. Tests: only `App/ClanTabTests` if routing logic changes; add a UI-level
   check that switching groups updates `route` correctly if there's a
   precedent test to extend.

## Part 2 — Settings reorg (after Part 1 ships)

**[CLI] — no owner action needed, pure iOS code.**

1. Split `SettingsView`'s single "Account" `Form` section into two:
   **Account** (sign in/out, Delete Account) and **App** (version; room for
   future prefs like default currency).
2. Keep Delete Account copy/behavior unchanged (Apple Guideline 5.1.1(v)
   already handled — don't touch).
3. Stretch, not required: a dedicated groups-management screen (rename/
   reorder/remove) separate from the inline list — only if Part 1's sheet
   feels too thin once it's live.

## Part 3 — Cross-platform guardrails (no build — constraints only)

Decision from the brainstorm: no web/Android client being built now
("future-proofing," not a committed roadmap item). The backend
(`worker/`, plain REST) is already client-agnostic; the gap is the SwiftUI
shell and Swift-only `ClanTabKit`, which won't run on web/Android regardless
of how "pure" the core is (Linux CI proves testability, not portability).
Cheapest real path when/if this becomes a real ask: a thin web client hitting
the existing Worker API directly — not a Flutter/RN/KMP rewrite of the shell.

While doing Part 1/2, keep these true so that path stays cheap later:

1. Don't add Foundation/Apple-only types to `ClanTabKit`'s wire-facing
   models (`Model`/`Network`) — keep plain `Codable` structs with primitive
   fields, as today.
2. Don't grow SIWA-specific assumptions into the wire contract beyond
   `DESIGN.md` §13 — the REST API stays client-agnostic.
3. New local-storage keys (groups list, identity) should stay simple
   (string/date) — no `NSSecureCoding`-flavored tricks that don't map
   cleanly to `localStorage`/`SharedPreferences` later.
4. Don't scaffold a web or Android client speculatively — revisit only on a
   concrete reason (demo need, real non-iPhone user).

## Explicitly not doing

- No tab bar, no hamburger/account menu, no "My Premium"-style redesign —
  contradicts the no-login-required design center.
- No native Android build until there's real demand, not just optionality.

# TestFlight on-device end-to-end pass — ClanTab 1.0 (15)

**Build `1.0 (15)` is live** — archived and uploaded 2026-09-13 from the tip
of `main` at the time (through commit `f5972c4`), confirmed `processingState
VALID` via the ASC API and already assigned to the **test-team** group. It
carries everything build 14 didn't:

- **[D1, critical]** The CSV EU-locale amount-corruption fix — `12,50` now
  reads as €12.50, not a silent 100x error — plus a same-currency
  implausible-amount flag as a safety net.
- **[D9]** UPI ID no longer shown on non-INR groups.
- **[D10]** "Remind" now persists a real cooldown/timestamp across visits
  instead of resetting every time the screen closes and reopens.
- **[D11]** "Share Invite Link" now also lives in Group Settings, not just
  Group Home's overflow menu.
- **The Insights tab is gone.** Its one non-duplicate piece — personal spend
  by category — is now **My Spending**, reached from Settings.

Run everything below on a real device against **build 15 specifically** —
confirm the TestFlight app actually offers 15 as the installed/available
build before starting, since none of the checks below mean anything against
a stale 14. Nothing in Parts 1-2 changed behaviorally since the build-10
doc; Part 3 is new.

- **Distribution:** internal group **test-team** (`id0399@gmail.com`).
- **Device prerequisites:** a real iPhone (Universal Links + push don't work
  in the Simulator), signed into **iCloud**, able to do **Sign in with
  Apple**. Part 2 needs a **second identity** (second Apple/Google account,
  or a second device/tester).

## Part 1 — baseline, unchanged since build 7

| # | Check | How | Pass = |
|---|---|---|---|
| 1 | **Sign in with Apple** | Fresh install → onboarding → Sign in with Apple | Reaches the groups screen; no name/email prompt |
| 2 | **Sign in with Google** | Settings → sign out → Sign in with Google | Same |
| 3 | **Create + add expense** | Create a group, add 1–2 expenses, an equal and an exact split | Balances update, totals reconcile to the paisa |
| 4 | **Universal Link** | Group Settings → copy share link → send to yourself in Messages → tap it | Opens **ClanTab** (not Safari) to that group / the claim screen |
| 5 | **Push on receipt** | Background the app; a second member (or the CLI, below) adds an expense | Banner arrives in a few seconds; tapping it opens that group |
| 6 | **Recurring reminder** | Group Settings → Recurring Reminders → new, ~1–2 min out; background the app | Local notification fires at the scheduled time |
| 7 | **Settle up** | Settle Up → Mark as Paid on a suggested payment | Chime + success haptic; balance goes to settled |
| 8 | **Report a Problem** | A member row → Report a Problem, or Group Settings → Report a Problem | Submits; `GET /api/admin/reports` (bearer `ADMIN_TOKEN`) shows the row |
| 9 | **Delete Account** (do last, both accounts) | Settings → Delete Account → confirm, **then sign back in with the same identity** | Signing back in shows **zero groups** — not just "signed out" (round-3 fixed a real bug here: the local group cache used to survive account deletion) |
| 10 | **CloudKit backup** | After opening a claimed group, check CloudKit Dashboard → `iCloud.com.clantab.app` → **Production** → Records | A `GroupBackup` record (`recordName` `group-<id>`), `payload` asset decodes to the ledger |

## Part 2 — round-2, needs a real second identity

Sign in as yourself on your phone; sign in as a second identity on a second
device (or ask someone to install TestFlight and join). You need to share
at least one real group so each of you is a claimed member the other sees
in Friends.

| # | Check | How | Pass = |
|---|---|---|---|
| 11 | **Friends tab populates** | StartView toolbar → Friends (person icon) | Lists the second identity, with a live net balance pulled from your shared group |
| 12 | **Start a private 1:1 tab** | Friends → tap the second identity → start a tab (no shared group needed) | A new hidden group appears for both of you; doesn't show up in either "Your Groups" list |
| 13 | **Comment on an expense** | Open an expense → Comments → post one; have the other identity reply | Both comments show, oldest first, each with the right avatar |
| 14 | **Multiple payers** | Add Expense → "Add Payer" (renamed from "Split the cost between payers" in round 3) → two payers | Splits/balances credit each payer their own share, not one person the whole amount |
| 15 | **Split by shares** | Add Expense → Shares tab → uneven ratios (e.g. 2:1) | Resolves to the right proportion, not equal |
| 16 | **Itemized tax/tip** | Add Expense → Items → a couple of line items with different people → add Tax/Tip | The split favors whoever's items cost more, not an even cut |
| 17 | **My Spending (was: Insights)** | Settings → **My Spending** (moved out of the tab bar in the post-14 build — if you still see a bottom-tab Insights icon, you're on stale build 14, stop and re-check the build number) | Shows your cross-group "You spent" total + by-category pie, no group-by-group drill-in |
| 18 | **Add member inline** | Add Expense → "Add Someone" (or search a member list of 8+) | New person is added and usable in the current split without leaving the sheet |
| 19 | **Remind push** | Member profile of someone who owes you → Remind (background their app first) | Their phone gets a push naming the amount; tapping it opens the group |
| 20 | **What's New sheet** | On the *second* identity's device, if it was already signed in on an older build before updating | Sheet appears once on next launch, listing this round's items; never shows again after dismissing |
| 21 | **Coach marks + reset** | Fresh-ish account: Group Home's balance carousel, Add Expense's "Add Someone", the Friends toolbar button | A small dismissible tip appears once each, then never again — none clipped inside a List/Form row (round-3 fixed clipping on the over-time chart and "Add Someone" row specifically) — then Settings → "Show Tips Again" brings them all back |

## Part 3 — everything since build 10, never touched a real device

Two batches landed after the build-10 pass doc was written: round-3/real-device-findings (already baked into build 14) and the end-user-flow/D-ticket audit (new to build 15). Every row below is now in build 15 — the "In build?" column instead flags the handful still unconfirmed on a real device regardless of build.

| # | Check | How | Pass = | In build? |
|---|---|---|---|---|
| 22 | **CSV import, EU-locale decimal comma** | Import a CSV with an amount like `12,50` (no `.` anywhere in the file) | Reads as €12.50, not €1250 — no silent 100x error | Yes (15) |
| 23 | **CSV import, implausible-amount flag** | Import a CSV with ≥4 rows in one currency where one amount is >25x the median | Import completes but flags that row for review, doesn't silently accept it | Yes (15) |
| 24 | **UPI ID hidden on non-INR groups** | Create/open a group with currency = USD or EUR → Group Settings | No "My UPI ID" section at all; switch the group's currency to INR live and it appears without a save | Yes (15) |
| 25 | **Remind cooldown persists** | Remind someone, force-quit the app, reopen, go back to their profile | Button still reads "Reminded Xh ago" and stays disabled — does not reset just because the screen closed | Yes (15) |
| 26 | **Invite link from Group Settings** | Group Settings → join code section | A "Share Invite Link" row exists there directly, not only via Group Home's "…" → Share | Yes (15) |
| 27 | **Edit a settlement** | Group Home → tap a settlement row, or swipe → Edit | Opens a small from/to/amount form (not the Settle Up planner); saved changes reflect in balances | Yes |
| 28 | **Delete a settlement or expense** | Swipe → Delete on a settlement and on an expense | Confirmation dialog appears and stays visible (this regressed to "disappears instantly, unusable" mid-session and was reverted — confirm it's back to normal) | Yes |
| 29 | **Member profile: 1:1 history** | Open a group → tap a member → scroll down | "Together in This Group" section lists every expense/settlement involving both of you, newest first | Yes |
| 30 | **Member profile: balance breakdown** | Same screen, "Balance in this group" | Shows a line per counterparty ("Priya owes ₹500," "Ana is owed ₹200"), not just one bare net number | Yes |
| 31 | **Duplicate an expense** | Open any expense → Duplicate | Amount is pre-filled along with everything else; date resets to today | Yes |
| 32 | **Bubble-balance sizing** | Group with several small, visibly-different balances (e.g. ₹150 and ₹50) under Group Home's bubble view | The two render as different sizes, not identical dots | Yes |
| 33 | **Member avatar in My Spending** | Settings → My Spending, per-member context if shown | Shows the real profile photo, same size as elsewhere — not a blank placeholder | Yes (15) |
| 34 | **Smart category suggestion** | Add Expense → type "Uber to airport" or "Costco run" in the description, category still unset | Auto-picks Transport / Groceries; doesn't override a category you already picked yourself | Yes |
| 35 | **Cover photo + emoji during group creation** | Create a new group, get to the "created" confirmation screen | A "Make It Yours" section lets you pick an emoji and cover photo before tapping Continue | Yes |
| 36 | **Floating Add Expense button vs. undo banner** | Delete an expense (triggers the undo banner), look at the bottom-right corner | The floating "+" button is hidden while the undo banner is showing — no overlap | Yes |
| 37 | **"…" menu, bottom rows reachable** | Group Home → "…" menu → scroll to and tap **Recently Deleted** and **Recurring Reminders** specifically (not the top rows) | Both open normally with one tap — this was flagged as possibly unreachable on a real finger, simulator-only so far | Unconfirmed either way |
| 38 | **Friends empty-state copy** | A group member who hasn't signed in yet — check the Friends tab | Copy says they need to *sign in*, not just "share a group and they'll show up" | Yes |
| 39 | **Log out / re-sign-in doesn't leak groups** | Sign out (not delete) from one identity, sign back in with the same identity | Normal sign-out still shows all your groups again (this is the case that must still work — only Delete Account should wipe local cache, per check 9) | Yes |
| 40 | **Merge duplicate members** | Group Settings → a member row → swipe → Merge → pick a target → confirm | Dialog says plainly "This can't be undone," names both people; after confirming, the merged member's expenses/settlements/comments now show under the kept member, and the duplicate row is gone | Yes |
| 41 | **My Spending replaces Insights** | Signed in, on the tab bar | No Insights tab exists at all (3 tabs: Home/Friends/Settings); Settings → My Spending shows the cross-group "You spent" total + category pie, with no per-group drill-in and no duplicate of Home's own totals | Yes (15) |

## Triggering a push from the CLI (checks 5, 19)

Once signed in on-device and in a group, share its join code or
groupId+token, then a second "member" adds an expense over the API and the
worker's `notifyGroup` fires a real APNs push to your device:

```
UA='Mozilla/5.0'
curl -sS -X POST "https://clantab.nakka-labs.workers.dev/api/groups/<GID>/members?token=<TOKEN>" \
  -H 'content-type: application/json' -H "user-agent: $UA" -d '{"displayName":"Test"}'
curl -sS -X POST "https://clantab.nakka-labs.workers.dev/api/groups/<GID>/expenses?token=<TOKEN>" \
  -H 'content-type: application/json' -H "user-agent: $UA" \
  -d '{"payerId":"<OTHER_MEMBER_ID>","amountMinor":50000,"currency":"INR","description":"Coffee",
       "date":"2026-09-09T12:00:00Z","splitType":"equal","category":"food",
       "splits":[{"memberId":"<YOU>","amountMinor":25000},{"memberId":"<OTHER>","amountMinor":25000}]}'
```

(The API rejects the default `Python-urllib`/bare-curl UA at the Cloudflare
edge — send a browser-ish `User-Agent`.) Check 19 (Remind) can't be
triggered this way — it needs a real second claimed identity.

## After it passes

Tag the release against whatever build number you actually shipped and
tested (e.g. `git tag v1.0-15`, not `v1.0-10` — the old doc's tag reference
is stale along with everything else about build 10). Monetization is
decided (free, no IAP) and price is already set to Free across all
territories via the ASC API. The only thing left between here and
submission is the submit decision itself (`CHECKLIST.md` "Submit for App
Store review") — plus whatever check 37 turns up.

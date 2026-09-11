# TestFlight on-device end-to-end pass — ClanTab 1.0 (9)

The pre-submission device pass (`CHECKLIST.md` "TestFlight on-device end-to-end
pass"). Build 7 was the first to post-date **real push delivery**,
**Universal Links**, the **Production CloudKit schema**, and the **strengthened
Guideline 1.2 moderation copy**. Build 9 adds the whole "Friend playtest +
competitive gap-fill, round 2" batch on top — Friends/cross-group/1:1 tabs,
comments, multiple payers, shares split, itemized tax/tip, interactive
Insights, inline add-member, the Remind push, What's New, returning-user
summary, and coach marks. Everything in Part 1 already passed on build 7 and
just needs a quick re-check that it's still true; **Part 2 is new and hasn't
been touched on a real device or with two real accounts at all** — round-2's
Friends/cross-group work was only smoke-tested unauthenticated via curl
during CLI development (`production_priority.md`), so it's the higher-value
half of this pass.

- **Build:** `1.0 (9)`, uploaded 2026-09-11. (A stray build 8 exists in App
  Store Connect from outside this batch's history — ignore it, it predates
  round-2 and isn't assigned to the test group.)
- **Distribution:** internal group **"test-team"** (`id0399@gmail.com`).
  Install from the **TestFlight** app on the device — it should offer 9 as
  an update once Apple finishes processing.
- **Device prerequisites:** a real iPhone (Universal Links + push don't work
  in the Simulator), signed into **iCloud**, able to do **Sign in with
  Apple**. For Part 2 you need **a second identity** — a second Apple/Google
  account (or a second device/tester) to actually be a "friend": creating a
  friend relationship, a 1:1 tab, and receiving a Remind push all require
  two real, distinct signed-in people, not just two members in one group.

## Part 1 — the build-7 pass, unchanged

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
| 9 | **Delete Account** (do last, both accounts) | Settings → Delete Account → confirm | Signed out; signing back in is a fresh account, no groups |
| 10 | **CloudKit backup** | After opening a claimed group, check CloudKit Dashboard → `iCloud.com.clantab.app` → **Production** → Records | A `GroupBackup` record (`recordName` `group-<id>`), `payload` asset decodes to the ledger |

## Part 2 — round-2, needs a real second identity

Sign in as yourself on your phone; sign in as a second identity on a second
device (or ask someone to install TestFlight and join). You need to end up
sharing at least one real group so each of you is a claimed member the other
can see in Friends.

| # | Check | How | Pass = |
|---|---|---|---|
| 11 | **Friends tab populates** | StartView toolbar → Friends (person icon) | Lists the second identity, with a live net balance pulled from your shared group |
| 12 | **Start a private 1:1 tab** | Friends → tap the second identity → start a tab (no shared group needed) | A new hidden group appears for both of you; doesn't show up in either "Your Groups" list |
| 13 | **Comment on an expense** | Open an expense → Comments → post one; have the other identity reply | Both comments show, oldest first, each with the right avatar |
| 14 | **Multiple payers** | Add Expense → "Split the cost between payers" → two payers | Splits/balances credit each payer their own share, not one person the whole amount |
| 15 | **Split by shares** | Add Expense → Shares tab → uneven ratios (e.g. 2:1) | Resolves to the right proportion, not equal |
| 16 | **Itemized tax/tip** | Add Expense → Items → a couple of line items with different people → add Tax/Tip | The split favors whoever's items cost more, not an even cut |
| 17 | **Insights interactive** | Group → Spending Insights → tap a member row, then the category pie | Charts filter to that member; pie shows a scrub tooltip; "Show Everyone" clears it |
| 18 | **Add member inline** | Add Expense → "Add Someone" (or search a member list of 8+) | New person is added and usable in the current split without leaving the sheet |
| 19 | **Remind push** | Member profile of someone who owes you → Remind (background their app first) | Their phone gets a push naming the amount; tapping it opens the group |
| 20 | **What's New sheet** | On the *second* identity's device, if it was already signed in on an older build before updating to 9 | Sheet appears once on next launch, listing this round's items; never shows again after dismissing |
| 21 | **Coach marks + reset** | Fresh-ish account: Group Home's balance carousel, Add Expense's "Add Someone", the Friends toolbar button | A small dismissible tip appears once each, then never again — then Settings → "Show Tips Again" brings them all back |

## Triggering a push from the CLI (checks 5, 19)

Once you're signed in on-device and in a group, share its **join code** or
groupId+token, then a second "member" adds an expense over the API and the
worker's `notifyGroup` fires a real APNs push to your device:

```
UA='Mozilla/5.0'
# add a member to the group (if you need a distinct payer)
curl -sS -X POST "https://clantab.nakka-labs.workers.dev/api/groups/<GID>/members?token=<TOKEN>" \
  -H 'content-type: application/json' -H "user-agent: $UA" -d '{"displayName":"Test"}'
# add an expense as that member -> triggers the push to every other claimed member
curl -sS -X POST "https://clantab.nakka-labs.workers.dev/api/groups/<GID>/expenses?token=<TOKEN>" \
  -H 'content-type: application/json' -H "user-agent: $UA" \
  -d '{"payerId":"<OTHER_MEMBER_ID>","amountMinor":50000,"currency":"INR","description":"Coffee",
       "date":"2026-09-09T12:00:00Z","splitType":"equal","category":"food",
       "splits":[{"memberId":"<YOU>","amountMinor":25000},{"memberId":"<OTHER>","amountMinor":25000}]}'
```

(The API rejects the default `Python-urllib` / bare curl UA at the Cloudflare
edge — send a browser-ish `User-Agent`.) Check 19 (Remind) can't be triggered
this way — it needs a real second claimed identity, since the push targets a
specific member's linked account, not just anyone in the group.

## After it passes

Tag the release (`git tag v1.0-9`). Monetization is decided (free, no IAP —
`CHECKLIST.md` "Decide the monetization stance") and the price is already
set to Free across all territories via the ASC API (2026-09-10). The only
thing left between here and submission is the submit decision itself
(`CHECKLIST.md` "Submit for App Store review").

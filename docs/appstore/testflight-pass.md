# TestFlight on-device end-to-end pass — ClanTab 1.0 (7)

The pre-submission device pass (`CHECKLIST.md` "TestFlight on-device end-to-end
pass"). Build 7 is the first build that post-dates **real push delivery**,
**Universal Links**, the **Production CloudKit schema**, and the **strengthened
Guideline 1.2 moderation copy** — so it's the first that can exercise the whole
thing.

- **Build:** `1.0 (7)`, uploaded 2026-09-09, `processingState: VALID`,
  `usesNonExemptEncryption: false` (export compliance auto-answered).
- **Distribution:** internal group **"test-team"** (`id0399@gmail.com`), builds
  3–7 assigned. Install from the **TestFlight** app on the device.
- **Device prerequisites:** a real iPhone (Universal Links + push don't work in
  the Simulator), signed into **iCloud** (for the CloudKit backup check) and
  able to do **Sign in with Apple**. A second account (or the CLI) to trigger a
  push.

## The pass

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
| 9 | **Delete Account** (do last) | Settings → Delete Account → confirm | Signed out; signing back in is a fresh account, no groups |
| 10 | **CloudKit backup** | After opening a claimed group, check CloudKit Dashboard → `iCloud.com.clantab.app` → **Production** → Records | A `GroupBackup` record (`recordName` `group-<id>`), `payload` asset decodes to the ledger |

## Triggering the push (#5) from the CLI

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
edge — send a browser-ish `User-Agent`.)

## After it passes

Tag the release (`git tag v1.0-7` or similar). Monetization is already
decided (free, no IAP — `CHECKLIST.md` "Decide the monetization stance");
the only things between here and submission are Owner setting
Price = Free in App Store Connect's Pricing and Availability tab, then
the submit decision itself (`CHECKLIST.md` "Submit for App Store
review").

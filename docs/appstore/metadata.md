# App Store Connect — Squarely metadata (draft)

Paste these into App Store Connect. All are editable there; treat this as the
source of truth so it's version-controlled.

---

## Name
`Squarely`
_(If taken, alternatives: "Squarely: Split Expenses", "Squarely — Fair Splits".)_

## Subtitle (≤ 30 chars)
`Split expenses, no login`

## Category
Primary: **Finance**. (Secondary: Utilities.)

## Age rating
4+ — no objectionable content, no user-generated content beyond display names in
a private group.

---

## Promotional text (≤ 170 chars — editable any time without review)
`No accounts, no ads, no payment processing. Create a group, share a code, and
split trip and flatmate expenses down to the last paisa.`

## Description (≤ 4000 chars)
```
Squarely splits shared expenses for small groups — trips, flatmates, friend
circles — without the friction.

NO SIGN-UP
Create a group, pick a display name, and share a link or a 6-character code.
That's it. No email, no password, no account to manage.

SETTLE UP IN THE FEWEST PAYMENTS
Squarely collapses everyone's tangled IOUs into the minimum number of
"pay this person that much" transactions, so you settle up with one or two
transfers instead of six.

EXACT TO THE PAISA
Every amount is tracked in whole cents/paise — no floating-point rounding, no
lost or gained money across the ledger, ever.

SPLIT HOW YOU WANT
Equal splits or exact amounts per person. The remainder from an uneven split is
always assigned deterministically, so the totals match.

TRUST-BASED, NOT A PAYMENT APP
Marking a debt "paid" just records that you settled it outside the app. Squarely
never touches your money and never asks for card or bank details.

YOUR DATA, EXPORTABLE
Export any group to CSV or JSON at any time from the share menu.

NO ADS. NO TRACKING.
There are no analytics or advertising SDKs in the app.

Anyone with a group's link or code can see and edit that group — the same model
as a shared document link. Keep the link private to the people in your group.
```

## Keywords (≤ 100 chars, comma-separated, no spaces)
`split,expenses,bills,trip,roommate,flatmate,shared,settle up,ious,group,tab,splitwise`

## Support URL
`https://github.com/nakka-labs/squarely-ios` _(until there's a real support page)_

## Marketing URL (optional)
_leave blank for now_

## Privacy Policy URL (required)
Host `docs/privacy-policy.md` somewhere public and put the URL here. Quickest:
GitHub Pages for this repo → `https://nakka-labs.github.io/squarely-ios/privacy-policy`
(enable Pages: repo Settings → Pages → deploy from `main` `/docs`).

---

## App Privacy (the questionnaire in App Store Connect)

Answer to match `App/Squarely/PrivacyInfo.xcprivacy`:

| Question | Answer |
|---|---|
| Do you collect data? | **Yes** |
| — Contact Info → Name | Yes · linked to user · not for tracking · App Functionality |
| — User Content → Other | Yes (expense records) · linked to user · not for tracking · App Functionality |
| Everything else (email, phone, payment, location, contacts, identifiers, usage, diagnostics) | **No** |
| Tracking (ATT) | **No** |

---

## Review notes (App Review — this app is unusual; pre-empt the questions)
```
Squarely has NO login or account system by design. Access to a group is by
capability link / 6-character join code (the same trust model as a shared
document link) — this is intentional, not a missing feature.

TO TEST:
1. Tap "Create a Group", enter any name and display name, tap "Create Group".
2. The next screen shows a 6-character join code (e.g. ABC234).
3. On a second device/simulator: "Join with a Code", enter that code, pick a
   name, "Join Group".
4. Either device: "Add Expense" — enter an amount, description, choose equal or
   exact split, "Add Expense". Balances update for everyone.
5. "Settle Up" shows the minimal set of payments. "Mark as Paid" records that a
   payment happened OUTSIDE the app — Squarely never processes money and never
   collects payment credentials.

BACKEND: a Cloudflare Worker at https://squarely.nakka-labs.workers.dev
(no auth; capability-URL access as described).

No third-party analytics or advertising SDKs. No in-app purchases.
```

## Screenshots
Required: 6.9" (iPhone 16 Pro Max) and 6.5"/6.1". Capture on the Simulator with a
seeded group (create → add 2 members via a second run or the join flow → one
expense). Good set: Start, Group Home (with a balance + activity), Add Expense,
Settle Up. The verification runs in this session produced usable frames under
the session scratchpad — reshoot cleanly for the store.

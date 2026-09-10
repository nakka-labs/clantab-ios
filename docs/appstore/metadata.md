# App Store Connect — ClanTab metadata (draft)

Source of truth, version-controlled. Pushed to App Store Connect (app
`6807057518`, version 1.0) via the ASC API on 2026-09-09: **name, subtitle,
description, keywords, promotional text, support URL, privacy policy URL,
primary/secondary category (Finance / Utilities), content-rights declaration
(no third-party content), build 7 attached, all 4 screenshots
(`APP_IPHONE_67` set, 1320×2868, order 1–4), and the App Review detail**
(contact Indra Nakka / `indra@nakka.dev` / `+91 77993 39777`, no demo
account, the review notes below). The 4+ age-rating questionnaire and the
App Privacy data-collection labels were filled in the UI (age rating
verified via API; the App Privacy API surface is non-functional so trust
the owner's UI entry against the table below).

Everything for a version 1.0 submission is in place. Monetization
stance decided 2026-09-10: **free, no in-app purchases** (see
`CHECKLIST.md` "Decide the monetization stance" and the repo's
`production_priority.md` project memory for the reasoning — a
network-effect group app can't carry a paywall without killing its own
adoption, and realistic revenue at this app's scale doesn't offset that
cost). **Price set to Free** via the ASC API on 2026-09-10:
`POST /v1/appPriceSchedules` with `baseTerritory = USA` at the free
price point — USA base + all 174 automatic territories now `0.0`,
effective immediately. Verified 0 IAP products and 0 subscription
groups exist. Remaining is just the `Owner` decision to submit
(`CHECKLIST.md` "Submit for App Store review"), gated on the TestFlight
pass.

**ASC API access** (for a future session): key `58887ALLXT` (Team key
"clantab-upload", App Manager) at `~/.appstoreconnect/private_keys/`;
issuer ID `6efff402-9490-4d58-ae2a-dcaba05b65e7`; app id `6807057518`.
Neither is a secret (the `.p8` is); the App Privacy API surface stays
non-functional so those labels are UI-only.

---

## Name
`ClanTab`

## Subtitle (≤ 30 chars)
`Split expenses, settle up fast` (30 chars)

## Category
Primary: **Finance**. (Secondary: Utilities.)

## Age rating
**4+.** The app does carry user-generated content now — group names, member
display names, and expense descriptions, plus the Guideline 1.2 moderation
system (in-app "Report a Problem", member removal/block from Group Settings,
published contact in the privacy policy). 4+ still holds because that content is
confined to private, invite-only groups: there is no public feed, no discovery,
no messaging between strangers, and nothing a user sees that wasn't written by
someone they invited or were invited by. Every objectionable-content category in
the questionnaire (violence, sexual content, profanity/crude humor, horror,
gambling, contests, drugs/alcohol) is "None", and there is no unrestricted web
access. Re-confirm the questionnaire maps to 4+ at submission; if App Review
argues the UGC warrants 17+, that is the fallback — the moderation obligations
under 1.2 are already met either way.

---

## Promotional text (≤ 170 chars — editable any time without review)
`No ads, no tracking, no payment processing. Sign in, start a group, share a
code, and split trip and flatmate expenses down to the last paisa.`

## Description (≤ 4000 chars)
```
ClanTab splits shared expenses for small groups — trips, flatmates, friend
circles — without the friction.

QUICK SIGN-IN
Sign in with Apple or Google — no email or password to create, no phone number,
nothing to verify. Then start a group, pick a display name, and share a link or
a 6-character code.

SETTLE UP IN THE FEWEST PAYMENTS
ClanTab collapses everyone's tangled IOUs into the minimum number of
"pay this person that much" transactions, so you settle up with one or two
transfers instead of six.

EXACT TO THE PAISA
Every amount is tracked in whole cents/paise — no floating-point rounding, no
lost or gained money across the ledger, ever.

SPLIT HOW YOU WANT
Equal splits or exact amounts per person. The remainder from an uneven split is
always assigned deterministically, so the totals match.

TRUST-BASED, NOT A PAYMENT APP
Marking a debt "paid" just records that you settled it outside the app. ClanTab
never touches your money and never asks for card or bank details.

YOUR DATA, EXPORTABLE
Export any group to CSV or JSON at any time from the share menu.

NO ADS. NO TRACKING.
There are no analytics or advertising SDKs in the app.

Anyone with a group's link or code can see and edit that group — the same model
as a shared document link. Keep the link private to the people in your group.
```

## Keywords (≤ 100 chars, comma-separated, no spaces)
`split,expenses,bills,trip,roommate,flatmate,shared,settle up,ious,group,tab,expense tracker`

(Dropped `splitwise` 2026-09-09 — a competitor trademark in keywords is a
common metadata-rejection trigger, Guideline 2.3.7 — and used the freed
space for `expense tracker`.)

## Support URL
`https://clantab.nakka.dev/support`

Live. Standalone page (what ClanTab is, a contact address, an FAQ, links to
the privacy policy and repo), served from the `nakka-labs/clantab-website`
repo via Cloudflare Pages. The page there is a hand-port of this repo's
`docs/support.html` — that file stays the upstream source (`WEBSITE_PLAN.md`
in the website repo). Use the extension-less path; `/support.html` 301s to it.

## Marketing URL (optional)
_leave blank for now — or reuse the support URL_

## Privacy Policy URL (required)
`https://clantab.nakka.dev/privacy`

Live. Served from the `nakka-labs/clantab-website` repo via Cloudflare Pages —
a hand-port of this repo's `docs/privacy-policy.md`, which stays the upstream
source. Use the extension-less path; `/privacy.html` 301s to it.

---

## App Privacy (the questionnaire in App Store Connect)

Keep this and `App/ClanTab/PrivacyInfo.xcprivacy` in sync. The manifest was
updated to match this table on 2026-09-08 (added Identifiers → User ID and
Identifiers → Device ID).

| Question | Answer |
|---|---|
| Do you collect data? | **Yes** |
| — Contact Info → Name | Yes · linked to user · not for tracking · App Functionality — the display name a user types for each group |
| — Identifiers → User ID | Yes · linked to user · not for tracking · App Functionality — the opaque Apple/Google account identifier ("subject" id) used to recognise a returning user, plus per-group member ids |
| — Identifiers → Device ID | Yes · linked to user · not for tracking · App Functionality — the Apple Push Notification token, only if the user enables notifications; used solely to notify them about their own groups |
| — User Content → Other | Yes · linked to user · not for tracking · App Functionality — shared expense/settlement records, and the free-text details of a content report |
| — Contact Info → Email Address | **No** — see note. Sign in with Apple requests no email. Sign in with Google returns a token containing the user's email, but it is transmitted only to verify the sign-in and is never read, stored, or logged (the backend extracts only the anonymous `sub`). Treated as "not collected" under Apple's not-retained-beyond-servicing carve-out. Revisit if App Review disagrees — the fallback answer is Yes · linked · not for tracking · App Functionality. |
| Everything else (phone, payment info, location, contacts, health, browsing/search history, usage data, diagnostics, other financial info) | **No** |
| Tracking (ATT) | **No** |

Notes for the questionnaire:

- **User Content → Other** rather than **Financial Info → Other**: the ledger
  records a group's shared spending, not a user's personal financial standing
  (salary/assets/debts). Judgement call, revisit if App Review pushes back.
- Nothing is used for tracking or third-party advertising; there are no
  analytics or ad SDKs in the app.
- Account identity is stored server-side (Cloudflare) for cross-device sync;
  "Delete Account" in the app removes it (Guideline 5.1.1(v)).

---

## Review notes (App Review — this app is unusual; pre-empt the questions)
```
SIGN-IN
ClanTab requires Sign in with Apple or Sign in with Google before any group can
be created, joined, or viewed. No demo account is needed — Sign in with Apple
works with your own reviewer Apple ID, and a brand-new account can reach 100% of
the app immediately (there is no approval step, no waitlist, no paid tier).
ClanTab requests NO name and NO email from Apple; it stores only the anonymous
account identifier.

GROUP ACCESS MODEL (unchanged, and intentional)
Once signed in, access to a specific group is by capability link / 6-character
join code plus a rotatable access token — the same trust model as a shared
document link. Anyone a member shares the current link/code with can view and
edit that group. This is by design, layered on top of mandatory sign-in.

TO TEST:
1. Launch the app, complete Sign in with Apple (or Google) at the prompt.
2. Tap "Create a Group", enter any name and display name, tap "Create Group".
3. Open Group Settings (top-right) — the join code and share link are there.
   "Add Someone" also lets you add a member by name with no account of their own.
4. On a second device/simulator: sign in with a different account, tap
   "Join with a Code", enter that code, pick which member you are (or add
   yourself), "Join".
5. Either device: "Add Expense" — amount, description, choose equal or exact
   split, "Add Expense". Balances update for everyone.
6. "Settle Up" shows the minimal set of payments. "Mark as Paid" records that a
   payment happened OUTSIDE the app — ClanTab never processes money and never
   collects payment credentials.

USER-GENERATED CONTENT (Guideline 1.2)
Group names, member names, and expense descriptions are shared between members.
"Report a Problem" is available from any member row and from Group Settings;
"Remove" (Group Settings) blocks a member from the group. Reports go to the
operator and are reviewed within 24 hours; abusive content and users are
removed. The EULA (https://clantab.nakka.dev/terms) states a zero-tolerance
policy for objectionable content and abusive users. Published support contact:
indra@nakka.dev.

ACCOUNT DELETION (Guideline 5.1.1(v))
Settings (gear icon on the start screen or Group Home) → "Delete Account".

BACKEND: a Cloudflare Worker at https://clantab.nakka-labs.workers.dev.
Group-data routes use capability-link/token possession as described; auth routes
verify an Apple or Google identity token and mint a session token.

Notifications are optional (prompted once, just after sign-in). No third-party
analytics or advertising SDKs. No in-app purchases.
```

## Screenshots
✅ Uploaded to App Store Connect 2026-09-09 (`APP_IPHONE_67` set, order 1–4,
all `COMPLETE`, no warnings). Source: `docs/appstore/screenshots/`
(2026-09-02). Four 1320 × 2868 frames
(iPhone 6.9" — the one required iPhone size), PNG without alpha, status bar at
9:41: Group Home, Insights, Add Expense, Settle Up. Captured on an iPhone 17 Pro
Max Simulator with a "Lisbon Trip" demo group. Upload as-is to the iPhone
screenshot slot in App Store Connect; App Store Connect scales for other iPhone
sizes.

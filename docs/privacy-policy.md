# ClanTab — Privacy Policy

_Last updated: 2026-09-09_

ClanTab is an expense-splitting app for small groups — trips, flatmates, friend
circles. Using it **requires signing in with Apple or Google**. This policy
explains what the app collects, why, and your choices.

## Signing in

To create, join, or view a group you must sign in with **Sign in with Apple** or
**Sign in with Google**. There is no email/password account and no phone
verification.

- **Sign in with Apple** — ClanTab requests *no* name and *no* email from Apple.
  It receives only Apple's stable, app-specific account identifier for you.
- **Sign in with Google** — Google's sign-in returns a token that includes your
  email address and basic profile (name, profile-photo URL). ClanTab uses only
  the anonymous account identifier in that token to recognise you on your next
  sign-in. **It does not store, log, or display your Google email address or
  name.**

Apple and Google act as the identity provider for the sign-in itself; their own
privacy policies cover what they collect when you authenticate:

- Apple: https://www.apple.com/legal/privacy/
- Google: https://policies.google.com/privacy

## What ClanTab collects

**Account data** (stored on ClanTab's backend, linked to you):

- **An opaque account identifier** — the "subject" identifier from Apple or
  Google described above. It is not your name, email, or phone number.
- **The date you first signed in.**
- **An index of your groups** — which groups you belong to, and your member id
  and chosen display name within each. Not the groups' contents.
- **For Sign in with Apple only**: if Apple provides a refresh token during
  sign-in, ClanTab stores it for one purpose — to tell Apple to revoke your
  sign-in when you delete your ClanTab account.
- **A device notification token**, if you allow notifications — your device's
  Apple Push Notification Service token, used only to send you notifications
  about activity in your groups. Removed when you sign out on that device.

**Group data** (stored on the backend, shared with everyone in the group):

- **The display name you type** for each group (e.g. "Ana"). You choose it.
- **The group's shared records** — expense amounts, descriptions, dates, who
  paid, how each expense is split, and settlement ("I paid you back") entries.

**Content reports:** if you report a group or a member (see "User-generated
content" below), ClanTab stores the report — the reason you pick, any details
you type, which group and member it concerns, and your account identifier if you
are signed in — so it can be reviewed.

## What ClanTab does **not** collect

- Email addresses, phone numbers, or real names — beyond a display name you type
  yourself
- Passwords or payment credentials — ClanTab never processes money
- Location, contacts, photos, or advertising identifiers
- Any analytics, advertising, or tracking data. There are no third-party
  analytics or advertising SDKs in the app, and ClanTab does not track you
  across other apps or websites.

## User-generated content

Group names, member display names, expense descriptions, and report details are
written by users and shared with the other members of a group. ClanTab has a
zero-tolerance approach to abusive or objectionable content:

- **Report** — from a member's row or from Group Settings, you can report a
  member or a group's content for review.
- **Remove** — from Group Settings, a member can remove another member from the
  group.
- Reports are reviewed within 24 hours, and content or members found to be
  abusive are removed.

## How groups are identified

Each group has a long, unguessable link and a short join code, backed by an
access token that a member can rotate ("Regenerate Link") to invalidate every
previously shared link and code. **Anyone who currently holds a valid link or
code can view and edit that group's records** — that, plus your sign-in, is the
access model, by design (similar to a shareable document link). Don't post a
group's link or code publicly.

## Where data is stored

- **On your device**: your session token and Apple account identifier (in the
  iOS Keychain), your chosen display name, the last group you opened, your
  notification token, and local app settings. Removing the app deletes this.
- **On the backend**: account and group records are stored in Cloudflare
  Durable Objects and Workers KV (Cloudflare, Inc. is ClanTab's infrastructure
  provider). All data is transmitted over HTTPS to
  `clantab.nakka-labs.workers.dev`.

## Data retention and deletion

- **Delete your account** — in the app, open **Settings → Delete Account**. This
  revokes your Sign in with Apple token (for Apple accounts), removes your
  account identifier, your groups index, and your notification tokens, and
  releases your group memberships. Your past expenses and settlements, and the
  member entry itself, **remain in each group** (the member becomes an
  unclaimed placeholder) so the other members keep an accurate ledger.
- **Delete a group's data** — because a group is shared, contact us (below) with
  the group's join code and we will remove that group's records.

## Children

ClanTab is not directed at children under 13 and does not knowingly collect data
from them.

## Third parties

- **Cloudflare** — hosts the backend (a subprocessor):
  https://www.cloudflare.com/privacypolicy/
- **Apple** and **Google** — identity providers for sign-in only (see "Signing
  in").
- **Apple Push Notification service** — delivers notifications if you enable
  them.
- ClanTab does not sell or share your data with anyone else.

## Changes

If this policy changes materially, the "Last updated" date above will change
and, where practical, a note will appear in the app.

## Contact

Questions or deletion requests: **indra@nakka.dev**

// SQLite DDL for the Durable Objects (`DESIGN.md` §3). All money columns are
// INTEGER minor units — never REAL. Foreign-key REFERENCES from `DESIGN.md` are
// omitted (the DO validates every referenced id in code, per §6) but the column
// meaning is unchanged.

export const GROUP_SCHEMA = `
CREATE TABLE IF NOT EXISTS group_meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS members (
  id           TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  created_at   INTEGER NOT NULL,
  identity_sub TEXT,
  upi_vpa      TEXT
);

CREATE TABLE IF NOT EXISTS expenses (
  id            TEXT PRIMARY KEY,
  payer_id      TEXT NOT NULL,
  amount_minor  INTEGER NOT NULL,
  description   TEXT NOT NULL,
  expense_date  TEXT NOT NULL,
  split_type    TEXT NOT NULL CHECK (split_type IN ('equal','exact','percentage')),
  created_at    INTEGER NOT NULL,
  category      TEXT,
  category_icon TEXT,
  currency      TEXT,
  deleted_at    INTEGER,
  deleted_by    TEXT
);

CREATE TABLE IF NOT EXISTS expense_splits (
  expense_id   TEXT NOT NULL,
  member_id    TEXT NOT NULL,
  amount_minor INTEGER NOT NULL,
  PRIMARY KEY (expense_id, member_id)
);

CREATE TABLE IF NOT EXISTS settlements (
  id           TEXT PRIMARY KEY,
  from_id      TEXT NOT NULL,
  to_id        TEXT NOT NULL,
  amount_minor INTEGER NOT NULL,
  settled_at   INTEGER NOT NULL,
  currency     TEXT,
  deleted_at   INTEGER,
  deleted_by   TEXT
);
`;

/**
 * `UserDO` — one per signed-in identity, addressed by
 * `idFromName("<provider>:<sub>")` (`apple:…` or `google:…`,
 * `MANDATORY_LOGIN_PLAN.md` Part 2). A thin per-identity index of "which
 * groups, as which member" (`ACCOUNTS_DESIGN.md` §1). At most one membership
 * per group per identity (PK on `group_id`).
 */
export const USER_SCHEMA = `
CREATE TABLE IF NOT EXISTS user_meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS memberships (
  group_id     TEXT PRIMARY KEY,
  member_id    TEXT NOT NULL,
  display_name TEXT NOT NULL,
  added_at     INTEGER NOT NULL
);

-- Registered APNs device tokens, for push notifications
-- (FEATURE_BACKLOG.md "Push notifications"). One identity can hold several
-- (phone + iPad, or a reinstall that got a new token before the old one
-- expired) -- all get notified. Re-registering the same token is a no-op
-- (PK on token); added_at isn't touched on re-registration, nothing to
-- gain from it.
CREATE TABLE IF NOT EXISTS devices (
  token    TEXT PRIMARY KEY,
  platform TEXT NOT NULL,
  added_at INTEGER NOT NULL
);
`;

export const USER_META_KEYS = {
  /** The composite `"<provider>:<sub>"` identity string this DO was created
   * for — the same value `idFromName` addressed it by. */
  identity: "identity",
  createdAt: "created_at",
  schemaVersion: "schema_version",
  /** Apple refresh token, from the sign-in `authorizationCode` exchange — used
   * to revoke on account deletion (Apple Guideline 5.1.1(v)). Only present when
   * the identity is Apple's and the `SIWA_*` config is configured — Google's
   * flow requests no offline access, so this stays unset for Google identities. */
  appleRefreshToken: "apple_refresh_token",
} as const;

export const USER_SCHEMA_VERSION = "1";

/**
 * `ReportsDO` — one global singleton (`idFromName("global")`), the content-
 * report log required by Apple Guideline 1.2 for any app with shared
 * user-generated content (`SHIP_PLAN.md` Track 3 §7): group names, member
 * names, and expense descriptions are all user-typed and shared between
 * whoever holds a group's link. Deliberately a singleton — unlike the
 * retired `RegistryDO` (a chokepoint on every group creation/join-code
 * lookup, real request volume), reports are rare by design, and the owner
 * needs one place to see all of them rather than polling every group's own
 * unguessable `groupId`.
 */
export const REPORTS_SCHEMA = `
CREATE TABLE IF NOT EXISTS reports (
  id           TEXT PRIMARY KEY,
  group_id     TEXT NOT NULL,
  target_type  TEXT NOT NULL CHECK (target_type IN ('group','member')),
  target_id    TEXT,
  reason       TEXT NOT NULL,
  details      TEXT,
  reported_by  TEXT,
  created_at   INTEGER NOT NULL
);
`;

/** `group_meta` keys written at creation (`DESIGN.md` §3 + §10). */
export const META_KEYS = {
  name: "name",
  currency: "currency",
  joinCode: "join_code",
  createdAt: "created_at",
  schemaVersion: "schema_version",
  /** The rotatable capability-link credential (`ACCESS_TOKEN_PLAN.md`) —
   * separate from `groupId`, which permanently identifies the DO. Written at
   * creation for every group from here on; absent on a group created before
   * this feature shipped (`requireGroup` treats "no row" as open access,
   * unchanged from before — a deliberate backward-compat choice, not a bug). */
  accessToken: "access_token",
} as const;

/**
 * Bump when a `GroupDO` needs an in-place migration (`DESIGN.md` §10). History:
 *  - `1` → initial v1 shape.
 *  - `2` → `expenses.split_type` CHECK widened to allow `'percentage'`. SQLite
 *          can't alter a CHECK in place, so `GroupDO.migrate` rebuilds the table.
 *  - `3` → `expenses.category` + `expenses.category_icon` added (nullable).
 *          Plain `ALTER TABLE ... ADD COLUMN` — no rebuild.
 *  - `4` → `expenses.currency` + `settlements.currency` added (nullable), then
 *          backfilled from the group's currency. Multi-currency ledgers.
 *  - `5` → `members.identity_sub` added (nullable). Every existing member is a
 *          placeholder (NULL); claiming links a member to an Apple identity.
 *          Plain `ALTER TABLE ... ADD COLUMN` — no rebuild. See `ACCOUNTS_DESIGN.md`.
 *  - `6` → `expenses.deleted_at` / `.deleted_by` and `settlements.deleted_at` /
 *          `.deleted_by` added (nullable). Delete becomes soft — a row with
 *          `deleted_at` set is excluded from balances/getState but stays in
 *          storage for "Recently Deleted" + Restore (`FEATURE_BACKLOG.md`).
 *          Plain `ALTER TABLE ... ADD COLUMN` — no rebuild.
 *  - `7` → `members.upi_vpa` added (nullable). User-supplied, never verified —
 *          `FEATURE_BACKLOG.md` "UPI deep link on Settle Up". Plain
 *          `ALTER TABLE ... ADD COLUMN` — no rebuild.
 */
export const SCHEMA_VERSION = "7";

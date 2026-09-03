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
  identity_sub TEXT
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
  currency      TEXT
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
  currency     TEXT
);
`;

export const REGISTRY_SCHEMA = `
CREATE TABLE IF NOT EXISTS join_codes (
  code       TEXT PRIMARY KEY,
  group_id   TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
`;

/**
 * `UserDO` — one per Apple identity (`idFromName(appleSub)`). A thin per-identity
 * index of "which groups, as which member" (`ACCOUNTS_DESIGN.md` §1). At most one
 * membership per group per identity (PK on `group_id`).
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
`;

export const USER_META_KEYS = {
  appleSub: "apple_sub",
  createdAt: "created_at",
  schemaVersion: "schema_version",
} as const;

export const USER_SCHEMA_VERSION = "1";

/** `group_meta` keys written at creation (`DESIGN.md` §3 + §10). */
export const META_KEYS = {
  name: "name",
  currency: "currency",
  joinCode: "join_code",
  createdAt: "created_at",
  schemaVersion: "schema_version",
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
 */
export const SCHEMA_VERSION = "5";

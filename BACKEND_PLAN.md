# Squarely Backend — Build Plan

The iOS-app track (`PLAN.md` Phases 0-7) is done and tagged `v0.1.0`. Nothing
works end-to-end yet because **the backend doesn't exist** — `AppConfig.apiBaseURL`
is a placeholder and everything has only run against a local mock.

This plan builds the Cloudflare Worker + Durable Objects backend that
`DESIGN.md` specifies. `DESIGN.md` is the contract (API §2, storage §3,
concurrency §4, flows §5, validation §6, security §8, non-functional §9,
schema evolution §10, testing §11, deferred §12) — this plan is the
*sequence* for implementing it, plus the decisions to lock first.

---

## Progress

- **§0 decisions** — locked. Monorepo `worker/`; Workers + DO SQLite; zero
  runtime deps; `number` money with integer guards. **§0.3: yes — `joinCode`
  is now returned from `GET /api/groups/:groupId`** (`DESIGN.md` §2/§12
  updated; iOS `GroupSummary` carries it; Group Home's Share menu re-shares it).
- **§1 scaffold** — ✅ done. `worker/` with `wrangler.jsonc` (DO bindings +
  `v1` sqlite migration), `tsconfig`, three vitest configs, `Makefile`
  `worker-*` targets, `.github/workflows/worker.yml`, `AGENTS.md` Backend
  section.
- **§2 pure logic + parity** — ✅ done. 7 shared vectors run by both
  `worker/test/logic.test.ts` and `SquareKitTests/GoldenParityTests.swift`.
- **§3 RegistryDO** — ✅ done. `reserve` (collision-retry) + `resolve`
  (case-insensitive, per-IP 20/min fixed-window limiter). `test/registry.test.ts`.
- **§4 GroupDO** — ✅ done. Schema from §3 + `schema_version`; `initGroup` /
  `addMember` / `getState` (server-computed balances + `simplify`) / `addExpense`
  / `addSettlement` / `exists`. Idempotent writes; validation in the DO;
  `INTEGER` money; `ORDER BY created_at, rowid` (a real bug: `Date.now()` ties
  within a DO). DO methods return `Result`/discriminated unions rather than
  throwing — a thrown error loses its prototype across the RPC boundary.
  `test/group.test.ts`.
- **§5 router** — ✅ done. `src/index.ts`: all six §2 routes (URLPattern),
  `{error:{code,message}}` envelopes, bare 404 for unknown resolve,
  `GROUP_NOT_FOUND` for group routes, `X-Robots-Tag: noindex` on `/api/*`,
  strict body parsing (rejects unknown fields, §6), 404/405. `test/routes.test.ts`
  (20 tests). Smoke-tested end-to-end against `wrangler dev` on `:8787`.
- **Tests**: `npm --prefix worker test` → 52 (logic 10 + validation 13 +
  registry 4 + group 6 + routes 20 via `@cloudflare/vitest-pool-workers`).
  `swift test` → 47.
- **§6 `/g/:groupId` page** — minimal stub shipped: a noindex HTML page with an
  "Open in Squarely" deep link (`src/index.ts` `handleCapabilityPage`). A real
  landing page + `apple-app-site-association` / Universal Links still need a
  production domain.
- **§7 re-verify the iOS app against the real backend** — ✅ done (2026-08-28).
  Ran the full app flow (temp `AppConfig.apiBaseURL` → `http://localhost:8787/`)
  against `wrangler dev` end-to-end: create group → join code shown → (test
  adds 2 members via its own HTTP calls) → app picks them up on refresh → add
  a ₹3000 equal-split expense → **server-computed** "You are owed ₹2000" and
  member balances → Settle Up shows the server's simplified plan → Mark as
  Paid → recompute → Group Home's Share menu offers "Share Join Code (VYC5AU)".
  All temp changes reverted. Screenshots in the session scratchpad.
- **§8 deploy** — ✅ done (2026-08-28). Live at
  **`https://squarely.nakka-labs.workers.dev`** (`wrangler deploy`; `v1`
  migration created `RegistryDO` + `GroupDO`). `AppConfig.apiBaseURL` points at
  it. Production smoke test green (create → members → server-computed balances →
  simplified plan → resolve → bare-404). iOS re-verification against production:
  pending.
  - *Note:* the zone's default Cloudflare browser-integrity check returns
    `error code: 1010` to bare non-browser user agents (curl/urllib without a
    UA). Native `URLSession` sends a real UA and is unaffected; a future web
    client would need this revisited.

---

## 0. Decisions to lock before starting

### 0.1 Monorepo — add `worker/` to this repo (recommended)

The repo was scaffolded for it: `.gitignore` already ignores `.wrangler/`,
`node_modules/`, `dist/`; `DESIGN.md` names `src/worker/index.ts` and
`worker/lib/balances.ts`. Keeping it here means one `DESIGN.md` contract, one
place to keep the balance/simplify logic honest against `SquareKit`, and one
PR touches both sides when the wire contract changes. A separate repo only
makes sense if the backend gets its own release cadence or team — not the
case now.

**→ `worker/` directory in this repo.**

### 0.2 Stack

- **Cloudflare Workers + Durable Objects**, TypeScript, `wrangler`.
- **DO storage: the SQLite storage API** (`DurableObjectState.storage.sql`),
  matching `DESIGN.md` §3's schema. Requires `new_sqlite_classes` in the
  migration and a recent `compatibility_date`.
- **Zero runtime dependencies** (same ethos as the iOS side's no-3rd-party
  rule). A hand-rolled router is ~30 lines; `nanoid` is replaceable with ~15
  lines over `crypto.getRandomValues`. Re-evaluate only if it actually hurts.
- **Tests: Vitest** + `@cloudflare/vitest-pool-workers` for the ones that need
  a real local DO (`DESIGN.md` §11). Dev-only deps are fine.
- **`tsc --noEmit`** in CI for type-checking.

### 0.3 Return `joinCode` from `GET /api/groups/:groupId`? — recommended: yes

`DESIGN.md` §12 flags this. Today the join code is shown exactly once
(right after creation) and can never be recovered — see `App/README.md`
"Known gaps". The code is already low-entropy and Registry-resolvable, so
returning it from the group-state endpoint adds no real exposure and removes
a real UX wart. Doing it means: one extra field in the §2 `group` object,
one `group_meta` read, and a small iOS change (surface it on Group Home).

**→ Add `joinCode` to the `group` object in the GET response.** Update
`DESIGN.md` §2 + §12 and `SquarelyWireTypes.GroupSummary` when it lands.

### 0.4 Error shapes the iOS client already expects

`SquarelyClient` decodes a `{ error: { code, message } }` envelope into
`.server(code:message:)`, and a **bare** 404 (no body) into `.notFound`.
`GroupViewModel` now treats either a bare 404 or a `GROUP_NOT_FOUND` envelope
as "group is gone". So:

- `GET /api/groups/resolve/:joinCode` unknown → **bare 404**.
- Group routes with an unknown `groupId` → `404 { error: { code:
  "GROUP_NOT_FOUND", ... } }` (envelope, per §2).
- All other failures → envelope with the §2/§6 codes
  (`SPLIT_MISMATCH`, `UNKNOWN_MEMBER`, `INVALID_AMOUNT`).

### 0.5 Integer money in TypeScript

Amounts are minor units (paise/cents) as `INTEGER` in SQLite. In TS use
`number` with explicit guards (`Number.isInteger(x) && x > 0`); the values
(even a large group's running totals) sit far below `Number.MAX_SAFE_INTEGER`
(~9e15). Document the ceiling in `validation.ts`. No `bigint` — JSON has none
anyway.

---

## 1. Scaffold `worker/` + CI

```
worker/
├── package.json            # scripts: dev, test, typecheck, deploy
├── tsconfig.json
├── wrangler.jsonc          # DO bindings GROUP_DO / REGISTRY_DO, sqlite migration
├── src/
│   ├── index.ts            # Worker entry + router (/api/*, /g/:groupId)
│   ├── group-do.ts         # GroupDO
│   ├── registry-do.ts      # RegistryDO
│   ├── types.ts            # wire types, mirror of DESIGN.md §2 / SquarelyWireTypes
│   └── lib/
│       ├── balances.ts     # port of SquareKit Balances.compute
│       ├── simplify.ts     # port of SquareKit Simplify.simplify
│       ├── validation.ts   # port of SquareKit Validation.*
│       ├── ids.ts          # groupId (nanoid, 16) + joinCode (6, 32-char alphabet)
│       └── schema.ts       # CREATE TABLE strings from DESIGN.md §3
└── test/
    ├── fixtures/           # shared golden vectors (see §2)
    ├── logic.test.ts
    ├── registry.test.ts
    ├── group.test.ts
    └── routes.test.ts
```

- `wrangler.jsonc`: `GROUP_DO` → `GroupDO`, `REGISTRY_DO` → `RegistryDO`;
  migration `{ tag: "v1", new_sqlite_classes: ["GroupDO", "RegistryDO"] }`;
  `compatibility_date` current.
- Root `Makefile`: add `worker-dev`, `worker-test`, `worker-typecheck`,
  `worker-deploy` (delegating to `npm --prefix worker run …`).
- New `.github/workflows/worker.yml` (ubuntu, Node 20): `npm ci`,
  `npm run typecheck`, `npm run test`. Path-filter on `worker/**`.
- `AGENTS.md`: add a "Backend" section — the zero-dep rule, "logic mirrors
  `SquareKit`, kept honest by shared fixtures", `wrangler dev` on `:8787`.

## 2. Pure logic + golden parity tests — **start here**

No Cloudflare involved; highest value; this is `DESIGN.md` §11's "the tests
that matter most".

1. **Port the three pure modules** 1:1 from `SquareKit/Sources/SquareKit/Logic/`:
   - `Balances.compute(members, expenses, settlements) → Balance[]` — payer
     credited full amount, each split member debited their share; settlement
     credits `fromId`, debits `toId`; one result per member, sums to zero.
   - `Simplify.simplify(balances) → SimplifiedSettlement[]` — greedy
     largest-creditor/largest-debtor, **ties broken by `memberId` ascending**,
     re-sort after each match. Must be byte-identical to the Swift output.
   - `Validation` — `validateSplitsSum` (exact, no tolerance),
     `validateMembersExist`, `validatePositiveAmount`. (`equalSplit` is **not**
     needed server-side — the client sends splits already resolved, §6.)
2. **Shared golden fixtures** — `worker/test/fixtures/*.json`, each:
   `{ members, expenses, settlements, expectedBalances, expectedSimplified }`.
   Cover `PLAN.md` §2's essential cases: triangle collapse, single-payer →
   N-1, ₹100 split 3 ways remainder, already-settled → 0 transactions,
   idempotency (run twice, identical), and a seeded fuzz vector
   (Σ payments == Σ positive balances).
3. **Make `SquareKitTests` consume the same fixtures** — add a Swift test that
   decodes each JSON and asserts `Balances`/`Simplify` match `expected*`.
   Now both CIs fail if the two implementations drift. This is the
   enforcement mechanism for `DESIGN.md`'s "logic exists in exactly one place".
4. Vitest runs the fixtures in TS + its own property tests.

## 3. RegistryDO

Schema: `join_codes(code TEXT PRIMARY KEY, group_id TEXT NOT NULL, created_at INTEGER NOT NULL)`.

- `reserve(groupId) → joinCode` — generate a candidate, `INSERT`; on PK
  collision regenerate and retry (bounded loop). Returns the winning code.
- `resolve(code) → groupId | null`.
- **Rate limit** the resolve path (`DESIGN.md` §8): per-IP fixed-window
  counter, 20/min, in-DO `Map<ip, {count, windowStart}>`. Single-instance DO
  ⇒ this is a true global limiter, which is the intent. 21st request in a
  window → `429`.
- Tests: reserve/resolve round-trip, collision regeneration (seed the RNG),
  unknown code → null, limiter trips and resets.

## 4. GroupDO

Schema exactly as `DESIGN.md` §3, plus a `group_meta` row
`schema_version = "1"` from day one (`DESIGN.md` §10). Create tables in
`blockConcurrencyWhile` on first access.

Operations (invoked from the Worker; RPC methods or an internal `fetch`):

| op | does | returns / errors |
|---|---|---|
| `init(name, currency, creatorDisplayName, joinCode)` | write `group_meta`, insert first member | `{ member, group }` |
| `addMember(displayName)` | insert member | `{ member }` |
| `getState()` | read everything, run `balances` + `simplify` | full §2 `GET` body (incl. `joinCode` per §0.3) |
| `addExpense(body)` | validate → idempotency check on `id` → persist expense + splits | `{ expense }` / `SPLIT_MISMATCH`, `UNKNOWN_MEMBER`, `INVALID_AMOUNT` |
| `addSettlement(body)` | validate → idempotency → persist | `{ settlement }` / `UNKNOWN_MEMBER`, `INVALID_AMOUNT` |
| `exists()` | has this DO been initialised? | bool (for `GROUP_NOT_FOUND`) |

- **Idempotency** (`DESIGN.md` §2): `id` optional, client-generated UUID; if a
  row with that `id` already exists, return it unchanged (no-op replay).
- **Validation in the DO, independent of the client** (`DESIGN.md` §6):
  splits sum exactly; every `memberId` (payer, split members, settlement
  from/to) exists; amounts are positive integers; `splitType ∈ {equal, exact}`;
  **reject unknown fields** rather than ignoring them.
- Money columns are `INTEGER`; read back as `number`.
- GET ordering: `DESIGN.md` doesn't specify — use `created_at ASC` for both
  `expenses` and `settlements` and document it (matches `Export`'s
  oldest-first, and the iOS activity feed re-sorts by date anyway).
- Tests (`vitest-pool-workers`, real DO): every op's happy path, every error
  code, idempotent replay returns the original, full `getState()` shape,
  a 2-member and a 5-member scenario end-to-end.

## 5. Worker router + HTTP layer (`src/index.ts`)

Route table = `DESIGN.md` §2 verbatim, base `/api`:

```
POST   /api/groups
GET    /api/groups/resolve/:joinCode
POST   /api/groups/:groupId/members
GET    /api/groups/:groupId
POST   /api/groups/:groupId/expenses
POST   /api/groups/:groupId/settlements
```

- `POST /api/groups`: generate `groupId` (nanoid 16) → `REGISTRY_DO`
  (`idFromName("registry")`) `.reserve(groupId)` → `joinCode` →
  `GROUP_DO` (`idFromName(groupId)`) `.init(...)`. Response per §2.
- Group routes: `GROUP_DO.idFromName(groupId)`; if `!exists()` →
  `GROUP_NOT_FOUND` envelope 404.
- `GET /resolve` unknown → **bare 404**, no body (§0.4).
- Every failure → `{ error: { code, message } }` with the right status; map
  DO-thrown typed errors to it in one place.
- Strict per-endpoint body parsing: known fields only, reject extras (§6),
  cap body size.
- `X-Robots-Tag: noindex` on every `/api/groups/*` response (`DESIGN.md` §8).
- **No CORS headers** — the consumer is a native app, not a browser; if a web
  client is ever added, lock CORS to same-origin then (`DESIGN.md` §8).
- Unknown route / method → 404 / 405.
- Tests (`routes.test.ts`): each route happy path + each documented error, the
  resolve-then-join flow, idempotent POST retries, `noindex` header present.

## 6. The `/g/:groupId` capability page (can be a stub for v1)

`DESIGN.md` §1/§8: the Worker also serves the human-facing link.

- `GET /g/:groupId` → minimal HTML with
  `<meta name="robots" content="noindex">`, a "Open in Squarely" button
  (deep link `squarely://g/:groupId` for now), and the App Store link once
  there is one. Doesn't need the group's data.
- **Universal Links** (cross-refs the iOS "deferred" item): serve
  `/.well-known/apple-app-site-association` once there's an App ID and the iOS
  app adds the Associated Domains entitlement + a production domain. Then the
  `https://<host>/g/:groupId` links `RootView.extractGroupId` already parses
  start working without the `squarely://` scheme.

## 7. Local integration + re-verify the iOS app against the real backend

- `wrangler dev` on `:8787` (the port `AppConfig`'s comment and the
  verification mock already assume).
- The throwaway Python mock from the iOS runtime-verification pass is the
  behavioural reference — the real Worker should be a drop-in replacement at
  the same URL.
- Point `AppConfig.apiBaseURL` at `http://localhost:8787/` and **re-run the
  "App/ Runtime Verification" flow from `HANDOFF.md` against the real backend
  this time** — same script, real persistence, real balances/simplify.
- `vitest-pool-workers` integration suite green (§4/§5 tests).

## 8. Deploy

- `wrangler deploy` → `*.workers.dev` URL (or a custom domain — needed anyway
  for Universal Links and a shareable link that isn't ugly).
- Set `AppConfig.apiBaseURL` to the deployed URL — the **first real value it
  has ever had**. Small iOS commit.
- Re-run the iOS verification flow against production.
- Tag: bump the repo to **`v0.2.0`** — "iOS app + backend, working end to end".

## 9. Deferred (from `DESIGN.md` §12, still deferred)

- WebSocket live updates — same DO, add a WS handler; only if usage shows
  people actually have the app open at the same time.
- Optimistic UI on mutations.
- "Merge my old entries" for someone who loses local storage and rejoins.
- Multi-currency, recurring expenses, %/shares splitting, receipt OCR — out
  of scope per `PLAN.md` §1.

---

## Rollout order (TL;DR)

1. Scaffold `worker/` + `worker.yml` CI (§1)
2. **Pure logic + shared golden fixtures + SquareKit parity test (§2) ← start here**
3. RegistryDO (§3)
4. GroupDO (§4)
5. Worker router (§5)
6. `wrangler dev` + re-run iOS runtime verification against it (§7)
7. `wrangler deploy`, point `AppConfig` at prod, re-verify, tag `v0.2.0` (§8)
8. *(optional / later)* `/g/:groupId` page + AASA + Universal Links (§6)

Rough sizing: §2 ~half a day (mostly the fixtures) · §3-§5 ~1-2 days ·
§7-§8 ~half a day. The DO tests are where the time actually goes.

## Testing strategy (`DESIGN.md` §11)

| layer | tool | covers |
|---|---|---|
| unit | Vitest (no CF) | `balances` / `simplify` / `validation` + golden fixtures |
| parity | Vitest **and** `SquareKitTests` | same fixtures, both implementations — fails on drift |
| integration | `@cloudflare/vitest-pool-workers` | HTTP routes against real local DOs, Registry flow, idempotency, rate limit |
| manual | iOS app ↔ `wrangler dev`, then ↔ prod | the `HANDOFF.md` runtime-verification flow, for real |

The single-writer serialization guarantee (`DESIGN.md` §4) is a production
runtime property — not something Miniflare proves. Trust the platform; if it
ever needs checking, that's a small prod load test, not a unit test.

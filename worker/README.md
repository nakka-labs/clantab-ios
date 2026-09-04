# ClanTab Worker

The Cloudflare Worker + Durable Objects backend. Contract: `../DESIGN.md` §2-§8
(guest routes) and §13 (accounts / auth). Plan / status: `../BACKEND_PLAN.md`.
Accounts rationale: `../ACCOUNTS_DESIGN.md`.

**Deployed:** `https://clantab.nakka-labs.workers.dev` — accounts routes live
since 2026-09-04 (`SESSION_SIGNING_KEY` is a real secret).

## Layout

```
src/
├── index.ts        Worker entry + URLPattern router (DESIGN.md §2 incl.
│                   PUT/DELETE edit-delete, + §13 accounts)
├── registry-do.ts  RegistryDO  — joinCode ↔ groupId, per-IP rate limit
├── group-do.ts     GroupDO     — one group's SQLite ledger; server-computed balances;
│                                 claim / unclaim (schema v5, members.identity_sub)
├── user-do.ts      UserDO      — one per Apple sub; thin self-healing group index
├── types.ts        wire DTOs (mirror ClanTabKit's ClanTabWireTypes.swift)
└── lib/            balances / simplify / validation (ports of ClanTabKit Logic/),
                    apple-auth (Apple JWKS verify), session (HS256 session JWT),
                    base64url, ids, schema (SQL DDL), parse, errors, result
test/               logic + validation (Node) · registry/group/routes/user/auth (workers pool)
```

## Commands (`make worker-*` from the repo root, or directly here)

| | |
|---|---|
| `npm ci` | install (Node 20+) |
| `npm test` | Vitest — 111 tests (pure + `@cloudflare/vitest-pool-workers` integration) |
| `npm run typecheck` | `tsc --noEmit` |
| `npm run dev` | `wrangler dev` on `:8787` |
| `npm run deploy` | `wrangler deploy` (needs `wrangler login`) |

## Notes

- **Zero runtime dependencies.** Hand-rolled router; `crypto.getRandomValues` for ids;
  Apple-token and session JWTs verified with Web Crypto (`crypto.subtle`), no library.
- **The balance / simplify logic must stay identical to `ClanTabKit`** — both run the
  shared vectors in `../test-fixtures/balances/`.
- **DO methods return `Result` / discriminated unions for expected failures**, never
  `throw` — a thrown error loses its prototype across the RPC boundary.
- Storage: the DO SQLite API (`ctx.storage.sql`), schema in `src/lib/schema.ts`.
  `GroupDO` is at schema v5; `UserDO` at v1. wrangler migrations: `v1`
  (`GroupDO` + `RegistryDO`), `v2` (`UserDO`).
- **Accounts config** (`DESIGN.md` §13): `APPLE_AUDIENCE` is a `vars` entry.
  `SESSION_SIGNING_KEY` is **not** — a plain var overwrites a same-named secret on
  every `wrangler deploy`, so it's a real secret in prod
  (`wrangler secret put SESSION_SIGNING_KEY`), `worker/.dev.vars` (gitignored,
  see `.dev.vars.example`) for `wrangler dev`, and a fixed value in
  `vitest.workers.config.ts` for tests. The `SIWA_*` secrets for Apple token
  revocation on account deletion aren't set yet — a submission prerequisite;
  `DELETE /api/auth/account` stubs revocation with a TODO.
- **Auth is additive** — the group routes are still `groupId`-possession only.
  Never add a session check to them.
- `GET /g/:groupId` is a stub landing page (noindex + app deep link). A real page +
  Universal Links come with a production domain — `BACKEND_PLAN.md` §6.

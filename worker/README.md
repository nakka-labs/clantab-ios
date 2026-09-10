# ClanTab Worker

The Cloudflare Worker + Durable Objects backend. Contract: `../DESIGN.md` §2-§8
(group routes) and §13 (accounts / auth). Status: `../CHECKLIST.md`.

**Deployed:** `https://clantab.nakka-labs.workers.dev` — accounts routes live
since 2026-09-04 (`SESSION_SIGNING_KEY` is a real secret).

## Layout

```
src/
├── index.ts        Worker entry + URLPattern router (DESIGN.md §2 incl.
│                   PUT/DELETE edit-delete, + §13 accounts)
├── group-do.ts     GroupDO     — one group's SQLite ledger; server-computed balances;
│                                 claim / unclaim (schema v5, members.identity_sub)
├── user-do.ts      UserDO      — one per signed-in identity (provider:sub); thin self-healing group index
├── types.ts        wire DTOs (mirror ClanTabKit's ClanTabWireTypes.swift)
└── lib/            balances / simplify / validation (ports of ClanTabKit Logic/),
                    apple-auth (Apple JWKS verify), apple-oauth (code exchange +
                    token revocation), session (HS256 session JWT), base64url,
                    ids, join-codes (joinCode ↔ groupId in Workers KV, rate-limit
                    binding), schema (SQL DDL), parse,
                    errors, result
test/               logic + validation (Node) · join-codes/group/routes/user/auth/
                    apple-oauth (workers pool)
```

## Commands (`make worker-*` from the repo root, or directly here)

| | |
|---|---|
| `npm ci` | install (Node 20+) |
| `npm test` | Vitest — 133 tests (pure + `@cloudflare/vitest-pool-workers` integration) |
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
  (`GroupDO` + `RegistryDO`), `v2` (`UserDO`), `v3` (`RegistryDO` deleted —
  its one job, joinCode↔groupId, moved to the `JOIN_CODES` KV namespace so
  it's no longer a singleton chokepoint; `src/lib/join-codes.ts`).
- **Accounts config** (`DESIGN.md` §13): `APPLE_AUDIENCE` is a `vars` entry.
  `SESSION_SIGNING_KEY` is **not** — a plain var overwrites a same-named secret on
  every `wrangler deploy`, so it's a real secret in prod
  (`wrangler secret put SESSION_SIGNING_KEY`), `worker/.dev.vars` (gitignored,
  see `.dev.vars.example`) for `wrangler dev`, and a fixed value in
  `vitest.workers.config.ts` for tests. `SIWA_SERVICES_ID` / `SIWA_TEAM_ID` /
  `SIWA_KEY_ID` / `SIWA_PRIVATE_KEY` (all four or none) drive the Apple
  authorization-code exchange + token revocation on account deletion
  (`lib/apple-oauth.ts`) — the code is done and inert until the secrets are set;
  configured in production since 2026-09-04 (`DESIGN.md` §13 Config).
- **Auth is additive** — the group routes are still `groupId`-possession only.
  Never add a session check to them.
- **Image storage** (`CHECKLIST.md` "Image storage backend (R2)"): one R2 bucket
  (`MEDIA` binding). `POST /api/media/presign` hands the client a 5-minute
  presigned S3 URL — the Worker never proxies image bytes. Uploads pin
  `Content-Type`/`Content-Length` (signed into the URL); 5 MB / JPEG-PNG-WebP
  cap in `lib/media.ts`. Keys are derived server-side (`avatars/<hash>`,
  `groups/<id>/cover`, `expenses/<gid>/<eid>/<id>`), never taken from the
  client. Group-scoped ops need claimed membership, not just the capability
  link. `lib/s3-presign.ts` is a hand-rolled SigV4 signer (zero deps, checked
  against AWS's documented vector in `test/media.test.ts`). Config:
  `R2_BUCKET` var + `R2_ACCOUNT_ID`/`R2_ACCESS_KEY_ID`/`R2_SECRET_ACCESS_KEY`
  secrets; all unset → the endpoint 503s (safe until configured). Delete-on-
  delete cleanup is wired per-surface as profile-photo / cover / receipt ship.
- `GET /g/:groupId` is a stub landing page (noindex + app deep link). A real page +
  Universal Links come with a production domain — see `CHECKLIST.md`'s
  "custom domain + Universal Links" item.

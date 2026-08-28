# Squarely Worker

The Cloudflare Worker + Durable Objects backend. Contract: `../DESIGN.md` §2-§8.
Plan / status: `../BACKEND_PLAN.md`.

**Deployed:** `https://squarely.nakka-labs.workers.dev`

## Layout

```
src/
├── index.ts        Worker entry + URLPattern router (all of DESIGN.md §2)
├── registry-do.ts  RegistryDO  — joinCode ↔ groupId, per-IP rate limit
├── group-do.ts     GroupDO     — one group's SQLite ledger; server-computed balances
├── types.ts        wire DTOs (mirror SquareKit's SquarelyWireTypes.swift)
└── lib/            balances / simplify / validation (ports of SquareKit Logic/),
                    ids, schema (SQL DDL), parse (strict body parsing), errors, result
test/               logic + validation (Node) · registry/group/routes (workers pool)
```

## Commands (`make worker-*` from the repo root, or directly here)

| | |
|---|---|
| `npm ci` | install (Node 20+) |
| `npm test` | Vitest — 54 tests (pure + `@cloudflare/vitest-pool-workers` integration) |
| `npm run typecheck` | `tsc --noEmit` |
| `npm run dev` | `wrangler dev` on `:8787` |
| `npm run deploy` | `wrangler deploy` (needs `wrangler login`) |

## Notes

- **Zero runtime dependencies.** Hand-rolled router; `crypto.getRandomValues` for ids.
- **The balance / simplify logic must stay identical to `SquareKit`** — both run the
  shared vectors in `../test-fixtures/balances/`.
- **DO methods return `Result` / discriminated unions for expected failures**, never
  `throw` — a thrown error loses its prototype across the RPC boundary.
- Storage: the DO SQLite API (`ctx.storage.sql`), schema in `src/lib/schema.ts`,
  `v1` migration in `wrangler.jsonc`.
- `GET /g/:groupId` is a stub landing page (noindex + app deep link). A real page +
  Universal Links come with a production domain — `BACKEND_PLAN.md` §6.

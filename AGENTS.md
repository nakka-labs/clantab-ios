# ClanTab (iOS)

Open-source, no-login expense splitter for small groups. Native iOS application powered by a pure Swift core package (`ClanTabKit`). No accounts, no payments, no ads.

## Commands
- `make check` — run everything relevant (ClanTabKit + worker + iOS build/tests). Same as what the `pre-push` hook runs; `make hooks` installs it.
- `swift test --package-path ClanTabKit` or `make test` — the pure Swift core (no Apple frameworks; also runs on the Linux CI)
- `swift build --package-path ClanTabKit` — build the core package
- `App/` (the SwiftUI shell) requires Xcode on macOS. `cd App && xcodegen generate`, then the `ClanTab` scheme. See `App/README.md`.
- `worker/` (Cloudflare Worker backend — `BACKEND_PLAN.md`): `npm --prefix worker ci`, then `make worker-test` / `worker-typecheck` / `worker-dev`. `make worker-deploy` needs `wrangler login`.

## CI
- The repo is **public**, so GitHub-hosted runners (Linux and macOS) are unmetered.
- `.github/workflows/`: `test.yml` (ClanTabKit, Linux) and `worker.yml` (Worker, Linux) run on push. `worker-deploy.yml` deploys on `v*` tags (needs a `CLOUDFLARE_API_TOKEN` secret). `pages.yml` publishes `docs/privacy-policy.md` to GitHub Pages.
- **The iOS build is NOT in cloud CI** — it runs in the `pre-push` hook on the dev's Mac for fast local feedback. A macOS CI job is now cost-free to add if PR-time checks are wanted; don't add one without a reason.

## Backend (`worker/`)
- **Same rules as `ClanTabKit`**: integer minor units only, derived balances, zero runtime dependencies (dev deps like `vitest`/`typescript` are fine). Hand-rolled router (`URLPattern`) over a framework.
- **Logic mirrors `ClanTabKit`, kept honest by fixtures**: `worker/src/lib/balances.ts` / `simplify.ts` / `validation.ts` are ports of the Swift `Logic/` files. Both implementations run the shared vectors in `test-fixtures/balances/` (`worker/test/logic.test.ts` and `ClanTabKitTests/GoldenParityTests.swift`) — change one language and the other's CI fails until it matches.
- **Durable Object methods return `Result` / discriminated unions for expected failures, not `throw`** — a thrown error loses its prototype across the RPC boundary, so `instanceof` checks in the router break. Only genuinely-exceptional cases throw (→ 500).
- **Ordering**: `Date.now()` is not monotonic enough within a DO (rapid RPC calls collide on the same ms). Order by `created_at ASC, rowid ASC`.
- `DESIGN.md` is the wire/storage/security contract. `make worker-dev` runs `wrangler dev` on `:8787`. `make worker-test` / `worker-typecheck`. Deploy (`make worker-deploy`) needs `wrangler login` first.

## Architecture Rules
- **Pure Core Logic in `ClanTabKit`**: `Balances.swift`, `Simplify.swift`, `Validation.swift`, `Insights.swift`, and `ActivityFilter.swift` are pure functions. No I/O, no network calls, no UI dependencies. If a test needs a mock or a running network server to test business math, move the impure logic elsewhere.
- **Integer Minor Units**: All money amounts are stored and calculated in integer minor units (paise, cents, yen) as `Int` or `Int64`. Never use floating-point types (`Double`, `Float`) for monetary amounts or arithmetic. Convert to/from display units only at the UI formatting edge.
- **Derived Balances**: Member balances are always derived on read from the collection of expenses and settlements; never cache or persist a mutable "balance" field.
- **Zero-Login / Capability Links**: Each group is addressed by an unguessable capability identifier (`groupId`) and an optional 6-character human-friendly `joinCode`. User identity is stored locally on the device (per group).
- **Split Integrity**: Every split in an expense must sum up exactly to the total `amountMinor`. Remainder paise/cents from equal or percentage divisions are deterministically assigned (e.g., to the payer) before dispatch. `splitType` (`equal` / `exact` / `percentage`) is a descriptive label — `percentage` is resolved to minor-unit shares client-side (`Validation.percentageSplit`), never sent as raw percentages.

## Non-Goals — Do Not Add Without Explicit Request
- No accounts, login systems, or passwords.
- No payment processing, banking integration, or money transfer — ever.
- No FX conversion. A group can hold expenses in multiple currencies, but balances and settle-up are computed per currency and never blended — the group's `currency` is only the default for new expenses.
- No recurring expenses or subscription models.
- No receipt OCR / paid cloud AI services in core v1.
- No push notification servers or email collection.

## Conventions
- Swift 6 language standard, strict concurrency checking.
- Commit format: `feat|fix|test|chore|docs(scope): description`
- Every modification to `Balances.swift`/`Simplify.swift` (or their `worker/src/lib/` ports) must be accompanied by unit tests, and the two languages must agree on `test-fixtures/balances/`.

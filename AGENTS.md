# Squarely (iOS)

Open-source, no-login expense splitter for small groups. Native iOS application powered by a pure Swift core package (`SquareKit`). No accounts, no payments, no ads.

## Commands
- `swift test --package-path SquareKit` or `make test` — run fast unit tests (Windows, macOS, Linux)
- `swift build --package-path SquareKit` — build the core package
- `App/` (the SwiftUI shell) requires Xcode on macOS — it cannot be built or tested on Windows/Linux. See `App/README.md` for setup (`xcodegen generate`) and its current verification status before assuming it builds.
- `worker/` (Cloudflare Worker backend, in progress — see `BACKEND_PLAN.md`): `npm --prefix worker ci`, then `npm --prefix worker test` and `npm --prefix worker run typecheck`. Node only; no Cloudflare account needed for the current layer.

## Backend (`worker/`)
- **Same rules as `SquareKit`**: integer minor units only, derived balances, zero runtime dependencies (dev deps like `vitest`/`typescript` are fine). Hand-rolled router over a framework.
- **Logic mirrors `SquareKit`, kept honest by fixtures**: `worker/src/lib/balances.ts` / `simplify.ts` / `validation.ts` are ports of the Swift `Logic/` files. Both implementations run the shared vectors in `test-fixtures/balances/` (`worker/test/logic.test.ts` and `SquareKitTests/GoldenParityTests.swift`) — change one language and the other's CI fails until it matches.
- `DESIGN.md` is the wire/storage/security contract. Local dev: `wrangler dev` on `:8787` (once the Worker entry exists).

## Architecture Rules
- **Pure Core Logic in `SquareKit`**: `Balances.swift` and `Simplify.swift` are pure functions. No I/O, no network calls, no UI dependencies. If a test needs a mock or a running network server to test business math, move the impure logic elsewhere.
- **Integer Minor Units**: All money amounts are stored and calculated in integer minor units (paise, cents, yen) as `Int` or `Int64`. Never use floating-point types (`Double`, `Float`) for monetary amounts or arithmetic. Convert to/from display units only at the UI formatting edge.
- **Derived Balances**: Member balances are always derived on read from the collection of expenses and settlements; never cache or persist a mutable "balance" field.
- **Zero-Login / Capability Links**: Each group is addressed by an unguessable capability identifier (`groupId`) and an optional 6-character human-friendly `joinCode`. User identity is stored locally on the device (per group).
- **Split Integrity**: Every split in an expense must sum up exactly to the total `amountMinor`. Remainder paise/cents from equal divisions are deterministically assigned (e.g., to the payer) before dispatch.

## Non-Goals — Do Not Add Without Explicit Request
- No accounts, login systems, or passwords.
- No payment processing, banking integration, or money transfer — ever.
- No multi-currency per group (one currency fixed at group creation for v1).
- No recurring expenses or subscription models.
- No receipt OCR / paid cloud AI services in core v1.
- No push notification servers or email collection.
- No percentage or shares splitting in v1 (equal and exact amounts only).

## Conventions
- Swift 6 language standard, strict concurrency checking.
- Commit format: `feat|fix|test|chore|docs(scope): description`
- Every modification to `Balances.swift`/`Simplify.swift` (or their `worker/src/lib/` ports) must be accompanied by unit tests, and the two languages must agree on `test-fixtures/balances/`.

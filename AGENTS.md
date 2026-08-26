# Squarely (iOS)

Open-source, no-login expense splitter for small groups. Native iOS application powered by a pure Swift core package (`SquareKit`). No accounts, no payments, no ads.

## Commands
- `swift test --package-path SquareKit` or `make test` — run fast unit tests (Windows, macOS, Linux)
- `swift build --package-path SquareKit` — build the core package

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
- Every modification to `Balances.swift` or `Simplify.swift` must be accompanied by unit tests.

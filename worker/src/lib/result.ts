// Durable Object methods return these instead of throwing for *expected* failures:
// a thrown error loses its prototype across the RPC boundary, so `instanceof`
// checks in the router don't work. Truly-exceptional cases still throw (→ 500).

import type { ValidationCode } from "./validation.ts";

export interface DomainError {
  code: ValidationCode;
  message: string;
}

export type Result<T> = { ok: true; value: T } | { ok: false; error: DomainError };

export const ok = <T>(value: T): Result<T> => ({ ok: true, value });

export const fail = (code: ValidationCode, message: string): Result<never> => ({
  ok: false,
  error: { code, message },
});

// Strict request-body parsing. `DESIGN.md` §6: "Reject unknown fields rather than
// silently ignoring them (fail loud during development)."

import { BadRequestError } from "./errors.ts";

type Obj = Record<string, unknown>;

export function assertPlainObject(value: unknown, what = "body"): asserts value is Obj {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new BadRequestError(`Expected ${what} to be a JSON object.`);
  }
}

export async function readJsonObject(request: Request): Promise<Obj> {
  let raw: unknown;
  try {
    raw = await request.json();
  } catch {
    throw new BadRequestError("Request body must be valid JSON.");
  }
  assertPlainObject(raw);
  return raw;
}

export function rejectUnknownKeys(obj: Obj, allowed: readonly string[]): void {
  for (const key of Object.keys(obj)) {
    if (!allowed.includes(key)) {
      throw new BadRequestError(`Unknown field "${key}".`);
    }
  }
}

export function requireString(obj: Obj, key: string): string {
  const v = obj[key];
  if (typeof v !== "string" || v.trim().length === 0) {
    throw new BadRequestError(`Field "${key}" must be a non-empty string.`);
  }
  return v;
}

export function optionalString(obj: Obj, key: string): string | undefined {
  const v = obj[key];
  if (v === undefined) return undefined;
  if (typeof v !== "string" || v.length === 0) {
    throw new BadRequestError(`Field "${key}", if present, must be a non-empty string.`);
  }
  return v;
}

/** Like `optionalString`, but an explicit JSON `null` is also accepted, to
 * mean "clear this field" — distinct from the key being absent entirely
 * ("leave it alone"). An empty string is still rejected either way; `null`
 * is the one way to say "nothing," so it stays unambiguous. */
export function optionalStringOrNull(obj: Obj, key: string): string | null | undefined {
  const v = obj[key];
  if (v === undefined) return undefined;
  if (v === null) return null;
  if (typeof v !== "string" || v.length === 0) {
    throw new BadRequestError(`Field "${key}", if present, must be a non-empty string or null.`);
  }
  return v;
}

export function optionalBoolean(obj: Obj, key: string): boolean | undefined {
  const v = obj[key];
  if (v === undefined) return undefined;
  if (typeof v !== "boolean") {
    throw new BadRequestError(`Field "${key}", if present, must be a boolean.`);
  }
  return v;
}

export function requireInteger(obj: Obj, key: string): number {
  const v = obj[key];
  if (typeof v !== "number" || !Number.isInteger(v)) {
    throw new BadRequestError(`Field "${key}" must be an integer.`);
  }
  return v;
}

export function optionalInteger(obj: Obj, key: string): number | undefined {
  const v = obj[key];
  if (v === undefined) return undefined;
  if (typeof v !== "number" || !Number.isInteger(v)) {
    throw new BadRequestError(`Field "${key}", if present, must be an integer.`);
  }
  return v;
}

/** Like `requireString`, but for a field the iOS client decodes as `Date`
 * with `JSONDecoder.dateDecodingStrategy = .iso8601` — `ISO8601DateFormatter`
 * with its default options, which requires a full date-time
 * ("2026-09-10T00:00:00Z"), not a bare date ("2026-09-10"). `requireString`
 * alone would accept either, and the app's own UI only ever sends the full
 * form — but nothing stopped a malformed one from reaching here (a bug
 * elsewhere, a future caller, a hand-built request). Once stored, *every*
 * client's next `fetchGroupState` for that group fails to decode the whole
 * response and gets stuck — there's no way to fix it through the app either,
 * since loading the edit screen needs that same decode to succeed first.
 * Rejecting the bad shape at the door is cheap insurance against a group
 * becoming permanently unusable for everyone in it. */
export function requireISODate(obj: Obj, key: string): string {
  const v = requireString(obj, key);
  const isFullISO8601 = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/.test(v);
  if (!isFullISO8601 || Number.isNaN(new Date(v).getTime())) {
    throw new BadRequestError(`Field "${key}" must be a full ISO 8601 date-time (e.g. "2026-09-10T00:00:00Z").`);
  }
  return v;
}

export function requireArray(obj: Obj, key: string): unknown[] {
  const v = obj[key];
  if (!Array.isArray(v)) {
    throw new BadRequestError(`Field "${key}" must be an array.`);
  }
  return v;
}

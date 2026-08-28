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

export function requireInteger(obj: Obj, key: string): number {
  const v = obj[key];
  if (typeof v !== "number" || !Number.isInteger(v)) {
    throw new BadRequestError(`Field "${key}" must be an integer.`);
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

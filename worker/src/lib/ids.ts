// Identifier generation for `DESIGN.md` §1's two distinct IDs. Both alphabets
// have a length that divides 256, so `byte % length` is free of modulo bias and
// a plain `crypto.getRandomValues` loop is enough.

/** URL-safe, 64 symbols. */
const GROUP_ID_ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_";

/**
 * 32 symbols, uppercase, no visually ambiguous glyphs: A-Z minus I and O (24),
 * plus 2-9 (8). Matches `DESIGN.md` §1 ("no 0/O/1/I/l" — codes are uppercase, so
 * lowercase l never appears; L is kept).
 */
const JOIN_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function randomString(alphabet: string, length: number): string {
  const n = alphabet.length; // 64 or 32 — both divide 256
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  let out = "";
  for (let i = 0; i < length; i++) out += alphabet[bytes[i]! % n];
  return out;
}

/** 16 chars over 64 symbols ≈ 96 bits (`DESIGN.md` §1: nanoid, ~95 bits). */
export function newGroupId(): string {
  return randomString(GROUP_ID_ALPHABET, 16);
}

/** 6 chars, human-typeable, deliberately low-entropy (`DESIGN.md` §1). */
export function newJoinCode(): string {
  return randomString(JOIN_CODE_ALPHABET, 6);
}

/** 22 chars over 64 symbols ≈ 132 bits — the rotatable capability-link
 * credential (`ACCESS_TOKEN_PLAN.md`), deliberately higher-entropy than
 * `groupId` itself since unlike `groupId` this is *meant* to be revoked and
 * reissued, never guessed. */
export function newAccessToken(): string {
  return randomString(GROUP_ID_ALPHABET, 22);
}

/** Server-assigned member id. Not user-facing; just needs to be unique per group. */
export function newMemberId(): string {
  return randomString(GROUP_ID_ALPHABET, 12);
}

/**
 * Server-assigned id for an expense or settlement when the client didn't supply
 * one. Client-supplied ids (for idempotent retries, `DESIGN.md` §2) are UUIDs.
 */
export function newRecordId(): string {
  return randomString(GROUP_ID_ALPHABET, 16);
}

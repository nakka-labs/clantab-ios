// Sign in with Apple identity-token verification (`ACCOUNTS_DESIGN.md` §5).
//
// Hand-rolled with Web Crypto — the Worker has zero runtime dependencies and we
// keep it that way. Apple's identity token is an RS256 JWT; we verify its
// signature against Apple's published JWKS, then check `iss` / `aud` / `exp`.
//
// Deviation from `ACCOUNTS_DESIGN.md` §5: the JWKS is cached in a module-level
// variable (per-isolate, ~24h TTL, plus a one-shot refetch on a `kid` miss)
// rather than in a KV namespace. Apple rotates keys rarely, verification runs at
// sign-in only, and this avoids provisioning a KV binding. A cold isolate just
// does one extra fetch. Revisit if sign-in latency or Apple's rate limits bite.

import { b64urlDecode, b64urlDecodeJson } from "./base64url.ts";

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys";
const JWKS_TTL_MS = 24 * 60 * 60 * 1000;

/** A single RSA key from Apple's JWKS. `use` / `alg` are advisory and not all
 * JWK exporters emit them, so only the fields we actually consume are required. */
export interface AppleJwk {
  kty: string;
  kid: string;
  n: string;
  e: string;
  use?: string;
  alg?: string;
}

/** Fetches Apple's current signing keys. `force` bypasses the cache (used once
 * on a `kid` miss, in case Apple just rotated). Injectable for tests. */
export type JwksFetcher = (force?: boolean) => Promise<AppleJwk[]>;

export class AppleAuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AppleAuthError";
  }
}

let jwksCache: { keys: AppleJwk[]; fetchedAt: number } | undefined;

const defaultFetchJwks: JwksFetcher = async (force = false) => {
  if (!force && jwksCache !== undefined && Date.now() - jwksCache.fetchedAt < JWKS_TTL_MS) {
    return jwksCache.keys;
  }
  const res = await fetch(APPLE_JWKS_URL);
  if (!res.ok) throw new AppleAuthError(`Apple JWKS fetch failed (${res.status}).`);
  const body = (await res.json()) as { keys: AppleJwk[] };
  jwksCache = { keys: body.keys, fetchedAt: Date.now() };
  return body.keys;
};

interface AppleJwtHeader {
  alg: string;
  kid: string;
}
interface AppleJwtPayload {
  iss: string;
  aud: string | string[];
  sub: string;
  exp: number;
  iat: number;
  email?: string;
}

/**
 * Verify an Apple identity token. Resolves to the stable Apple subject id
 * (`sub`) or throws `AppleAuthError`. `email` is returned when Apple included it
 * (first sign-in only) but the product doesn't use it.
 */
export async function verifyAppleIdentityToken(
  token: string,
  opts: { audience: string; now?: number; fetchJwks?: JwksFetcher },
): Promise<{ sub: string; email?: string }> {
  const now = opts.now ?? Date.now();
  const fetchJwks = opts.fetchJwks ?? defaultFetchJwks;

  const parts = token.split(".");
  if (parts.length !== 3) throw new AppleAuthError("Malformed identity token.");
  const [headerB64, payloadB64, signatureB64] = parts as [string, string, string];

  let header: AppleJwtHeader;
  let payload: AppleJwtPayload;
  try {
    header = b64urlDecodeJson<AppleJwtHeader>(headerB64);
    payload = b64urlDecodeJson<AppleJwtPayload>(payloadB64);
  } catch {
    throw new AppleAuthError("Unreadable identity token.");
  }

  if (header.alg !== "RS256") throw new AppleAuthError(`Unexpected token algorithm "${header.alg}".`);

  let jwk = (await fetchJwks()).find((k) => k.kid === header.kid);
  if (jwk === undefined) {
    jwk = (await fetchJwks(true)).find((k) => k.kid === header.kid);
  }
  if (jwk === undefined) throw new AppleAuthError("No Apple key matches the token's kid.");

  const key = await crypto.subtle.importKey(
    "jwk",
    { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"],
  );
  const signed = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    b64urlDecode(signatureB64),
    signed,
  );
  if (!valid) throw new AppleAuthError("Identity-token signature does not verify.");

  if (payload.iss !== APPLE_ISSUER) throw new AppleAuthError(`Wrong issuer "${payload.iss}".`);
  const audiences = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!audiences.includes(opts.audience)) throw new AppleAuthError("Token audience mismatch.");
  if (typeof payload.exp !== "number" || payload.exp * 1000 <= now) {
    throw new AppleAuthError("Identity token has expired.");
  }
  if (typeof payload.sub !== "string" || payload.sub.length === 0) {
    throw new AppleAuthError("Identity token has no subject.");
  }

  return payload.email !== undefined
    ? { sub: payload.sub, email: payload.email }
    : { sub: payload.sub };
}

/** Test seam: reset the module-level JWKS cache between cases. */
export function __resetJwksCache(): void {
  jwksCache = undefined;
}

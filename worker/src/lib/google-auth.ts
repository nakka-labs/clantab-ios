// Google Sign-In identity-token verification (`MANDATORY_LOGIN_PLAN.md` Part 1).
//
// Hand-rolled with Web Crypto, no library — same discipline as `apple-auth.ts`
// and the zero-third-party-dependency rule (`AGENTS.md`, `DESIGN.md` §7).
// Google's identity token is an RS256 JWT; we verify its signature against
// Google's published JWKS, then check `iss` / `aud` / `exp`.
//
// Same JWKS-caching tradeoff as `apple-auth.ts`: module-level, ~24h TTL, one
// forced refetch on a `kid` miss. Google rotates keys rarely and verification
// runs at sign-in only.

import { b64urlDecode, b64urlDecodeJson } from "./base64url.ts";

// Google documents both forms as valid `iss` values — some libraries emit the
// bare host, most emit the full URL.
const GOOGLE_ISSUERS = ["https://accounts.google.com", "accounts.google.com"];
const GOOGLE_JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs";
const JWKS_TTL_MS = 24 * 60 * 60 * 1000;

/** A single RSA key from Google's JWKS. */
export interface GoogleJwk {
  kty: string;
  kid: string;
  n: string;
  e: string;
  use?: string;
  alg?: string;
}

/** Fetches Google's current signing keys. `force` bypasses the cache (used
 * once on a `kid` miss). Injectable for tests. */
export type JwksFetcher = (force?: boolean) => Promise<GoogleJwk[]>;

export class GoogleAuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GoogleAuthError";
  }
}

let jwksCache: { keys: GoogleJwk[]; fetchedAt: number } | undefined;

const defaultFetchJwks: JwksFetcher = async (force = false) => {
  if (!force && jwksCache !== undefined && Date.now() - jwksCache.fetchedAt < JWKS_TTL_MS) {
    return jwksCache.keys;
  }
  const res = await fetch(GOOGLE_JWKS_URL);
  if (!res.ok) throw new GoogleAuthError(`Google JWKS fetch failed (${res.status}).`);
  const body = (await res.json()) as { keys: GoogleJwk[] };
  jwksCache = { keys: body.keys, fetchedAt: Date.now() };
  return body.keys;
};

interface GoogleJwtHeader {
  alg: string;
  kid: string;
}
interface GoogleJwtPayload {
  iss: string;
  aud: string | string[];
  sub: string;
  exp: number;
  iat: number;
  email?: string;
}

/**
 * Verify a Google identity token. Resolves to the stable Google subject id
 * (`sub`) or throws `GoogleAuthError`. `email` is returned when present
 * (granted by the `email` scope) but the product doesn't use it.
 */
export async function verifyGoogleIdentityToken(
  token: string,
  opts: { audience: string; now?: number; fetchJwks?: JwksFetcher },
): Promise<{ sub: string; email?: string }> {
  const now = opts.now ?? Date.now();
  const fetchJwks = opts.fetchJwks ?? defaultFetchJwks;

  const parts = token.split(".");
  if (parts.length !== 3) throw new GoogleAuthError("Malformed identity token.");
  const [headerB64, payloadB64, signatureB64] = parts as [string, string, string];

  let header: GoogleJwtHeader;
  let payload: GoogleJwtPayload;
  try {
    header = b64urlDecodeJson<GoogleJwtHeader>(headerB64);
    payload = b64urlDecodeJson<GoogleJwtPayload>(payloadB64);
  } catch {
    throw new GoogleAuthError("Unreadable identity token.");
  }

  if (header.alg !== "RS256") throw new GoogleAuthError(`Unexpected token algorithm "${header.alg}".`);

  let jwk = (await fetchJwks()).find((k) => k.kid === header.kid);
  if (jwk === undefined) {
    jwk = (await fetchJwks(true)).find((k) => k.kid === header.kid);
  }
  if (jwk === undefined) throw new GoogleAuthError("No Google key matches the token's kid.");

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
  if (!valid) throw new GoogleAuthError("Identity-token signature does not verify.");

  if (!GOOGLE_ISSUERS.includes(payload.iss)) throw new GoogleAuthError(`Wrong issuer "${payload.iss}".`);
  const audiences = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!audiences.includes(opts.audience)) throw new GoogleAuthError("Token audience mismatch.");
  if (typeof payload.exp !== "number" || payload.exp * 1000 <= now) {
    throw new GoogleAuthError("Identity token has expired.");
  }
  if (typeof payload.sub !== "string" || payload.sub.length === 0) {
    throw new GoogleAuthError("Identity token has no subject.");
  }

  return payload.email !== undefined
    ? { sub: payload.sub, email: payload.email }
    : { sub: payload.sub };
}

/** Test seam: reset the module-level JWKS cache between cases. */
export function __resetJwksCache(): void {
  jwksCache = undefined;
}

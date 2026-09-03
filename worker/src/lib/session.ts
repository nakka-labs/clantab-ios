// Stateless session tokens (`ACCOUNTS_DESIGN.md` §3).
//
// Our own minimal JWT: `{ sub, iat, exp }`, HS256 (HMAC-SHA256) with
// `env.SESSION_SIGNING_KEY`, 30-day expiry, no server-side revocation. Verified
// locally on every authed request — no DO round-trip.

import { b64urlDecodeJson, b64urlEncode, b64urlEncodeJson } from "./base64url.ts";

const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000;

export class SessionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SessionError";
  }
}

interface SessionPayload {
  sub: string;
  iat: number;
  exp: number;
}

/** Mint a fresh session token for `sub`. `expiresAt` is ISO 8601, for the client
 * to decide when to refresh. */
export async function mintSession(
  sub: string,
  signingKey: string,
  now: number = Date.now(),
): Promise<{ token: string; expiresAt: string }> {
  const iat = Math.floor(now / 1000);
  const exp = Math.floor((now + SESSION_TTL_MS) / 1000);
  const header = b64urlEncodeJson({ alg: "HS256", typ: "JWT" });
  const payload = b64urlEncodeJson({ sub, iat, exp } satisfies SessionPayload);
  const signature = await sign(`${header}.${payload}`, signingKey);
  return { token: `${header}.${payload}.${signature}`, expiresAt: new Date(exp * 1000).toISOString() };
}

/** Verify a session token's signature and expiry. Resolves to `sub` or throws
 * `SessionError`. Never hits a DO. */
export async function verifySession(
  token: string,
  signingKey: string,
  now: number = Date.now(),
): Promise<{ sub: string }> {
  const parts = token.split(".");
  if (parts.length !== 3) throw new SessionError("Malformed session token.");
  const [header, payload, signature] = parts as [string, string, string];

  const expected = await sign(`${header}.${payload}`, signingKey);
  if (!timingSafeEqual(signature, expected)) {
    throw new SessionError("Session-token signature does not verify.");
  }

  let claims: SessionPayload;
  try {
    claims = b64urlDecodeJson<SessionPayload>(payload);
  } catch {
    throw new SessionError("Unreadable session token.");
  }
  if (typeof claims.exp !== "number" || claims.exp * 1000 <= now) {
    throw new SessionError("Session has expired.");
  }
  if (typeof claims.sub !== "string" || claims.sub.length === 0) {
    throw new SessionError("Session token has no subject.");
  }
  return { sub: claims.sub };
}

async function sign(data: string, signingKey: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(signingKey),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(data));
  return b64urlEncode(new Uint8Array(mac));
}

/** Constant-time string compare — both inputs are our own base64url HMACs of
 * fixed length, but don't leak via early exit. */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

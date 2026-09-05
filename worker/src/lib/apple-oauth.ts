// Sign in with Apple OAuth — the authorization-code exchange and token
// revocation needed for account deletion (Apple Guideline 5.1.1(v),
// `ACCOUNTS_DESIGN.md` §11).
//
// Hand-rolled with Web Crypto, no library. The `client_secret` is an ES256 JWT
// signed with the team's `.p8` key.

import { b64urlEncode } from "./base64url.ts";
import { pemToDer } from "./pem.ts";

const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";
const APPLE_AUD = "https://appleid.apple.com";

/** The four secrets from the Apple Developer portal. */
export interface SiwaConfig {
  /** The Services ID — the OAuth `client_id` (NOT the app bundle id). */
  servicesId: string;
  teamId: string;
  /** The 10-char id of the `.p8` "Sign in with Apple" key. */
  keyId: string;
  /** The `.p8` file contents (PKCS#8 PEM, `-----BEGIN PRIVATE KEY-----` …). */
  privateKeyPem: string;
}

/** `{ SIWA_SERVICES_ID, SIWA_TEAM_ID, SIWA_KEY_ID, SIWA_PRIVATE_KEY }` → a
 * config, or `null` if any is missing (revocation is then a no-op — sign-in and
 * local deletion still work). */
export function siwaConfigFromEnv(env: {
  SIWA_SERVICES_ID?: string;
  SIWA_TEAM_ID?: string;
  SIWA_KEY_ID?: string;
  SIWA_PRIVATE_KEY?: string;
}): SiwaConfig | null {
  const { SIWA_SERVICES_ID, SIWA_TEAM_ID, SIWA_KEY_ID, SIWA_PRIVATE_KEY } = env;
  if (!SIWA_SERVICES_ID || !SIWA_TEAM_ID || !SIWA_KEY_ID || !SIWA_PRIVATE_KEY) return null;
  return {
    servicesId: SIWA_SERVICES_ID,
    teamId: SIWA_TEAM_ID,
    keyId: SIWA_KEY_ID,
    privateKeyPem: SIWA_PRIVATE_KEY,
  };
}

export class AppleOAuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AppleOAuthError";
  }
}

interface CallOpts {
  fetchImpl?: typeof fetch;
  now?: number;
}

/** The ES256 `client_secret` JWT Apple's token endpoints require. Valid for
 * ~10 minutes (Apple's max is 6 months; short is fine, we mint per call). */
export async function mintClientSecret(config: SiwaConfig, now: number = Date.now()): Promise<string> {
  const iat = Math.floor(now / 1000);
  const header = b64urlEncode(new TextEncoder().encode(JSON.stringify({ alg: "ES256", kid: config.keyId })));
  const payload = b64urlEncode(
    new TextEncoder().encode(
      JSON.stringify({
        iss: config.teamId,
        iat,
        exp: iat + 600,
        aud: APPLE_AUD,
        sub: config.servicesId,
      }),
    ),
  );

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(config.privateKeyPem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(`${header}.${payload}`),
  );
  // Web Crypto ECDSA output is already raw r‖s — exactly JOSE format.
  return `${header}.${payload}.${b64urlEncode(new Uint8Array(signature))}`;
}

/** Exchange the sign-in `authorizationCode` for a refresh token. */
export async function exchangeAuthorizationCode(
  code: string,
  config: SiwaConfig,
  opts: CallOpts = {},
): Promise<{ refreshToken: string }> {
  const body = new URLSearchParams({
    client_id: config.servicesId,
    client_secret: await mintClientSecret(config, opts.now),
    grant_type: "authorization_code",
    code,
  });
  const res = await (opts.fetchImpl ?? fetch)(APPLE_TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body,
  });
  const json = (await res.json()) as { refresh_token?: string; error?: string; error_description?: string };
  if (!res.ok || json.refresh_token === undefined) {
    throw new AppleOAuthError(
      `Apple token exchange failed (${res.status}): ${json.error ?? "no refresh_token"}${
        json.error_description ? ` — ${json.error_description}` : ""
      }`,
    );
  }
  return { refreshToken: json.refresh_token };
}

/** Revoke a refresh token (account deletion). Resolves on success; throws on a
 * non-2xx so the caller can log it. */
export async function revokeToken(refreshToken: string, config: SiwaConfig, opts: CallOpts = {}): Promise<void> {
  const body = new URLSearchParams({
    client_id: config.servicesId,
    client_secret: await mintClientSecret(config, opts.now),
    token: refreshToken,
    token_type_hint: "refresh_token",
  });
  const res = await (opts.fetchImpl ?? fetch)(APPLE_REVOKE_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body,
  });
  if (!res.ok) {
    throw new AppleOAuthError(`Apple token revocation failed (${res.status}).`);
  }
}

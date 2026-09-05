// APNs (Apple Push Notification service) dispatch (`FEATURE_BACKLOG.md`
// "Push notifications"). The provider authentication token is an ES256 JWT
// signed with the team's `.p8` "APNs Auth Key" — same construction as
// `apple-oauth.ts`'s SIWA client-secret JWT. Hand-rolled with Web Crypto, no
// library.

import { b64urlEncode } from "./base64url.ts";
import { pemToDer } from "./pem.ts";

const APNS_PRODUCTION_HOST = "https://api.push.apple.com";
const APNS_SANDBOX_HOST = "https://api.sandbox.push.apple.com";

/** The Apple Developer portal secrets an owner must generate — none of this
 * can be built or faked from here (`NEXT_STEPS.md` Phase 6). */
export interface ApnsConfig {
  /** The 10-char id of the APNs Auth Key. */
  keyId: string;
  teamId: string;
  /** The `.p8` file contents (PKCS#8 PEM, `-----BEGIN PRIVATE KEY-----` …). */
  privateKeyPem: string;
  /** The app's bundle id — required as `apns-topic` on every push. */
  topic: string;
  /** A Xcode debug build's device token is only ever valid against the
   * sandbox APNs host; a TestFlight/App Store build's only against
   * production. Sending to the wrong host silently fails every push. */
  environment: "production" | "sandbox";
}

export function apnsConfigFromEnv(env: {
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_PRIVATE_KEY?: string;
  APNS_TOPIC?: string;
  APNS_ENVIRONMENT?: string;
}): ApnsConfig | null {
  const { APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY, APNS_TOPIC, APNS_ENVIRONMENT } = env;
  if (!APNS_KEY_ID || !APNS_TEAM_ID || !APNS_PRIVATE_KEY || !APNS_TOPIC) return null;
  return {
    keyId: APNS_KEY_ID,
    teamId: APNS_TEAM_ID,
    privateKeyPem: APNS_PRIVATE_KEY,
    topic: APNS_TOPIC,
    environment: APNS_ENVIRONMENT === "sandbox" ? "sandbox" : "production",
  };
}

// Provider tokens are valid up to an hour; Apple asks providers not to mint a
// fresh one on every request. Cached per `keyId` for the isolate's lifetime
// (module-level state survives across requests within one Worker instance),
// refreshed after 30 minutes.
const tokenCache = new Map<string, { token: string; mintedAt: number }>();
const TOKEN_TTL_MS = 30 * 60 * 1000;

async function providerToken(config: ApnsConfig, now: number): Promise<string> {
  const cached = tokenCache.get(config.keyId);
  if (cached && now - cached.mintedAt < TOKEN_TTL_MS) return cached.token;

  const iat = Math.floor(now / 1000);
  const header = b64urlEncode(new TextEncoder().encode(JSON.stringify({ alg: "ES256", kid: config.keyId })));
  const payload = b64urlEncode(new TextEncoder().encode(JSON.stringify({ iss: config.teamId, iat })));
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
  const token = `${header}.${payload}.${b64urlEncode(new Uint8Array(signature))}`;
  tokenCache.set(config.keyId, { token, mintedAt: now });
  return token;
}

/** `"sent"`: delivered to APNs (which queues it to the device; APNs never
 * confirms actual on-device delivery). `"unregistered"`: APNs says this
 * token is dead (app uninstalled, or the OS rotated it) — the caller should
 * forget it. `"failed"`: anything else — log and move on. A push failure
 * must never fail the mutation it's about, so this never throws. */
export type ApnsOutcome = "sent" | "unregistered" | "failed";

export interface PushPayload {
  title: string;
  body: string;
  /** Extra top-level keys merged alongside `aps` — a deep link target, e.g.
   * `{ groupId: "…" }`, read by the App's notification-tap handler. */
  data?: Record<string, string>;
}

interface SendOpts {
  fetchImpl?: typeof fetch;
  now?: number;
}

/** Send one alert push to one device token. Best-effort: never throws. */
export async function sendPush(
  config: ApnsConfig,
  deviceToken: string,
  payload: PushPayload,
  opts: SendOpts = {},
): Promise<ApnsOutcome> {
  const now = opts.now ?? Date.now();
  const fetchImpl = opts.fetchImpl ?? fetch;
  const host = config.environment === "sandbox" ? APNS_SANDBOX_HOST : APNS_PRODUCTION_HOST;

  try {
    const token = await providerToken(config, now);
    const res = await fetchImpl(`${host}/3/device/${deviceToken}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${token}`,
        "apns-topic": config.topic,
        "apns-push-type": "alert",
        "apns-priority": "10",
      },
      body: JSON.stringify({
        aps: { alert: { title: payload.title, body: payload.body }, sound: "default" },
        ...payload.data,
      }),
    });

    if (res.ok) return "sent";
    if (res.status === 400 || res.status === 410) {
      const body = (await res.json().catch(() => ({}))) as { reason?: string };
      if (body.reason === "BadDeviceToken" || body.reason === "Unregistered") return "unregistered";
    }
    console.error(`APNs push failed (${res.status}): ${await res.text().catch(() => "")}`);
    return "failed";
  } catch (err) {
    console.error("APNs push threw:", err);
    return "failed";
  }
}

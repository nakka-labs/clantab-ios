import { describe, expect, it } from "vitest";
import {
  AppleOAuthError,
  exchangeAuthorizationCode,
  mintClientSecret,
  revokeToken,
  siwaConfigFromEnv,
  type SiwaConfig,
} from "../src/lib/apple-oauth.ts";

function b64urlToBytes(s: string): Uint8Array {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(s.length / 4) * 4, "=");
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function b64urlToJson<T>(s: string): T {
  return JSON.parse(new TextDecoder().decode(b64urlToBytes(s))) as T;
}

/** A real P-256 keypair; the private half exported as a `.p8`-style PEM. */
async function fakeKey(): Promise<{ config: SiwaConfig; publicKey: CryptoKey }> {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
    "sign",
    "verify",
  ])) as CryptoKeyPair;
  const pkcs8 = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  let bin = "";
  for (const b of pkcs8) bin += String.fromCharCode(b);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(bin).replace(/(.{64})/g, "$1\n")}\n-----END PRIVATE KEY-----`;
  return {
    config: { servicesId: "com.clantab.app.signin", teamId: "TEAM123456", keyId: "KEYID98765", privateKeyPem: pem },
    publicKey: pair.publicKey,
  };
}

describe("siwaConfigFromEnv", () => {
  it("returns null unless all four vars are present", () => {
    expect(siwaConfigFromEnv({})).toBeNull();
    expect(siwaConfigFromEnv({ SIWA_SERVICES_ID: "a", SIWA_TEAM_ID: "b", SIWA_KEY_ID: "c" })).toBeNull();
    expect(
      siwaConfigFromEnv({ SIWA_SERVICES_ID: "a", SIWA_TEAM_ID: "b", SIWA_KEY_ID: "c", SIWA_PRIVATE_KEY: "d" }),
    ).toEqual({ servicesId: "a", teamId: "b", keyId: "c", privateKeyPem: "d" });
  });
});

describe("mintClientSecret", () => {
  it("is an ES256 JWT with the right claims and a valid signature", async () => {
    const { config, publicKey } = await fakeKey();
    const now = Date.UTC(2026, 0, 1);
    const jwt = await mintClientSecret(config, now);

    const [h, p, s] = jwt.split(".") as [string, string, string];
    expect(b64urlToJson<{ alg: string; kid: string }>(h)).toEqual({ alg: "ES256", kid: "KEYID98765" });
    const payload = b64urlToJson<{ iss: string; sub: string; aud: string; iat: number; exp: number }>(p);
    expect(payload).toMatchObject({
      iss: "TEAM123456",
      sub: "com.clantab.app.signin",
      aud: "https://appleid.apple.com",
      iat: now / 1000,
    });
    expect(payload.exp).toBe(now / 1000 + 600);

    const ok = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      publicKey,
      b64urlToBytes(s),
      new TextEncoder().encode(`${h}.${p}`),
    );
    expect(ok).toBe(true);
  });
});

describe("exchangeAuthorizationCode", () => {
  it("POSTs the code + client_secret and returns the refresh token", async () => {
    const { config } = await fakeKey();
    let seen: { url: string; body: URLSearchParams } | undefined;
    const fetchImpl = (async (url: string, init: RequestInit) => {
      seen = { url: String(url), body: init.body as URLSearchParams };
      return new Response(JSON.stringify({ refresh_token: "rt-abc", access_token: "at" }), { status: 200 });
    }) as unknown as typeof fetch;

    const result = await exchangeAuthorizationCode("code-123", config, { fetchImpl });

    expect(result).toEqual({ refreshToken: "rt-abc" });
    expect(seen?.url).toBe("https://appleid.apple.com/auth/token");
    expect(seen?.body.get("grant_type")).toBe("authorization_code");
    expect(seen?.body.get("code")).toBe("code-123");
    expect(seen?.body.get("client_id")).toBe("com.clantab.app.signin");
    expect(seen?.body.get("client_secret")).toMatch(/^[\w-]+\.[\w-]+\.[\w-]+$/);
  });

  it("throws AppleOAuthError on an error response", async () => {
    const { config } = await fakeKey();
    const fetchImpl = (async () =>
      new Response(JSON.stringify({ error: "invalid_grant" }), { status: 400 })) as unknown as typeof fetch;

    await expect(exchangeAuthorizationCode("bad", config, { fetchImpl })).rejects.toBeInstanceOf(AppleOAuthError);
  });

  it("throws when 200 but no refresh_token", async () => {
    const { config } = await fakeKey();
    const fetchImpl = (async () =>
      new Response(JSON.stringify({ access_token: "at" }), { status: 200 })) as unknown as typeof fetch;
    await expect(exchangeAuthorizationCode("x", config, { fetchImpl })).rejects.toThrow(/refresh_token/);
  });
});

describe("revokeToken", () => {
  it("POSTs the token with token_type_hint=refresh_token", async () => {
    const { config } = await fakeKey();
    let body: URLSearchParams | undefined;
    const fetchImpl = (async (url: string, init: RequestInit) => {
      body = init.body as URLSearchParams;
      return new Response(null, { status: 200 });
    }) as unknown as typeof fetch;

    await revokeToken("rt-abc", config, { fetchImpl });

    expect(body?.get("token")).toBe("rt-abc");
    expect(body?.get("token_type_hint")).toBe("refresh_token");
    expect(body?.get("client_id")).toBe("com.clantab.app.signin");
  });

  it("throws on a non-2xx", async () => {
    const { config } = await fakeKey();
    const fetchImpl = (async () => new Response(null, { status: 400 })) as unknown as typeof fetch;
    await expect(revokeToken("rt", config, { fetchImpl })).rejects.toBeInstanceOf(AppleOAuthError);
  });
});

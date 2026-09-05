import { describe, expect, it } from "vitest";
import { apnsConfigFromEnv, sendPush, type ApnsConfig } from "../src/lib/apns.ts";

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
async function fakeKey(overrides: Partial<ApnsConfig> = {}): Promise<{ config: ApnsConfig; publicKey: CryptoKey }> {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
    "sign",
    "verify",
  ])) as CryptoKeyPair;
  const pkcs8 = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  let bin = "";
  for (const b of pkcs8) bin += String.fromCharCode(b);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(bin).replace(/(.{64})/g, "$1\n")}\n-----END PRIVATE KEY-----`;
  return {
    config: {
      keyId: "APNSKEY123",
      teamId: "TEAM123456",
      privateKeyPem: pem,
      topic: "com.clantab.app",
      environment: "sandbox",
      ...overrides,
    },
    publicKey: pair.publicKey,
  };
}

describe("apnsConfigFromEnv", () => {
  it("returns null unless the required vars are all present", () => {
    expect(apnsConfigFromEnv({})).toBeNull();
    expect(apnsConfigFromEnv({ APNS_KEY_ID: "a", APNS_TEAM_ID: "b", APNS_PRIVATE_KEY: "c" })).toBeNull();
  });

  it("defaults to production unless APNS_ENVIRONMENT is exactly 'sandbox'", () => {
    const base = { APNS_KEY_ID: "a", APNS_TEAM_ID: "b", APNS_PRIVATE_KEY: "c", APNS_TOPIC: "com.clantab.app" };
    expect(apnsConfigFromEnv(base)?.environment).toBe("production");
    expect(apnsConfigFromEnv({ ...base, APNS_ENVIRONMENT: "sandbox" })?.environment).toBe("sandbox");
    expect(apnsConfigFromEnv({ ...base, APNS_ENVIRONMENT: "typo" })?.environment).toBe("production");
  });
});

describe("sendPush", () => {
  it("POSTs a correctly-shaped alert to the sandbox host with a valid ES256 provider token", async () => {
    const { config, publicKey } = await fakeKey();
    let seen: { url: string; headers: Headers; body: string } | undefined;
    const fetchImpl = (async (url: string, init: RequestInit) => {
      seen = { url: String(url), headers: new Headers(init.headers), body: init.body as string };
      return new Response(null, { status: 200 });
    }) as unknown as typeof fetch;

    const now = Date.UTC(2026, 0, 1);
    const outcome = await sendPush(
      config,
      "deadbeef",
      { title: "Priya added ₹500", body: "Dinner at Toit", data: { groupId: "g1" } },
      { fetchImpl, now },
    );

    expect(outcome).toBe("sent");
    expect(seen?.url).toBe("https://api.sandbox.push.apple.com/3/device/deadbeef");
    expect(seen?.headers.get("apns-topic")).toBe("com.clantab.app");
    expect(seen?.headers.get("apns-push-type")).toBe("alert");
    expect(seen?.headers.get("apns-priority")).toBe("10");
    expect(JSON.parse(seen!.body)).toEqual({
      aps: { alert: { title: "Priya added ₹500", body: "Dinner at Toit" }, sound: "default" },
      groupId: "g1",
    });

    const auth = seen?.headers.get("authorization") ?? "";
    expect(auth.startsWith("bearer ")).toBe(true);
    const [h, p, s] = auth.slice("bearer ".length).split(".") as [string, string, string];
    expect(b64urlToJson<{ alg: string; kid: string }>(h)).toEqual({ alg: "ES256", kid: "APNSKEY123" });
    expect(b64urlToJson<{ iss: string; iat: number }>(p)).toEqual({ iss: "TEAM123456", iat: now / 1000 });
    const ok = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      publicKey,
      b64urlToBytes(s),
      new TextEncoder().encode(`${h}.${p}`),
    );
    expect(ok).toBe(true);
  });

  it("hits the production host when environment is 'production'", async () => {
    const { config } = await fakeKey({ environment: "production" });
    let seenUrl: string | undefined;
    const fetchImpl = (async (url: string) => {
      seenUrl = String(url);
      return new Response(null, { status: 200 });
    }) as unknown as typeof fetch;

    await sendPush(config, "tok", { title: "t", body: "b" }, { fetchImpl });
    expect(seenUrl).toBe("https://api.push.apple.com/3/device/tok");
  });

  it("reuses the provider token within the cache window instead of re-signing", async () => {
    const { config } = await fakeKey();
    const seenAuth: string[] = [];
    const fetchImpl = (async (_url: string, init: RequestInit) => {
      seenAuth.push(new Headers(init.headers).get("authorization") ?? "");
      return new Response(null, { status: 200 });
    }) as unknown as typeof fetch;

    const now = Date.UTC(2026, 0, 1);
    await sendPush(config, "tok1", { title: "t", body: "b" }, { fetchImpl, now });
    await sendPush(config, "tok2", { title: "t", body: "b" }, { fetchImpl, now: now + 60_000 });

    expect(seenAuth[0]).toBe(seenAuth[1]);
  });

  it("reports 'unregistered' on a 410 BadDeviceToken/Unregistered response", async () => {
    const { config } = await fakeKey();
    const fetchImpl = (async () =>
      new Response(JSON.stringify({ reason: "Unregistered" }), { status: 410 })) as unknown as typeof fetch;

    const outcome = await sendPush(config, "stale-token", { title: "t", body: "b" }, { fetchImpl });
    expect(outcome).toBe("unregistered");
  });

  it("reports 'unregistered' on a 400 BadDeviceToken response", async () => {
    const { config } = await fakeKey();
    const fetchImpl = (async () =>
      new Response(JSON.stringify({ reason: "BadDeviceToken" }), { status: 400 })) as unknown as typeof fetch;

    const outcome = await sendPush(config, "bad-token", { title: "t", body: "b" }, { fetchImpl });
    expect(outcome).toBe("unregistered");
  });

  it("reports 'failed' (never throws) on other error statuses or a network error", async () => {
    const { config } = await fakeKey();

    const serverError = (async () =>
      new Response(JSON.stringify({ reason: "InternalServerError" }), { status: 500 })) as unknown as typeof fetch;
    expect(await sendPush(config, "tok", { title: "t", body: "b" }, { fetchImpl: serverError })).toBe("failed");

    const networkError = (async () => {
      throw new Error("network down");
    }) as unknown as typeof fetch;
    expect(await sendPush(config, "tok", { title: "t", body: "b" }, { fetchImpl: networkError })).toBe("failed");
  });
});

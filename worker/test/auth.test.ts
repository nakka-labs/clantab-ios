import { describe, expect, it } from "vitest";
import {
  type AppleJwk,
  AppleAuthError,
  __resetJwksCache,
  verifyAppleIdentityToken,
} from "../src/lib/apple-auth.ts";
import { SessionError, mintSession, verifySession } from "../src/lib/session.ts";

// --- helpers -----------------------------------------------------------

function b64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function b64urlJson(value: unknown): string {
  return b64url(new TextEncoder().encode(JSON.stringify(value)));
}

const AUDIENCE = "com.clantab.app";

interface FakeApple {
  jwk: AppleJwk;
  fetchJwks: () => Promise<AppleJwk[]>;
  sign: (payload: Record<string, unknown>, overrides?: { kid?: string; alg?: string }) => Promise<string>;
}

async function fakeApple(kid = "test-key-1"): Promise<FakeApple> {
  const pair = (await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  )) as CryptoKeyPair;
  const exported = (await crypto.subtle.exportKey("jwk", pair.publicKey)) as JsonWebKey;
  const pubJwk: AppleJwk = {
    kty: exported.kty!,
    n: exported.n!,
    e: exported.e!,
    kid,
    alg: "RS256",
    use: "sig",
  };

  const sign: FakeApple["sign"] = async (payload, overrides = {}) => {
    const header = b64urlJson({ alg: overrides.alg ?? "RS256", kid: overrides.kid ?? kid });
    const body = b64urlJson(payload);
    const sig = await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      pair.privateKey,
      new TextEncoder().encode(`${header}.${body}`),
    );
    return `${header}.${body}.${b64url(new Uint8Array(sig))}`;
  };

  return { jwk: pubJwk, fetchJwks: () => Promise.resolve([pubJwk]), sign };
}

function claims(over: Partial<Record<string, unknown>> = {}): Record<string, unknown> {
  const now = Math.floor(Date.now() / 1000);
  return {
    iss: "https://appleid.apple.com",
    aud: AUDIENCE,
    sub: "000123.abc.0001",
    iat: now,
    exp: now + 600,
    ...over,
  };
}

// --- Apple identity token --------------------------------------------

describe("verifyAppleIdentityToken", () => {
  it("accepts a well-formed token and returns the subject", async () => {
    const apple = await fakeApple();
    const token = await apple.sign(claims());
    const result = await verifyAppleIdentityToken(token, {
      audience: AUDIENCE,
      fetchJwks: apple.fetchJwks,
    });
    expect(result).toEqual({ sub: "000123.abc.0001" });
  });

  it("passes through email when Apple included it (first sign-in)", async () => {
    const apple = await fakeApple();
    const token = await apple.sign(claims({ email: "x@privaterelay.appleid.com" }));
    const result = await verifyAppleIdentityToken(token, {
      audience: AUDIENCE,
      fetchJwks: apple.fetchJwks,
    });
    expect(result.email).toBe("x@privaterelay.appleid.com");
  });

  it("rejects a tampered payload (signature fails)", async () => {
    const apple = await fakeApple();
    const token = await apple.sign(claims());
    const [h, , s] = token.split(".");
    const forged = `${h}.${b64urlJson(claims({ sub: "999999.evil.9999" }))}.${s}`;
    await expect(
      verifyAppleIdentityToken(forged, { audience: AUDIENCE, fetchJwks: apple.fetchJwks }),
    ).rejects.toBeInstanceOf(AppleAuthError);
  });

  it("rejects the wrong audience", async () => {
    const apple = await fakeApple();
    const token = await apple.sign(claims({ aud: "com.someone.else" }));
    await expect(
      verifyAppleIdentityToken(token, { audience: AUDIENCE, fetchJwks: apple.fetchJwks }),
    ).rejects.toThrow(/audience/i);
  });

  it("rejects the wrong issuer", async () => {
    const apple = await fakeApple();
    const token = await apple.sign(claims({ iss: "https://evil.example" }));
    await expect(
      verifyAppleIdentityToken(token, { audience: AUDIENCE, fetchJwks: apple.fetchJwks }),
    ).rejects.toThrow(/issuer/i);
  });

  it("rejects an expired token", async () => {
    const apple = await fakeApple();
    const token = await apple.sign(claims({ exp: Math.floor(Date.now() / 1000) - 60 }));
    await expect(
      verifyAppleIdentityToken(token, { audience: AUDIENCE, fetchJwks: apple.fetchJwks }),
    ).rejects.toThrow(/expired/i);
  });

  it("rejects a non-RS256 algorithm", async () => {
    const apple = await fakeApple();
    const token = await apple.sign(claims(), { alg: "none" });
    await expect(
      verifyAppleIdentityToken(token, { audience: AUDIENCE, fetchJwks: apple.fetchJwks }),
    ).rejects.toThrow(/algorithm/i);
  });

  it("refetches once on a kid miss, then gives up", async () => {
    const apple = await fakeApple("rotated-key");
    const token = await apple.sign(claims(), { kid: "old-key" });
    let calls = 0;
    const fetchJwks = () => {
      calls++;
      return Promise.resolve([apple.jwk]); // never contains "old-key"
    };
    await expect(
      verifyAppleIdentityToken(token, { audience: AUDIENCE, fetchJwks }),
    ).rejects.toThrow(/kid/i);
    expect(calls).toBe(2); // initial + one forced refetch
  });

  it("rejects a structurally malformed token", async () => {
    __resetJwksCache();
    await expect(
      verifyAppleIdentityToken("not-a-jwt", { audience: AUDIENCE, fetchJwks: (await fakeApple()).fetchJwks }),
    ).rejects.toThrow(/malformed/i);
  });
});

// --- session tokens --------------------------------------------------

describe("session tokens", () => {
  const KEY = "test-signing-key";

  it("round-trips sub through mint → verify", async () => {
    const { token, expiresAt } = await mintSession("000123.abc.0001", KEY);
    expect(new Date(expiresAt).getTime()).toBeGreaterThan(Date.now());
    expect(await verifySession(token, KEY)).toEqual({ sub: "000123.abc.0001" });
  });

  it("expires ~30 days out", async () => {
    const t0 = Date.UTC(2026, 0, 1);
    const { expiresAt } = await mintSession("s", KEY, t0);
    expect(new Date(expiresAt).getTime()).toBe(t0 + 30 * 24 * 60 * 60 * 1000);
  });

  it("rejects a token signed with a different key", async () => {
    const { token } = await mintSession("s", KEY);
    await expect(verifySession(token, "other-key")).rejects.toBeInstanceOf(SessionError);
  });

  it("rejects a tampered payload", async () => {
    const { token } = await mintSession("s", KEY);
    const [h, , sig] = token.split(".");
    const forged = `${h}.${b64urlJson({ sub: "admin", iat: 0, exp: 9_999_999_999 })}.${sig}`;
    await expect(verifySession(forged, KEY)).rejects.toBeInstanceOf(SessionError);
  });

  it("rejects an expired session", async () => {
    const t0 = Date.UTC(2026, 0, 1);
    const { token } = await mintSession("s", KEY, t0);
    const later = t0 + 31 * 24 * 60 * 60 * 1000;
    await expect(verifySession(token, KEY, later)).rejects.toThrow(/expired/i);
  });

  it("rejects a structurally malformed token", async () => {
    await expect(verifySession("a.b", KEY)).rejects.toThrow(/malformed/i);
  });
});

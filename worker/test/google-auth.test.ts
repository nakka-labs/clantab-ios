import { describe, expect, it } from "vitest";
import {
  type GoogleJwk,
  GoogleAuthError,
  __resetJwksCache,
  verifyGoogleIdentityToken,
} from "../src/lib/google-auth.ts";

// --- helpers -----------------------------------------------------------
// Mirrors worker/test/auth.test.ts's fakeApple() — same RS256/JWKS shape,
// different issuer.

function b64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function b64urlJson(value: unknown): string {
  return b64url(new TextEncoder().encode(JSON.stringify(value)));
}

const AUDIENCE = "785063933196-ieaukpoat5r6v5jjr65315o9rniaaahn.apps.googleusercontent.com";

interface FakeGoogle {
  jwk: GoogleJwk;
  fetchJwks: () => Promise<GoogleJwk[]>;
  sign: (payload: Record<string, unknown>, overrides?: { kid?: string; alg?: string }) => Promise<string>;
}

async function fakeGoogle(kid = "test-key-1"): Promise<FakeGoogle> {
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
  const pubJwk: GoogleJwk = {
    kty: exported.kty!,
    n: exported.n!,
    e: exported.e!,
    kid,
    alg: "RS256",
    use: "sig",
  };

  const sign: FakeGoogle["sign"] = async (payload, overrides = {}) => {
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
    iss: "https://accounts.google.com",
    aud: AUDIENCE,
    sub: "109876543210987654321",
    iat: now,
    exp: now + 600,
    ...over,
  };
}

describe("verifyGoogleIdentityToken", () => {
  it("accepts a well-formed token and returns the subject", async () => {
    const google = await fakeGoogle();
    const token = await google.sign(claims());
    const result = await verifyGoogleIdentityToken(token, {
      audience: AUDIENCE,
      fetchJwks: google.fetchJwks,
    });
    expect(result).toEqual({ sub: "109876543210987654321" });
  });

  it("accepts the bare-host issuer form too", async () => {
    const google = await fakeGoogle();
    const token = await google.sign(claims({ iss: "accounts.google.com" }));
    const result = await verifyGoogleIdentityToken(token, {
      audience: AUDIENCE,
      fetchJwks: google.fetchJwks,
    });
    expect(result.sub).toBe("109876543210987654321");
  });

  it("passes through email when the email scope was granted", async () => {
    const google = await fakeGoogle();
    const token = await google.sign(claims({ email: "x@example.com" }));
    const result = await verifyGoogleIdentityToken(token, {
      audience: AUDIENCE,
      fetchJwks: google.fetchJwks,
    });
    expect(result.email).toBe("x@example.com");
  });

  it("rejects a tampered payload (signature fails)", async () => {
    const google = await fakeGoogle();
    const token = await google.sign(claims());
    const [h, , s] = token.split(".");
    const forged = `${h}.${b64urlJson(claims({ sub: "999999999999999999999" }))}.${s}`;
    await expect(
      verifyGoogleIdentityToken(forged, { audience: AUDIENCE, fetchJwks: google.fetchJwks }),
    ).rejects.toBeInstanceOf(GoogleAuthError);
  });

  it("rejects the wrong audience", async () => {
    const google = await fakeGoogle();
    const token = await google.sign(claims({ aud: "some-other-client-id.apps.googleusercontent.com" }));
    await expect(
      verifyGoogleIdentityToken(token, { audience: AUDIENCE, fetchJwks: google.fetchJwks }),
    ).rejects.toThrow(/audience/i);
  });

  it("rejects the wrong issuer", async () => {
    const google = await fakeGoogle();
    const token = await google.sign(claims({ iss: "https://evil.example" }));
    await expect(
      verifyGoogleIdentityToken(token, { audience: AUDIENCE, fetchJwks: google.fetchJwks }),
    ).rejects.toThrow(/issuer/i);
  });

  it("rejects an expired token", async () => {
    const google = await fakeGoogle();
    const token = await google.sign(claims({ exp: Math.floor(Date.now() / 1000) - 60 }));
    await expect(
      verifyGoogleIdentityToken(token, { audience: AUDIENCE, fetchJwks: google.fetchJwks }),
    ).rejects.toThrow(/expired/i);
  });

  it("rejects a non-RS256 algorithm", async () => {
    const google = await fakeGoogle();
    const token = await google.sign(claims(), { alg: "none" });
    await expect(
      verifyGoogleIdentityToken(token, { audience: AUDIENCE, fetchJwks: google.fetchJwks }),
    ).rejects.toThrow(/algorithm/i);
  });

  it("refetches once on a kid miss, then gives up", async () => {
    const google = await fakeGoogle("rotated-key");
    const token = await google.sign(claims(), { kid: "old-key" });
    let calls = 0;
    const fetchJwks = () => {
      calls++;
      return Promise.resolve([google.jwk]); // never contains "old-key"
    };
    await expect(
      verifyGoogleIdentityToken(token, { audience: AUDIENCE, fetchJwks }),
    ).rejects.toThrow(/kid/i);
    expect(calls).toBe(2); // initial + one forced refetch
  });

  it("rejects a structurally malformed token", async () => {
    __resetJwksCache();
    await expect(
      verifyGoogleIdentityToken("not-a-jwt", { audience: AUDIENCE, fetchJwks: (await fakeGoogle()).fetchJwks }),
    ).rejects.toThrow(/malformed/i);
  });
});

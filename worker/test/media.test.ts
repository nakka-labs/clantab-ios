import { SELF, env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { mintSession } from "../src/lib/session.ts";
import { presignS3Url } from "../src/lib/s3-presign.ts";
import { avatarKey, groupCoverKey, groupIdForKey, receiptKey } from "../src/lib/media.ts";

const BASE = "https://api.test";

interface Json {
  [k: string]: unknown;
}

function bearer(sub: string): Promise<string> {
  return mintSession(sub, env.SESSION_SIGNING_KEY).then((r) => r.token);
}

async function call(
  method: string,
  path: string,
  opts: { bearer?: string; body?: unknown; token?: string } = {},
): Promise<{ status: number; json: Json }> {
  const headers: Record<string, string> = {};
  if (opts.bearer !== undefined) headers.Authorization = `Bearer ${opts.bearer}`;
  const url =
    opts.token === undefined ? `${BASE}${path}` : `${BASE}${path}${path.includes("?") ? "&" : "?"}token=${opts.token}`;
  const res = await SELF.fetch(url, {
    method,
    headers,
    body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
  });
  return { status: res.status, json: res.status === 204 ? {} : ((await res.json()) as Json) };
}

/** A group with one claimed member (`sub`) and its access token. */
async function groupWithClaimedMember(sub: string): Promise<{ groupId: string; token: string; memberId: string }> {
  const created = await call("POST", "/api/groups", {
    body: { name: "Goa Trip", currency: "INR", creatorDisplayName: "Indra" },
  });
  const groupId = created.json.groupId as string;
  const token = (created.json.group as Json).accessToken as string;
  const memberId = (created.json.member as Json).id as string;
  const b = await bearer(sub);
  const claim = await call("POST", `/api/groups/${groupId}/members/${memberId}/claim`, { bearer: b, token });
  expect(claim.status).toBe(200);
  return { groupId, token, memberId };
}

const JPEG = "image/jpeg";
const ONE_MB = 1024 * 1024;

// --- SigV4 signer: AWS's own documented example -----------------------------
// "Signature Version 4 — Query String Request Authentication" (AWS General
// Reference): GET examplebucket/test.txt, us-east-1, 2013-05-24, expires 86400.
describe("presignS3Url — AWS reference vector", () => {
  it("reproduces AWS's documented presigned GET signature", async () => {
    const url = await presignS3Url({
      accessKeyId: "AKIAIOSFODNN7EXAMPLE",
      secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
      region: "us-east-1",
      host: "examplebucket.s3.amazonaws.com",
      method: "GET",
      path: "/test.txt",
      expiresSeconds: 86400,
      now: Date.parse("2013-05-24T00:00:00Z"),
    });
    const params = new URL(url).searchParams;
    expect(params.get("X-Amz-Signature")).toBe(
      "aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404",
    );
    expect(params.get("X-Amz-Credential")).toBe(
      "AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request",
    );
    expect(params.get("X-Amz-SignedHeaders")).toBe("host");
  });

  it("signs content-* headers into a PUT and is deterministic for a fixed instant", async () => {
    const args = {
      accessKeyId: "AKIAIOSFODNN7EXAMPLE",
      secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
      region: "auto" as const,
      host: "acc.r2.cloudflarestorage.com",
      method: "PUT" as const,
      path: "/clantab-media/avatars/deadbeef",
      signedHeaders: { "content-type": "image/png", "content-length": "1234" },
      expiresSeconds: 300,
      now: 1_700_000_000_000,
    };
    const a = await presignS3Url(args);
    const b = await presignS3Url(args);
    expect(a).toBe(b);
    expect(new URL(a).searchParams.get("X-Amz-SignedHeaders")).toBe("content-length;content-type;host");
  });
});

// --- key derivation --------------------------------------------------------
describe("media key derivation", () => {
  it("avatar key is a stable 32-hex path under avatars/", async () => {
    const k = await avatarKey("apple:000123.abc");
    expect(k).toMatch(/^avatars\/[0-9a-f]{32}$/);
    expect(await avatarKey("apple:000123.abc")).toBe(k);
    expect(await avatarKey("google:999")).not.toBe(k);
  });

  it("groupIdForKey recovers the group for scoped keys and null for avatars", async () => {
    expect(groupIdForKey(groupCoverKey("G123"))).toBe("G123");
    expect(groupIdForKey(receiptKey("G123", "E456", "R789"))).toBe("G123");
    expect(groupIdForKey(await avatarKey("apple:x"))).toBeNull();
  });

  it("groupIdForKey rejects an unrecognized key", () => {
    expect(() => groupIdForKey("../../etc/passwd")).toThrow();
  });
});

// --- POST /api/media/presign ---------------------------------------------
describe("POST /api/media/presign", () => {
  it("401s without a session", async () => {
    const { status } = await call("POST", "/api/media/presign", {
      body: { operation: "upload", purpose: "avatar", contentType: JPEG, contentLength: ONE_MB },
    });
    expect(status).toBe(401);
  });

  it("presigns an avatar upload for any signed-in identity", async () => {
    const b = await bearer("apple:avatar.1");
    const { status, json } = await call("POST", "/api/media/presign", {
      bearer: b,
      body: { operation: "upload", purpose: "avatar", contentType: JPEG, contentLength: ONE_MB },
    });
    expect(status).toBe(200);
    expect(json.key).toMatch(/^avatars\/[0-9a-f]{32}$/);
    expect(json.method).toBe("PUT");
    expect((json.headers as Json)["Content-Type"]).toBe(JPEG);
    const u = new URL(json.url as string);
    expect(u.hostname).toBe("test-account-id.r2.cloudflarestorage.com");
    expect(u.searchParams.get("X-Amz-Signature")).toBeTruthy();
    expect(u.searchParams.get("X-Amz-Expires")).toBe("300");
  });

  it("rejects a disallowed content type", async () => {
    const b = await bearer("apple:avatar.2");
    const { status, json } = await call("POST", "/api/media/presign", {
      bearer: b,
      body: { operation: "upload", purpose: "avatar", contentType: "image/gif", contentLength: ONE_MB },
    });
    expect(status).toBe(400);
    expect((json.error as Json).code).toBe("BAD_REQUEST");
  });

  it("rejects an oversized upload with 413", async () => {
    const b = await bearer("apple:avatar.3");
    const { status, json } = await call("POST", "/api/media/presign", {
      bearer: b,
      body: { operation: "upload", purpose: "avatar", contentType: JPEG, contentLength: 6 * ONE_MB },
    });
    expect(status).toBe(413);
    expect((json.error as Json).code).toBe("PAYLOAD_TOO_LARGE");
  });

  it("presigns a group cover for a claimed member, keyed to the group", async () => {
    const sub = "apple:cover.owner";
    const { groupId } = await groupWithClaimedMember(sub);
    const { status, json } = await call("POST", "/api/media/presign", {
      bearer: await bearer(sub),
      body: { operation: "upload", purpose: "groupCover", groupId, contentType: JPEG, contentLength: ONE_MB },
    });
    expect(status).toBe(200);
    expect(json.key).toBe(`groups/${groupId}/cover`);
  });

  it("403s a group cover upload from a non-member", async () => {
    const { groupId } = await groupWithClaimedMember("apple:cover.owner.2");
    const { status } = await call("POST", "/api/media/presign", {
      bearer: await bearer("apple:cover.stranger"),
      body: { operation: "upload", purpose: "groupCover", groupId, contentType: JPEG, contentLength: ONE_MB },
    });
    expect(status).toBe(403);
  });

  it("404s a group cover upload for an unknown group", async () => {
    const { status } = await call("POST", "/api/media/presign", {
      bearer: await bearer("apple:cover.owner.3"),
      body: { operation: "upload", purpose: "groupCover", groupId: "nope12345", contentType: JPEG, contentLength: ONE_MB },
    });
    expect(status).toBe(404);
  });

  it("presigns a receipt upload with a per-object random key", async () => {
    const sub = "apple:receipt.owner";
    const { groupId } = await groupWithClaimedMember(sub);
    const b = await bearer(sub);
    const first = await call("POST", "/api/media/presign", {
      bearer: b,
      body: {
        operation: "upload",
        purpose: "receipt",
        groupId,
        expenseId: "E1",
        contentType: JPEG,
        contentLength: ONE_MB,
      },
    });
    const second = await call("POST", "/api/media/presign", {
      bearer: b,
      body: {
        operation: "upload",
        purpose: "receipt",
        groupId,
        expenseId: "E1",
        contentType: JPEG,
        contentLength: ONE_MB,
      },
    });
    expect(first.status).toBe(200);
    expect(first.json.key).toMatch(new RegExp(`^expenses/${groupId}/E1/[0-9A-Za-z_-]+$`));
    expect(first.json.key).not.toBe(second.json.key);
  });

  it("ignores a client-supplied key on upload — the server derives it", async () => {
    const b = await bearer("apple:key.injector");
    const { json } = await call("POST", "/api/media/presign", {
      bearer: b,
      body: {
        operation: "upload",
        purpose: "avatar",
        key: "avatars/somebody-elses",
        contentType: JPEG,
        contentLength: ONE_MB,
      },
    });
    // `key` isn't in the allowed keys for the request body → 400, never honored.
    expect((json.error as Json)?.code ?? json.key).not.toBe("avatars/somebody-elses");
  });

  it("presigns a view URL for a member and 403s a non-member", async () => {
    const sub = "apple:view.owner";
    const { groupId } = await groupWithClaimedMember(sub);
    const key = groupCoverKey(groupId);

    const ok = await call("POST", "/api/media/presign", {
      bearer: await bearer(sub),
      body: { operation: "view", key },
    });
    expect(ok.status).toBe(200);
    expect(new URL(ok.json.url as string).searchParams.get("X-Amz-Signature")).toBeTruthy();

    const denied = await call("POST", "/api/media/presign", {
      bearer: await bearer("apple:view.stranger"),
      body: { operation: "view", key },
    });
    expect(denied.status).toBe(403);
  });

  it("lets any signed-in identity view an avatar", async () => {
    const key = await avatarKey("apple:some.user");
    const { status } = await call("POST", "/api/media/presign", {
      bearer: await bearer("apple:another.user"),
      body: { operation: "view", key },
    });
    expect(status).toBe(200);
  });
});

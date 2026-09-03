import { SELF, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { mintSession, verifySession } from "../src/lib/session.ts";

const BASE = "https://api.test";

interface Json {
  [k: string]: unknown;
}

function token(sub: string): Promise<string> {
  return mintSession(sub, env.SESSION_SIGNING_KEY).then((r) => r.token);
}

async function call(
  method: string,
  path: string,
  opts: { bearer?: string; body?: unknown } = {},
): Promise<{ status: number; json: Json }> {
  const headers: Record<string, string> = {};
  if (opts.bearer !== undefined) headers.Authorization = `Bearer ${opts.bearer}`;
  const res = await SELF.fetch(`${BASE}${path}`, {
    method,
    headers,
    body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
  });
  return { status: res.status, json: res.status === 204 ? {} : ((await res.json()) as Json) };
}

async function makeGroup(): Promise<{ groupId: string; creatorId: string }> {
  const { json } = await call("POST", "/api/groups", {
    body: { name: "Goa Trip", currency: "INR", creatorDisplayName: "Indra" },
  });
  return { groupId: json.groupId as string, creatorId: (json.member as Json).id as string };
}

async function addMember(groupId: string, displayName: string): Promise<string> {
  const { json } = await call("POST", `/api/groups/${groupId}/members`, { body: { displayName } });
  return (json.member as Json).id as string;
}

describe("POST /api/auth/apple", () => {
  it("rejects an unverifiable identity token with INVALID_APPLE_TOKEN", async () => {
    const { status, json } = await call("POST", "/api/auth/apple", {
      body: { identityToken: "not.a.real-token" },
    });
    expect(status).toBe(401);
    expect((json.error as Json).code).toBe("INVALID_APPLE_TOKEN");
  });

  it("rejects a missing identityToken with 400", async () => {
    const { status } = await call("POST", "/api/auth/apple", { body: {} });
    expect(status).toBe(400);
  });
});

describe("Bearer-gated routes reject a missing / bad token", () => {
  it.each([
    ["POST", "/api/auth/refresh"],
    ["GET", "/api/auth/groups"],
    ["DELETE", "/api/auth/account"],
  ] as const)("%s %s → 401 without a token", async (method, path) => {
    const { status, json } = await call(method, path);
    expect(status).toBe(401);
    expect((json.error as Json).code).toBe("INVALID_SESSION");
  });

  it("401s a garbage bearer token", async () => {
    const { status } = await call("GET", "/api/auth/groups", { bearer: "garbage.token.here" });
    expect(status).toBe(401);
  });
});

describe("POST /api/auth/refresh", () => {
  it("returns a fresh, valid session token", async () => {
    const t = await token("000123.refresh.0001");
    const { status, json } = await call("POST", "/api/auth/refresh", { bearer: t });
    expect(status).toBe(200);
    await expect(
      verifySession(json.sessionToken as string, env.SESSION_SIGNING_KEY),
    ).resolves.toEqual({ sub: "000123.refresh.0001" });
    expect(new Date(json.expiresAt as string).getTime()).toBeGreaterThan(Date.now());
  });
});

describe("GET /api/auth/groups", () => {
  it("is empty for an identity that has claimed nothing", async () => {
    const { status, json } = await call("GET", "/api/auth/groups", {
      bearer: await token("000123.empty.0001"),
    });
    expect(status).toBe(200);
    expect(json.groups).toEqual([]);
  });
});

describe("claim flow", () => {
  let groupId: string;
  let placeholderId: string;
  const sub = "000123.claim.0001";
  let bearer: string;

  beforeEach(async () => {
    ({ groupId } = await makeGroup());
    placeholderId = await addMember(groupId, "Priya");
    bearer = await token(sub);
  });

  it("lists placeholders, claims one, and reflects it in /api/auth/groups", async () => {
    const claimable = await call("GET", `/api/groups/${groupId}/claimable`, { bearer });
    expect(claimable.status).toBe(200);
    expect((claimable.json.members as Json[]).map((m) => m.id)).toContain(placeholderId);

    const claim = await call("POST", `/api/groups/${groupId}/members/${placeholderId}/claim`, { bearer });
    expect(claim.status).toBe(200);
    expect(claim.json.member).toMatchObject({ id: placeholderId, displayName: "Priya" });

    const groups = await call("GET", "/api/auth/groups", { bearer });
    expect(groups.json.groups).toEqual([
      { groupId, memberId: placeholderId, displayName: "Priya" },
    ]);

    // The claimed member is no longer a placeholder.
    const after = await call("GET", `/api/groups/${groupId}/claimable`, { bearer });
    expect((after.json.members as Json[]).map((m) => m.id)).not.toContain(placeholderId);
  });

  it("re-claiming the same member with the same identity is idempotent", async () => {
    await call("POST", `/api/groups/${groupId}/members/${placeholderId}/claim`, { bearer });
    const again = await call("POST", `/api/groups/${groupId}/members/${placeholderId}/claim`, { bearer });
    expect(again.status).toBe(200);
  });

  it("404s a claim on an unknown member", async () => {
    const { status, json } = await call(
      "POST",
      `/api/groups/${groupId}/members/ghost/claim`,
      { bearer },
    );
    expect(status).toBe(404);
    expect((json.error as Json).code).toBe("UNKNOWN_MEMBER");
  });

  it("409s a claim on a member another identity already holds", async () => {
    await call("POST", `/api/groups/${groupId}/members/${placeholderId}/claim`, { bearer });
    const other = await call("POST", `/api/groups/${groupId}/members/${placeholderId}/claim`, {
      bearer: await token("000123.other.0002"),
    });
    expect(other.status).toBe(409);
    expect((other.json.error as Json).code).toBe("ALREADY_CLAIMED");
  });

  it("409s when the identity already holds another membership in the group", async () => {
    const secondPlaceholder = await addMember(groupId, "Priya's phone");
    await call("POST", `/api/groups/${groupId}/members/${placeholderId}/claim`, { bearer });
    const dup = await call(
      "POST",
      `/api/groups/${groupId}/members/${secondPlaceholder}/claim`,
      { bearer },
    );
    expect(dup.status).toBe(409);
    expect((dup.json.error as Json).code).toBe("IDENTITY_ALREADY_IN_GROUP");
  });

  it("404s claimable / claim for an unknown group", async () => {
    expect((await call("GET", "/api/groups/nope12345/claimable", { bearer })).status).toBe(404);
    expect((await call("POST", "/api/groups/nope12345/members/x/claim", { bearer })).status).toBe(404);
  });
});

describe("DELETE /api/auth/account", () => {
  it("releases every claimed membership and empties the index", async () => {
    const { groupId } = await makeGroup();
    const placeholderId = await addMember(groupId, "Priya");
    const bearer = await token("000123.delete.0001");

    await call("POST", `/api/groups/${groupId}/members/${placeholderId}/claim`, { bearer });
    expect((await call("GET", "/api/auth/groups", { bearer })).json.groups).toHaveLength(1);

    const del = await call("DELETE", "/api/auth/account", { bearer });
    expect(del.status).toBe(204);

    // Index gone…
    expect((await call("GET", "/api/auth/groups", { bearer })).json.groups).toEqual([]);
    // …and the membership is a claimable placeholder again.
    const claimable = await call("GET", `/api/groups/${groupId}/claimable`, { bearer });
    expect((claimable.json.members as Json[]).map((m) => m.id)).toContain(placeholderId);
  });
});

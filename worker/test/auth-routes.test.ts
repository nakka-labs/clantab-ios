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
  opts: { bearer?: string; body?: unknown; token?: string } = {},
): Promise<{ status: number; json: Json }> {
  const headers: Record<string, string> = {};
  if (opts.bearer !== undefined) headers.Authorization = `Bearer ${opts.bearer}`;
  const url =
    opts.token === undefined
      ? `${BASE}${path}`
      : `${BASE}${path}${path.includes("?") ? "&" : "?"}token=${opts.token}`;
  const res = await SELF.fetch(url, {
    method,
    headers,
    body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
  });
  return { status: res.status, json: res.status === 204 ? {} : ((await res.json()) as Json) };
}

async function makeGroup(): Promise<{ groupId: string; creatorId: string; token: string }> {
  const { json } = await call("POST", "/api/groups", {
    body: { name: "Goa Trip", currency: "INR", creatorDisplayName: "Indra" },
  });
  return {
    groupId: json.groupId as string,
    creatorId: (json.member as Json).id as string,
    token: (json.group as Json).accessToken as string,
  };
}

async function addMember(groupId: string, displayName: string, token: string): Promise<string> {
  const { json } = await call("POST", `/api/groups/${groupId}/members`, { body: { displayName }, token });
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

describe("POST /api/auth/google", () => {
  it("rejects an unverifiable identity token with INVALID_GOOGLE_TOKEN", async () => {
    const { status, json } = await call("POST", "/api/auth/google", {
      body: { identityToken: "not.a.real-token" },
    });
    expect(status).toBe(401);
    expect((json.error as Json).code).toBe("INVALID_GOOGLE_TOKEN");
  });

  it("rejects a missing identityToken with 400", async () => {
    const { status } = await call("POST", "/api/auth/google", { body: {} });
    expect(status).toBe(400);
  });
});

describe("Bearer-gated routes reject a missing / bad token", () => {
  it.each([
    ["POST", "/api/auth/refresh"],
    ["GET", "/api/auth/groups"],
    ["DELETE", "/api/auth/account"],
    ["POST", "/api/auth/devices"],
    ["DELETE", "/api/auth/devices/sometoken"],
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

describe("POST /api/auth/devices, DELETE /api/auth/devices/:token (FEATURE_BACKLOG.md — push notifications)", () => {
  it("registers a device token, idempotently, defaulting platform to ios", async () => {
    const bearer = await token("000123.devices.0001");
    expect((await call("POST", "/api/auth/devices", { bearer, body: { token: "dev-tok-1" } })).status).toBe(204);
    // Re-registering the same token (e.g. every launch) is a safe no-op.
    expect((await call("POST", "/api/auth/devices", { bearer, body: { token: "dev-tok-1" } })).status).toBe(204);
  });

  it("rejects a missing token with 400", async () => {
    const bearer = await token("000123.devices.0002");
    const { status } = await call("POST", "/api/auth/devices", { bearer, body: {} });
    expect(status).toBe(400);
  });

  it("unregisters a device token idempotently, scoped to the caller's own identity", async () => {
    const bearer = await token("000123.devices.0003");
    await call("POST", "/api/auth/devices", { bearer, body: { token: "dev-tok-2" } });

    expect((await call("DELETE", "/api/auth/devices/dev-tok-2", { bearer })).status).toBe(204);
    expect((await call("DELETE", "/api/auth/devices/dev-tok-2", { bearer })).status).toBe(204); // already gone
  });
});

describe("claim flow", () => {
  let groupId: string;
  let groupToken: string;
  let placeholderId: string;
  const sub = "000123.claim.0001";
  let bearer: string;

  beforeEach(async () => {
    ({ groupId, token: groupToken } = await makeGroup());
    placeholderId = await addMember(groupId, "Priya", groupToken);
    bearer = await token(sub);
  });

  it("lists placeholders, claims one, and reflects it in /api/auth/groups", async () => {
    const claimable = await call("GET", `/api/groups/${groupId}/claimable`, { bearer, token: groupToken });
    expect(claimable.status).toBe(200);
    expect((claimable.json.members as Json[]).map((m) => m.id)).toContain(placeholderId);

    const claim = await call("POST", `/api/groups/${groupId}/members/${placeholderId}/claim`, {
      bearer,
      token: groupToken,
    });
    expect(claim.status).toBe(200);
    expect(claim.json.member).toMatchObject({ id: placeholderId, displayName: "Priya" });

    const groups = await call("GET", "/api/auth/groups", { bearer });
    expect(groups.json.groups).toEqual([
      { groupId, memberId: placeholderId, displayName: "Priya" },
    ]);

    // The claimed member is no longer a placeholder. Note: no `token` needed
    // here — the caller is now a claimed member, the Bearer-session
    // alternate credential in `requireGroup` (`ACCESS_TOKEN_PLAN.md`).
    const after = await call("GET", `/api/groups/${groupId}/claimable`, { bearer });
    expect((after.json.members as Json[]).map((m) => m.id)).not.toContain(placeholderId);
  });

  it("re-claiming the same member with the same identity is idempotent", async () => {
    await call("POST", `/api/groups/${groupId}/members/${placeholderId}/claim`, { bearer, token: groupToken });
    const again = await call("POST", `/api/groups/${groupId}/members/${placeholderId}/claim`, {
      bearer,
      // No token this time — already a claimed member of this group, so the
      // Bearer-session alternate credential covers it.
    });
    expect(again.status).toBe(200);
  });

  it("404s a claim on an unknown member", async () => {
    const { status, json } = await call(
      "POST",
      `/api/groups/${groupId}/members/ghost/claim`,
      { bearer, token: groupToken },
    );
    expect(status).toBe(404);
    expect((json.error as Json).code).toBe("UNKNOWN_MEMBER");
  });

  it("409s a claim on a member another identity already holds", async () => {
    await call("POST", `/api/groups/${groupId}/members/${placeholderId}/claim`, { bearer, token: groupToken });
    const other = await call("POST", `/api/groups/${groupId}/members/${placeholderId}/claim`, {
      bearer: await token("000123.other.0002"),
      token: groupToken,
    });
    expect(other.status).toBe(409);
    expect((other.json.error as Json).code).toBe("ALREADY_CLAIMED");
  });

  it("409s when the identity already holds another membership in the group", async () => {
    const secondPlaceholder = await addMember(groupId, "Priya's phone", groupToken);
    await call("POST", `/api/groups/${groupId}/members/${placeholderId}/claim`, { bearer, token: groupToken });
    const dup = await call(
      "POST",
      `/api/groups/${groupId}/members/${secondPlaceholder}/claim`,
      // No token — already claimed in this group via `placeholderId`.
      { bearer },
    );
    expect(dup.status).toBe(409);
    expect((dup.json.error as Json).code).toBe("IDENTITY_ALREADY_IN_GROUP");
  });

  it("404s claimable / claim for an unknown group", async () => {
    expect((await call("GET", "/api/groups/nope12345/claimable", { bearer })).status).toBe(404);
    expect((await call("POST", "/api/groups/nope12345/members/x/claim", { bearer })).status).toBe(404);
  });

  it("403s claimable / claim on a real group with no token from an unclaimed identity", async () => {
    expect((await call("GET", `/api/groups/${groupId}/claimable`, { bearer })).status).toBe(403);
    expect(
      (await call("POST", `/api/groups/${groupId}/members/${placeholderId}/claim`, { bearer })).status,
    ).toBe(403);
  });
});

describe("GET /api/auth/people (cross-group settling)", () => {
  const alice = "000123.people.alice";
  const bob = "000123.people.bob";
  let aliceBearer: string;
  let bobBearer: string;

  beforeEach(async () => {
    aliceBearer = await token(alice);
    bobBearer = await token(bob);
  });

  /** A group where Alice and Bob are both claimed; `debt` = what Bob ends up
   * owing Alice (via one equal-split expense Alice paid). */
  async function sharedGroup(debt: number, name = "Trip"): Promise<string> {
    const { json } = await call("POST", "/api/groups", {
      body: { name, currency: "INR", creatorDisplayName: "x" },
    });
    const groupId = json.groupId as string;
    const groupToken = (json.group as Json).accessToken as string;
    const a = await addMember(groupId, "Alice", groupToken);
    const b = await addMember(groupId, "Bob", groupToken);
    await call("POST", `/api/groups/${groupId}/members/${a}/claim`, { bearer: aliceBearer, token: groupToken });
    await call("POST", `/api/groups/${groupId}/members/${b}/claim`, { bearer: bobBearer, token: groupToken });
    await call("POST", `/api/groups/${groupId}/expenses`, {
      token: groupToken,
      body: {
        payerId: a, amountMinor: debt * 2, description: "e", date: "2026-01-01T12:00:00Z",
        splitType: "equal", splits: [{ memberId: a, amountMinor: debt }, { memberId: b, amountMinor: debt }],
      },
    });
    return groupId;
  }

  it("shows the net a linked person owes / is owed, per currency", async () => {
    await sharedGroup(500, "Goa");

    const forAlice = await call("GET", "/api/auth/people", { bearer: aliceBearer });
    expect(forAlice.status).toBe(200);
    expect(forAlice.json.people).toHaveLength(1);
    const bobEntry = (forAlice.json.people as Json[])[0]!;
    expect(bobEntry.displayName).toBe("Bob");
    expect(bobEntry.net).toEqual([{ currency: "INR", netMinor: -500 }]); // Bob owes Alice
    expect(bobEntry).not.toHaveProperty("sub");
    const grp = (bobEntry.groups as Json[])[0]!;
    expect(grp).toMatchObject({ groupName: "Goa", currency: "INR", amountMinor: 500, youPay: false });
    expect(grp.myMemberId).toBeTypeOf("string");
    expect(grp.theirMemberId).toBeTypeOf("string");

    // Bob sees the mirror image.
    const forBob = await call("GET", "/api/auth/people", { bearer: bobBearer });
    const aliceEntry = (forBob.json.people as Json[])[0]!;
    expect(aliceEntry.displayName).toBe("Alice");
    expect(aliceEntry.net).toEqual([{ currency: "INR", netMinor: 500 }]); // Bob owes → positive
    expect((aliceEntry.groups as Json[])[0]).toMatchObject({ youPay: true });
  });

  it("nets one person across multiple shared groups", async () => {
    await sharedGroup(500, "Goa");   // Bob owes Alice 500
    // second group: Bob pays, so Alice owes Bob 200
    const { json } = await call("POST", "/api/groups", {
      body: { name: "Flat", currency: "INR", creatorDisplayName: "x" },
    });
    const g2 = json.groupId as string;
    const g2Token = (json.group as Json).accessToken as string;
    const a2 = await addMember(g2, "Alice", g2Token);
    const b2 = await addMember(g2, "Bob", g2Token);
    await call("POST", `/api/groups/${g2}/members/${a2}/claim`, { bearer: aliceBearer, token: g2Token });
    await call("POST", `/api/groups/${g2}/members/${b2}/claim`, { bearer: bobBearer, token: g2Token });
    await call("POST", `/api/groups/${g2}/expenses`, {
      token: g2Token,
      body: {
        payerId: b2, amountMinor: 400, description: "e", date: "2026-01-02T12:00:00Z",
        splitType: "equal", splits: [{ memberId: a2, amountMinor: 200 }, { memberId: b2, amountMinor: 200 }],
      },
    });

    const forAlice = await call("GET", "/api/auth/people", { bearer: aliceBearer });
    const bobEntry = (forAlice.json.people as Json[])[0]!;
    expect(bobEntry.net).toEqual([{ currency: "INR", netMinor: -300 }]); // -500 + 200
    expect(bobEntry.groups).toHaveLength(2);
  });

  it("excludes guests (unclaimed members) and fully-settled pairs", async () => {
    // group with Alice claimed + a guest 'Cara' who owes her
    const { json } = await call("POST", "/api/groups", {
      body: { name: "G", currency: "INR", creatorDisplayName: "x" },
    });
    const groupId = json.groupId as string;
    const groupToken = (json.group as Json).accessToken as string;
    const a = await addMember(groupId, "Alice", groupToken);
    const cara = await addMember(groupId, "Cara", groupToken);
    await call("POST", `/api/groups/${groupId}/members/${a}/claim`, { bearer: aliceBearer, token: groupToken });
    await call("POST", `/api/groups/${groupId}/expenses`, {
      token: groupToken,
      body: {
        payerId: a, amountMinor: 200, description: "e", date: "2026-01-01T12:00:00Z",
        splitType: "equal", splits: [{ memberId: a, amountMinor: 100 }, { memberId: cara, amountMinor: 100 }],
      },
    });

    expect((await call("GET", "/api/auth/people", { bearer: aliceBearer })).json.people).toEqual([]);
  });

  it("is empty for someone with no linked co-members", async () => {
    const { groupId, token: groupToken } = await makeGroup();
    const a = await addMember(groupId, "Solo", groupToken);
    await call("POST", `/api/groups/${groupId}/members/${a}/claim`, { bearer: aliceBearer, token: groupToken });
    expect((await call("GET", "/api/auth/people", { bearer: aliceBearer })).json.people).toEqual([]);
  });

  it("401s without a session", async () => {
    expect((await call("GET", "/api/auth/people")).status).toBe(401);
  });
});

describe("DELETE /api/auth/account", () => {
  it("releases every claimed membership and empties the index", async () => {
    const { groupId, token: groupToken } = await makeGroup();
    const placeholderId = await addMember(groupId, "Priya", groupToken);
    const bearer = await token("000123.delete.0001");

    await call("POST", `/api/groups/${groupId}/members/${placeholderId}/claim`, { bearer, token: groupToken });
    expect((await call("GET", "/api/auth/groups", { bearer })).json.groups).toHaveLength(1);

    const del = await call("DELETE", "/api/auth/account", { bearer });
    expect(del.status).toBe(204);

    // Index gone…
    expect((await call("GET", "/api/auth/groups", { bearer })).json.groups).toEqual([]);
    // …and the membership is a claimable placeholder again — no longer a
    // claimed member, so the token is needed again to see it.
    const claimable = await call("GET", `/api/groups/${groupId}/claimable`, { bearer, token: groupToken });
    expect((claimable.json.members as Json[]).map((m) => m.id)).toContain(placeholderId);
  });
});

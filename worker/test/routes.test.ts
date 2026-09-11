import { SELF, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";

const BASE = "https://api.test";

interface Json {
  [k: string]: unknown;
}

/** Every group created after `ACCESS_TOKEN_PLAN.md` has an `access_token`, so
 * every group-data call in this file needs one — appended as `?token=`
 * (`&token=` if the path already has a query string). */
function withToken(path: string, token?: string): string {
  if (token === undefined) return `${BASE}${path}`;
  return `${BASE}${path}${path.includes("?") ? "&" : "?"}token=${token}`;
}

async function post(path: string, body: unknown, token?: string): Promise<{ status: number; json: Json }> {
  const res = await SELF.fetch(withToken(path, token), { method: "POST", body: JSON.stringify(body) });
  return { status: res.status, json: res.status === 204 ? {} : ((await res.json()) as Json) };
}

async function put(path: string, body: unknown, token?: string): Promise<{ status: number; json: Json }> {
  const res = await SELF.fetch(withToken(path, token), { method: "PUT", body: JSON.stringify(body) });
  return { status: res.status, json: res.status === 204 ? {} : ((await res.json()) as Json) };
}

async function patch(path: string, body: unknown, token?: string): Promise<{ status: number; json: Json }> {
  const res = await SELF.fetch(withToken(path, token), { method: "PATCH", body: JSON.stringify(body) });
  return { status: res.status, json: res.status === 204 ? {} : ((await res.json()) as Json) };
}

async function del(path: string, token?: string): Promise<{ status: number; json: Json }> {
  const res = await SELF.fetch(withToken(path, token), { method: "DELETE" });
  const text = await res.text();
  return { status: res.status, json: text ? (JSON.parse(text) as Json) : {} };
}

async function get(
  path: string,
  headers?: Record<string, string>,
  token?: string,
): Promise<{ status: number; text: string; json: Json; robots: string | null }> {
  const res = await SELF.fetch(withToken(path, token), { headers });
  const text = await res.text();
  return {
    status: res.status,
    text,
    json: text ? (JSON.parse(text) as Json) : {},
    robots: res.headers.get("X-Robots-Tag"),
  };
}

async function makeGroup(): Promise<{ groupId: string; joinCode: string; creatorId: string; token: string }> {
  const { status, json } = await post("/api/groups", {
    name: "Goa Trip",
    currency: "INR",
    creatorDisplayName: "Indra",
  });
  expect(status).toBe(201);
  return {
    groupId: json.groupId as string,
    joinCode: json.joinCode as string,
    creatorId: (json.member as Json).id as string,
    token: (json.group as Json).accessToken as string,
  };
}

async function addMember(groupId: string, displayName: string, token: string): Promise<string> {
  const { status, json } = await post(`/api/groups/${groupId}/members`, { displayName }, token);
  expect(status).toBe(201);
  return (json.member as Json).id as string;
}

describe("POST /api/groups", () => {
  it("creates a group and returns ids, the creator, and the group summary with joinCode + accessToken", async () => {
    const { status, json } = await post("/api/groups", {
      name: "Goa Trip",
      currency: "INR",
      creatorDisplayName: "Indra",
    });
    expect(status).toBe(201);
    expect(json.groupId).toMatch(/^[0-9A-Za-z_-]{16}$/);
    expect(json.joinCode).toMatch(/^[A-Z2-9]{6}$/);
    expect(json.member).toMatchObject({ displayName: "Indra" });
    expect(json.group).toMatchObject({ name: "Goa Trip", currency: "INR", joinCode: json.joinCode });
    expect((json.group as Json).accessToken).toMatch(/^[0-9A-Za-z_-]{22}$/);
    expect(json.group).toHaveProperty("createdAt");
    expect(String((json.group as Json).createdAt)).not.toContain("."); // no fractional seconds
  });

  it("rejects an unknown field", async () => {
    const { status, json } = await post("/api/groups", {
      name: "X",
      currency: "INR",
      creatorDisplayName: "Y",
      extra: true,
    });
    expect(status).toBe(400);
    expect((json.error as Json).code).toBe("BAD_REQUEST");
  });

  it("rejects a missing field", async () => {
    const { status } = await post("/api/groups", { name: "X", currency: "INR" });
    expect(status).toBe(400);
  });
});

describe("GET /api/groups/:groupId", () => {
  it("returns the full state with a noindex header", async () => {
    const { groupId, joinCode, token } = await makeGroup();
    const { status, json, robots } = await get(`/api/groups/${groupId}`, undefined, token);
    expect(status).toBe(200);
    expect(robots).toBe("noindex");
    expect(json.group).toMatchObject({ name: "Goa Trip", currency: "INR", joinCode, accessToken: token });
    expect(json.members).toHaveLength(1);
    expect(json.expenses).toEqual([]);
    expect(json.settlements).toEqual([]);
    expect(json.balances).toEqual([]);
    expect(json.simplifiedSettlements).toEqual([]);
  });

  it("returns GROUP_NOT_FOUND for an unknown group", async () => {
    const { status, json } = await get("/api/groups/doesnotexist12345");
    expect(status).toBe(404);
    expect((json.error as Json).code).toBe("GROUP_NOT_FOUND");
  });

  it("returns FORBIDDEN for the right groupId with no token, or the wrong one", async () => {
    const { groupId } = await makeGroup();
    const noToken = await get(`/api/groups/${groupId}`);
    expect(noToken.status).toBe(403);
    expect((noToken.json.error as Json).code).toBe("FORBIDDEN");

    const wrongToken = await get(`/api/groups/${groupId}`, undefined, "not-the-real-token");
    expect(wrongToken.status).toBe(403);
  });
});

describe("POST /api/groups/:groupId/regenerate-link", () => {
  it("rotates the token — the old one stops working, the new one doesn't", async () => {
    const { groupId, token: oldToken } = await makeGroup();
    const { status, json } = await post(`/api/groups/${groupId}/regenerate-link`, {}, oldToken);
    expect(status).toBe(200);
    const newToken = json.accessToken as string;
    expect(newToken).toMatch(/^[0-9A-Za-z_-]{22}$/);
    expect(newToken).not.toBe(oldToken);

    expect((await get(`/api/groups/${groupId}`, undefined, oldToken)).status).toBe(403);
    expect((await get(`/api/groups/${groupId}`, undefined, newToken)).status).toBe(200);
  });

  it("403s with no token / the wrong one, 404s an unknown group", async () => {
    const { groupId } = await makeGroup();
    expect((await post(`/api/groups/${groupId}/regenerate-link`, {})).status).toBe(403);
    expect((await post(`/api/groups/${groupId}/regenerate-link`, {}, "nope")).status).toBe(403);
    expect((await post("/api/groups/doesnotexist12345/regenerate-link", {})).status).toBe(404);
  });
});

describe("GET /api/groups/resolve/:joinCode", () => {
  it("resolves a real code (case-insensitively) to its groupId and current accessToken", async () => {
    const { groupId, joinCode, token } = await makeGroup();
    const { status, json } = await get(`/api/groups/resolve/${joinCode.toLowerCase()}`);
    expect(status).toBe(200);
    expect(json.groupId).toBe(groupId);
    expect(json.accessToken).toBe(token);
  });

  it("returns the *current* accessToken even after a regenerate", async () => {
    const { groupId, joinCode, token: oldToken } = await makeGroup();
    const { json: regen } = await post(`/api/groups/${groupId}/regenerate-link`, {}, oldToken);
    const { json } = await get(`/api/groups/resolve/${joinCode}`);
    expect(json.accessToken).toBe(regen.accessToken);
    expect(json.accessToken).not.toBe(oldToken);
  });

  it("returns a bare 404 (no body) for an unknown code", async () => {
    const { status, text } = await get("/api/groups/resolve/ZZZZZZ");
    expect(status).toBe(404);
    expect(text).toBe("");
  });

  it("rate-limits after 20 lookups in a window", async () => {
    await makeGroup();
    // A dedicated IP, distinct from the other tests in this file — the
    // Rate Limiting binding's budget is keyed per-IP and, unlike Durable
    // Object storage, isn't reset between tests by vitest-pool-workers'
    // isolated-storage feature.
    const ip = "203.0.113.1";
    const statuses: number[] = [];
    for (let i = 0; i < 22; i++) {
      statuses.push((await get("/api/groups/resolve/ABCDEF", { "CF-Connecting-IP": ip })).status);
    }
    expect(statuses.slice(0, 20).every((s) => s === 404)).toBe(true);
    expect(statuses.at(-1)).toBe(429);
  });
});

describe("POST /api/groups/:groupId/members", () => {
  it("adds a member", async () => {
    const { groupId, token } = await makeGroup();
    const { status, json } = await post(`/api/groups/${groupId}/members`, { displayName: "Meera" }, token);
    expect(status).toBe(201);
    expect(json.member).toMatchObject({ displayName: "Meera" });
  });

  it("404s for an unknown group", async () => {
    const { status } = await post("/api/groups/nope/members", { displayName: "Meera" });
    expect(status).toBe(404);
  });
});

describe("POST /api/groups/:groupId/expenses", () => {
  let groupId: string;
  let token: string;
  let a: string;
  let b: string;

  beforeEach(async () => {
    const g = await makeGroup();
    groupId = g.groupId;
    token = g.token;
    a = g.creatorId;
    b = await addMember(groupId, "Ben", token);
  });

  it("records an equal-split expense and updates balances", async () => {
    const { status, json } = await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 1000 }],
        amountMinor: 1000,
        description: "Lunch",
        date: "2026-01-01T12:00:00Z",
        splitType: "equal",
        splits: [
          { memberId: a, amountMinor: 500 },
          { memberId: b, amountMinor: 500 },
        ],
      },
      token,
    );
    expect(status).toBe(201);
    expect(json.expense).toMatchObject({ description: "Lunch", amountMinor: 1000 });

    const state = await get(`/api/groups/${groupId}`, undefined, token);
    expect(state.json.balances).toEqual([
      { memberId: a, currency: "INR", netMinor: 500 },
      { memberId: b, currency: "INR", netMinor: -500 },
    ]);
    expect(state.json.simplifiedSettlements).toEqual([{ fromId: b, toId: a, amountMinor: 500, currency: "INR" }]);
  });

  it("treats a repeated client id as an idempotent replay", async () => {
    const payload = {
      id: "11111111-1111-1111-1111-111111111111",
      payers: [{ memberId: a, amountMinor: 200 }],
      amountMinor: 200,
      description: "Coffee",
      date: "2026-01-01T09:00:00Z",
      splitType: "equal",
      splits: [
        { memberId: a, amountMinor: 100 },
        { memberId: b, amountMinor: 100 },
      ],
    };
    const first = await post(`/api/groups/${groupId}/expenses`, payload, token);
    const second = await post(`/api/groups/${groupId}/expenses`, payload, token);
    expect(first.status).toBe(201);
    expect(second.status).toBe(201);
    expect(second.json.expense).toEqual(first.json.expense);

    const state = await get(`/api/groups/${groupId}`, undefined, token);
    expect(state.json.expenses).toHaveLength(1);
  });

  it("rejects splits that don't sum to the amount (SPLIT_MISMATCH)", async () => {
    const { status, json } = await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 1000 }],
        amountMinor: 1000,
        description: "x",
        date: "2026-01-01T12:00:00Z",
        splitType: "exact",
        splits: [
          { memberId: a, amountMinor: 400 },
          { memberId: b, amountMinor: 400 },
        ],
      },
      token,
    );
    expect(status).toBe(400);
    expect((json.error as Json).code).toBe("SPLIT_MISMATCH");
  });

  it("rejects an unknown member (UNKNOWN_MEMBER)", async () => {
    const { status, json } = await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 100 }],
        amountMinor: 100,
        description: "x",
        date: "2026-01-01T12:00:00Z",
        splitType: "equal",
        splits: [
          { memberId: a, amountMinor: 50 },
          { memberId: "ghost", amountMinor: 50 },
        ],
      },
      token,
    );
    expect(status).toBe(400);
    expect((json.error as Json).code).toBe("UNKNOWN_MEMBER");
  });

  it("rejects a non-positive amount (INVALID_AMOUNT)", async () => {
    const { status, json } = await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 0 }],
        amountMinor: 0,
        description: "x",
        date: "2026-01-01T12:00:00Z",
        splitType: "equal",
        splits: [{ memberId: a, amountMinor: 0 }],
      },
      token,
    );
    expect(status).toBe(400);
    expect((json.error as Json).code).toBe("INVALID_AMOUNT");
  });

  it("rejects a bad splitType", async () => {
    const { status, json } = await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 100 }],
        amountMinor: 100,
        description: "x",
        date: "2026-01-01T12:00:00Z",
        splitType: "weighted",
        splits: [{ memberId: a, amountMinor: 100 }],
      },
      token,
    );
    expect(status).toBe(400);
    expect((json.error as Json).code).toBe("BAD_REQUEST");
  });

  it("records a percentage-split expense (splits already resolved to minor units)", async () => {
    const { status, json } = await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 1000 }],
        amountMinor: 1000,
        description: "Dinner (70/30)",
        date: "2026-01-01T20:00:00Z",
        splitType: "percentage",
        splits: [
          { memberId: a, amountMinor: 700 },
          { memberId: b, amountMinor: 300 },
        ],
      },
      token,
    );
    expect(status).toBe(201);
    expect(json.expense).toMatchObject({ splitType: "percentage", amountMinor: 1000 });

    const state = await get(`/api/groups/${groupId}`, undefined, token);
    expect(state.json.balances).toEqual([
      { memberId: a, currency: "INR", netMinor: 300 },
      { memberId: b, currency: "INR", netMinor: -300 },
    ]);
  });

  it("still rejects percentage splits that don't sum to the amount (SPLIT_MISMATCH)", async () => {
    const { status, json } = await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 1000 }],
        amountMinor: 1000,
        description: "x",
        date: "2026-01-01T12:00:00Z",
        splitType: "percentage",
        splits: [
          { memberId: a, amountMinor: 700 },
          { memberId: b, amountMinor: 200 },
        ],
      },
      token,
    );
    expect(status).toBe(400);
    expect((json.error as Json).code).toBe("SPLIT_MISMATCH");
  });

  it("records an itemized expense and round-trips its line items", async () => {
    const { status, json } = await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 1000 }],
        amountMinor: 1000,
        description: "Groceries",
        date: "2026-01-02T09:00:00Z",
        splitType: "itemized",
        splits: [
          { memberId: a, amountMinor: 700 },
          { memberId: b, amountMinor: 300 },
        ],
        items: [
          { id: "li1", name: "Cheese", amountMinor: 600, participantIds: [a, b] },
          { id: "li2", name: "Wine", amountMinor: 400, participantIds: [a] },
        ],
      },
      token,
    );
    expect(status).toBe(201);
    expect(json.expense).toMatchObject({ splitType: "itemized", amountMinor: 1000 });
    expect((json.expense as Json).items).toEqual([
      { id: "li1", name: "Cheese", amountMinor: 600, participantIds: [a, b] },
      { id: "li2", name: "Wine", amountMinor: 400, participantIds: [a] },
    ]);

    const state = await get(`/api/groups/${groupId}`, undefined, token);
    expect(state.json.balances).toEqual([
      { memberId: a, currency: "INR", netMinor: 300 },
      { memberId: b, currency: "INR", netMinor: -300 },
    ]);
  });

  it("rejects splitType itemized without items, and items without itemized", async () => {
    const noItems = await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 100 }], amountMinor: 100, description: "x", date: "2026-01-01T12:00:00Z",
        splitType: "itemized", splits: [{ memberId: a, amountMinor: 100 }],
      },
      token,
    );
    expect(noItems.status).toBe(400);
    expect((noItems.json.error as Json).code).toBe("BAD_REQUEST");

    const strayItems = await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 100 }], amountMinor: 100, description: "x", date: "2026-01-01T12:00:00Z",
        splitType: "equal", splits: [{ memberId: a, amountMinor: 100 }],
        items: [{ id: "i", name: "n", amountMinor: 100, participantIds: [a] }],
      },
      token,
    );
    expect(strayItems.status).toBe(400);
    expect((strayItems.json.error as Json).code).toBe("BAD_REQUEST");
  });

  it("rejects itemized line items that don't sum to the amount (SPLIT_MISMATCH)", async () => {
    const { status, json } = await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 1000 }], amountMinor: 1000, description: "x", date: "2026-01-01T12:00:00Z",
        splitType: "itemized",
        splits: [{ memberId: a, amountMinor: 1000 }],
        items: [{ id: "i", name: "Only", amountMinor: 900, participantIds: [a] }],
      },
      token,
    );
    expect(status).toBe(400);
    expect((json.error as Json).code).toBe("SPLIT_MISMATCH");
  });

  it("records a multi-payer expense, round-trips it, and 400s on a bad total", async () => {
    const { status, json } = await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 700 }, { memberId: b, amountMinor: 300 }],
        amountMinor: 1000,
        description: "Groceries",
        date: "2026-01-02T09:00:00Z",
        splitType: "equal",
        splits: [{ memberId: a, amountMinor: 500 }, { memberId: b, amountMinor: 500 }],
      },
      token,
    );
    expect(status).toBe(201);
    expect((json.expense as Json).payers).toEqual([
      { memberId: a, amountMinor: 700 },
      { memberId: b, amountMinor: 300 },
    ]);

    const state = await get(`/api/groups/${groupId}`, undefined, token);
    expect(state.json.balances).toEqual([
      { memberId: a, currency: "INR", netMinor: 200 }, // paid 700, owes 500
      { memberId: b, currency: "INR", netMinor: -200 }, // paid 300, owes 500
    ]);

    const badTotal = await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 700 }, { memberId: b, amountMinor: 200 }],
        amountMinor: 1000,
        description: "x",
        date: "2026-01-02T09:00:00Z",
        splitType: "equal",
        splits: [{ memberId: a, amountMinor: 500 }, { memberId: b, amountMinor: 500 }],
      },
      token,
    );
    expect(badTotal.status).toBe(400);
    expect((badTotal.json.error as Json).code).toBe("SPLIT_MISMATCH");
  });

  it("records a shares expense and round-trips its weights", async () => {
    const { status, json } = await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 1000 }],
        amountMinor: 1000,
        description: "Rent",
        date: "2026-01-02T09:00:00Z",
        splitType: "shares",
        splits: [
          { memberId: a, amountMinor: 700 },
          { memberId: b, amountMinor: 300 },
        ],
        shares: [
          { memberId: a, weight: 7 },
          { memberId: b, weight: 3 },
        ],
      },
      token,
    );
    expect(status).toBe(201);
    expect(json.expense).toMatchObject({ splitType: "shares", amountMinor: 1000 });
    expect((json.expense as Json).shares).toEqual([
      { memberId: a, weight: 7 },
      { memberId: b, weight: 3 },
    ]);

    const state = await get(`/api/groups/${groupId}`, undefined, token);
    expect(state.json.balances).toEqual([
      { memberId: a, currency: "INR", netMinor: 300 },
      { memberId: b, currency: "INR", netMinor: -300 },
    ]);
  });

  it("rejects splitType shares without weights, and weights without shares", async () => {
    const noShares = await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 100 }], amountMinor: 100, description: "x", date: "2026-01-01T12:00:00Z",
        splitType: "shares", splits: [{ memberId: a, amountMinor: 100 }],
      },
      token,
    );
    expect(noShares.status).toBe(400);
    expect((noShares.json.error as Json).code).toBe("BAD_REQUEST");

    const strayShares = await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 100 }], amountMinor: 100, description: "x", date: "2026-01-01T12:00:00Z",
        splitType: "equal", splits: [{ memberId: a, amountMinor: 100 }],
        shares: [{ memberId: a, weight: 1 }],
      },
      token,
    );
    expect(strayShares.status).toBe(400);
    expect((strayShares.json.error as Json).code).toBe("BAD_REQUEST");
  });

  it("rejects shares weights that are all zero (SPLIT_MISMATCH)", async () => {
    const { status, json } = await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 100 }], amountMinor: 100, description: "x", date: "2026-01-01T12:00:00Z",
        splitType: "shares",
        splits: [{ memberId: a, amountMinor: 100 }],
        shares: [{ memberId: a, weight: 0 }, { memberId: b, weight: 0 }],
      },
      token,
    );
    expect(status).toBe(400);
    expect((json.error as Json).code).toBe("SPLIT_MISMATCH");
  });

  it("round-trips a category and its icon", async () => {
    const { status, json } = await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 500 }],
        amountMinor: 500,
        description: "Taxi",
        date: "2026-01-02T09:00:00Z",
        splitType: "equal",
        splits: [
          { memberId: a, amountMinor: 250 },
          { memberId: b, amountMinor: 250 },
        ],
        category: "Transport",
        categoryIcon: "car",
      },
      token,
    );
    expect(status).toBe(201);
    expect(json.expense).toMatchObject({ category: "Transport", categoryIcon: "car" });

    const state = await get(`/api/groups/${groupId}`, undefined, token);
    const stored = (state.json.expenses as Json[]).find((e) => (e as Json).description === "Taxi");
    expect(stored).toMatchObject({ category: "Transport", categoryIcon: "car" });
  });

  it("omits the category keys entirely when no category is given", async () => {
    const { json } = await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 200 }],
        amountMinor: 200,
        description: "Uncategorised",
        date: "2026-01-02T10:00:00Z",
        splitType: "equal",
        splits: [
          { memberId: a, amountMinor: 100 },
          { memberId: b, amountMinor: 100 },
        ],
      },
      token,
    );
    expect(json.expense).not.toHaveProperty("category");
    expect(json.expense).not.toHaveProperty("categoryIcon");
  });

  it("defaults currency to the group's, and keeps a foreign currency in its own bucket", async () => {
    const base = { date: "2026-01-03T10:00:00Z", splitType: "equal" as const };
    // No currency → group default (INR).
    const inr = await post(
      `/api/groups/${groupId}/expenses`,
      {
        ...base, payers: [{ memberId: a, amountMinor: 1000 }], amountMinor: 1000, description: "INR lunch",
        splits: [{ memberId: a, amountMinor: 500 }, { memberId: b, amountMinor: 500 }],
      },
      token,
    );
    expect((inr.json.expense as Json).currency).toBe("INR");
    // Explicit USD → its own ledger.
    await post(
      `/api/groups/${groupId}/expenses`,
      {
        ...base, payers: [{ memberId: b, amountMinor: 800 }], amountMinor: 800, currency: "USD", description: "USD dinner",
        splits: [{ memberId: a, amountMinor: 400 }, { memberId: b, amountMinor: 400 }],
      },
      token,
    );

    const state = await get(`/api/groups/${groupId}`, undefined, token);
    expect(state.json.balances).toEqual([
      { memberId: a, currency: "INR", netMinor: 500 },
      { memberId: b, currency: "INR", netMinor: -500 },
      { memberId: a, currency: "USD", netMinor: -400 },
      { memberId: b, currency: "USD", netMinor: 400 },
    ]);
    expect(state.json.simplifiedSettlements).toEqual([
      { fromId: b, toId: a, amountMinor: 500, currency: "INR" },
      { fromId: a, toId: b, amountMinor: 400, currency: "USD" },
    ]);
  });

  // --- receipt photos (CHECKLIST.md "Photo attachment on an expense") ---

  it("stores receipt attachments and returns them; an edit that drops one deletes its R2 object", async () => {
    const eid = "aaaaaaaa-bbbb-cccc-dddd-000000000001";
    const k1 = `expenses/${groupId}/${eid}/r1`;
    const k2 = `expenses/${groupId}/${eid}/r2`;
    await env.MEDIA.put(k1, new Uint8Array([1]));
    await env.MEDIA.put(k2, new Uint8Array([2]));

    const base = {
      id: eid, payers: [{ memberId: a, amountMinor: 1000 }], amountMinor: 1000, description: "Dinner", date: "2026-02-01T20:00:00Z",
      splitType: "equal", splits: [{ memberId: a, amountMinor: 500 }, { memberId: b, amountMinor: 500 }],
    };

    const added = await post(`/api/groups/${groupId}/expenses`, { ...base, attachments: [k1, k2] }, token);
    expect(added.status).toBe(201);
    expect((added.json.expense as Json).attachments).toEqual([k1, k2]);

    // Edit down to just k1 → k2's object is deleted.
    const edited = await put(`/api/groups/${groupId}/expenses/${eid}`, { ...base, id: undefined, attachments: [k1] }, token);
    expect(edited.status).toBe(200);
    expect((edited.json.expense as Json).attachments).toEqual([k1]);
    expect(await env.MEDIA.head(k2)).toBeNull();
    expect(await env.MEDIA.head(k1)).not.toBeNull();

    // Omitting `attachments` on a later edit leaves the stored list alone.
    const renamed = await put(`/api/groups/${groupId}/expenses/${eid}`, { ...base, id: undefined, description: "Late dinner" }, token);
    expect((renamed.json.expense as Json).attachments).toEqual([k1]);
  });

  it("rejects an attachment key that isn't this expense's, and attachments with no id", async () => {
    const base = {
      payers: [{ memberId: a, amountMinor: 100 }], amountMinor: 100, description: "x", date: "2026-02-01T20:00:00Z",
      splitType: "equal", splits: [{ memberId: a, amountMinor: 50 }, { memberId: b, amountMinor: 50 }],
    };
    // attachments but no client id
    expect((await post(`/api/groups/${groupId}/expenses`, { ...base, attachments: ["expenses/x/y/z"] }, token)).status).toBe(400);
    // a key for a different expense
    const eid = "aaaaaaaa-bbbb-cccc-dddd-000000000002";
    const foreign = await post(
      `/api/groups/${groupId}/expenses`,
      { ...base, id: eid, attachments: [`expenses/${groupId}/SOMEONE-ELSE/r1`] },
      token,
    );
    expect(foreign.status).toBe(400);
  });
});

describe("POST /api/groups/:groupId/settlements", () => {
  it("records a settlement and clears the balance", async () => {
    const { groupId, creatorId: a, token } = await makeGroup();
    const b = await addMember(groupId, "Ben", token);
    await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 1000 }],
        amountMinor: 1000,
        description: "Lunch",
        date: "2026-01-01T12:00:00Z",
        splitType: "equal",
        splits: [
          { memberId: a, amountMinor: 500 },
          { memberId: b, amountMinor: 500 },
        ],
      },
      token,
    );

    const { status, json } = await post(
      `/api/groups/${groupId}/settlements`,
      { fromId: b, toId: a, amountMinor: 500 },
      token,
    );
    expect(status).toBe(201);
    expect(json.settlement).toMatchObject({ fromId: b, toId: a, amountMinor: 500 });

    const state = await get(`/api/groups/${groupId}`, undefined, token);
    expect(state.json.balances).toEqual([]); // fully settled — no nonzero balances
  });

  it("rejects a settlement to oneself", async () => {
    const { groupId, creatorId: a, token } = await makeGroup();
    const { status, json } = await post(
      `/api/groups/${groupId}/settlements`,
      { fromId: a, toId: a, amountMinor: 100 },
      token,
    );
    expect(status).toBe(400);
    expect((json.error as Json).code).toBe("UNKNOWN_MEMBER");
  });
});

describe('POST /api/groups/:groupId/members/:memberId/remind (CHECKLIST.md "Remind button")', () => {
  it("reports sent:false when the two members aren't in this group", async () => {
    const { groupId, creatorId: a, token } = await makeGroup();
    const { status, json } = await post(`/api/groups/${groupId}/members/ghost/remind`, { fromMemberId: a }, token);
    expect(status).toBe(200);
    expect(json).toEqual({ sent: false });
  });

  it("reports sent:false when nothing is owed in that direction", async () => {
    const { groupId, creatorId: a, token } = await makeGroup();
    const b = await addMember(groupId, "Ben", token);
    // No expenses at all yet — fully settled, no edge either way.
    const { status, json } = await post(`/api/groups/${groupId}/members/${b}/remind`, { fromMemberId: a }, token);
    expect(status).toBe(200);
    expect(json).toEqual({ sent: false });
  });

  it("reports sent:false for the wrong direction — the asker owes the target, not vice versa", async () => {
    const { groupId, creatorId: a, token } = await makeGroup();
    const b = await addMember(groupId, "Ben", token);
    await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: b, amountMinor: 1000 }],
        amountMinor: 1000,
        description: "Lunch",
        date: "2026-01-01T12:00:00Z",
        splitType: "equal",
        splits: [
          { memberId: a, amountMinor: 500 },
          { memberId: b, amountMinor: 500 },
        ],
      },
      token,
    );
    // `a` owes `b` here, so `a` reminding `b` (as if `b` owed `a`) finds no edge.
    const { status, json } = await post(`/api/groups/${groupId}/members/${b}/remind`, { fromMemberId: a }, token);
    expect(status).toBe(200);
    expect(json).toEqual({ sent: false });
  });

  it("reports sent:false when the debtor hasn't claimed a signed-in identity yet", async () => {
    const { groupId, creatorId: a, token } = await makeGroup();
    const b = await addMember(groupId, "Ben", token);
    await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 1000 }],
        amountMinor: 1000,
        description: "Lunch",
        date: "2026-01-01T12:00:00Z",
        splitType: "equal",
        splits: [
          { memberId: a, amountMinor: 500 },
          { memberId: b, amountMinor: 500 },
        ],
      },
      token,
    );
    // `b` owes `a` 500, but `b` is still a placeholder — nobody to push.
    const { status, json } = await post(`/api/groups/${groupId}/members/${b}/remind`, { fromMemberId: a }, token);
    expect(status).toBe(200);
    expect(json).toEqual({ sent: false });
  });

  it("reports sent:false (APNs unconfigured in tests) once the debtor is claimed, rather than throwing", async () => {
    const { groupId, creatorId: a, token } = await makeGroup();
    const b = await addMember(groupId, "Ben", token);
    await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 1000 }],
        amountMinor: 1000,
        description: "Lunch",
        date: "2026-01-01T12:00:00Z",
        splitType: "equal",
        splits: [
          { memberId: a, amountMinor: 500 },
          { memberId: b, amountMinor: 500 },
        ],
      },
      token,
    );
    await env.GROUP_DO.get(env.GROUP_DO.idFromName(groupId)).claim(b, "apple:ben-remind");

    const { status, json } = await post(`/api/groups/${groupId}/members/${b}/remind`, { fromMemberId: a }, token);
    expect(status).toBe(200);
    expect(json).toEqual({ sent: false }); // no APNS_* secrets bound in the test env — see `notify.test.ts` for the sent:true path
  });

  it("400s when fromMemberId is missing", async () => {
    const { groupId, token } = await makeGroup();
    const b = await addMember(groupId, "Ben", token);
    const { status } = await post(`/api/groups/${groupId}/members/${b}/remind`, {}, token);
    expect(status).toBe(400);
  });

  it("403s without the group's access token", async () => {
    const { groupId, creatorId: a } = await makeGroup();
    const { status } = await post(`/api/groups/${groupId}/members/${a}/remind`, { fromMemberId: a });
    expect(status).toBe(403);
  });
});

describe("edit / delete", () => {
  let groupId: string;
  let token: string;
  let a: string;
  let b: string;

  const equalSplit = (amount: number) => [
    { memberId: a, amountMinor: amount / 2 },
    { memberId: b, amountMinor: amount / 2 },
  ];

  beforeEach(async () => {
    const g = await makeGroup();
    groupId = g.groupId;
    token = g.token;
    a = g.creatorId;
    b = await addMember(groupId, "Ben", token);
  });

  async function addExpense(amount: number, description = "x"): Promise<string> {
    const { json } = await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: amount }], amountMinor: amount, description, date: "2026-01-01T12:00:00Z",
        splitType: "equal", splits: equalSplit(amount),
      },
      token,
    );
    return (json.expense as Json).id as string;
  }

  it("PUT replaces an expense and recomputes balances; created_at keeps feed order", async () => {
    const first = await addExpense(1000, "Lunch");
    await new Promise((r) => setTimeout(r, 2));
    const second = await addExpense(400, "Coffee");

    const { status, json } = await put(
      `/api/groups/${groupId}/expenses/${first}`,
      {
        payers: [{ memberId: b, amountMinor: 2000 }], amountMinor: 2000, description: "Lunch (fixed)", date: "2026-01-02T12:00:00Z",
        splitType: "equal", splits: [
          { memberId: a, amountMinor: 1000 },
          { memberId: b, amountMinor: 1000 },
        ],
      },
      token,
    );
    expect(status).toBe(200);
    expect(json.expense).toMatchObject({ id: first, payers: [{ memberId: b, amountMinor: 2000 }], amountMinor: 2000, description: "Lunch (fixed)" });

    const state = await get(`/api/groups/${groupId}`, undefined, token);
    // b paid 2000 (own share 1000) → +1000; plus the unchanged 400 Coffee (a paid, -200 to b)
    expect(state.json.balances).toEqual([
      { memberId: a, currency: "INR", netMinor: -800 },
      { memberId: b, currency: "INR", netMinor: 800 },
    ]);
    // order unchanged: edited "Lunch (fixed)" still before "Coffee"
    expect((state.json.expenses as Json[]).map((e) => e.description)).toEqual(["Lunch (fixed)", "Coffee"]);
    expect((state.json.expenses as Json[])[0]!.id).toBe(first);
    expect((state.json.expenses as Json[])[1]!.id).toBe(second);
  });

  it("PUT to an unknown expense id → 404 NOT_FOUND", async () => {
    const { status, json } = await put(
      `/api/groups/${groupId}/expenses/ghost`,
      {
        payers: [{ memberId: a, amountMinor: 100 }], amountMinor: 100, description: "x", date: "2026-01-01T12:00:00Z",
        splitType: "equal", splits: equalSplit(100),
      },
      token,
    );
    expect(status).toBe(404);
    expect((json.error as Json).code).toBe("NOT_FOUND");
  });

  it("PUT still validates the splits", async () => {
    const id = await addExpense(1000);
    const { status, json } = await put(
      `/api/groups/${groupId}/expenses/${id}`,
      {
        payers: [{ memberId: a, amountMinor: 1000 }], amountMinor: 1000, description: "x", date: "2026-01-01T12:00:00Z",
        splitType: "exact", splits: [
          { memberId: a, amountMinor: 400 },
          { memberId: b, amountMinor: 400 },
        ],
      },
      token,
    );
    expect(status).toBe(400);
    expect((json.error as Json).code).toBe("SPLIT_MISMATCH");
  });

  it("PUT rejects a body `id` field", async () => {
    const id = await addExpense(1000);
    const { status } = await put(
      `/api/groups/${groupId}/expenses/${id}`,
      {
        id: "spoof", payers: [{ memberId: a, amountMinor: 1000 }], amountMinor: 1000, description: "x", date: "2026-01-01T12:00:00Z",
        splitType: "equal", splits: equalSplit(1000),
      },
      token,
    );
    expect(status).toBe(400);
  });

  it("DELETE removes an expense and its splits; balances update; idempotent", async () => {
    const id = await addExpense(1000);
    expect((await del(`/api/groups/${groupId}/expenses/${id}`, token)).status).toBe(204);

    const state = await get(`/api/groups/${groupId}`, undefined, token);
    expect(state.json.expenses).toEqual([]);
    expect(state.json.balances).toEqual([]);

    // second delete is a no-op success
    expect((await del(`/api/groups/${groupId}/expenses/${id}`, token)).status).toBe(204);
    expect((await del(`/api/groups/${groupId}/expenses/never-existed`, token)).status).toBe(204);
  });

  it("DELETE soft-deletes with attribution — GET /trash shows it, POST restore brings it back", async () => {
    const id = await addExpense(1000, "Lunch");
    expect((await del(`/api/groups/${groupId}/expenses/${id}?deletedBy=${b}`, token)).status).toBe(204);

    expect((await get(`/api/groups/${groupId}`, undefined, token)).json.expenses).toEqual([]);

    const trash = await get(`/api/groups/${groupId}/trash`, undefined, token);
    expect(trash.status).toBe(200);
    expect(trash.json.expenses).toHaveLength(1);
    expect((trash.json.expenses as Json[])[0]).toMatchObject({ id, deletedBy: b });
    expect(trash.json.settlements).toEqual([]);

    const restore = await post(`/api/groups/${groupId}/expenses/${id}/restore`, {}, token);
    expect(restore.status).toBe(200);
    expect((restore.json.expense as Json).id).toBe(id);
    expect((restore.json.expense as Json)).not.toHaveProperty("deletedBy");

    expect((await get(`/api/groups/${groupId}`, undefined, token)).json.expenses).toHaveLength(1);
    expect((await get(`/api/groups/${groupId}/trash`, undefined, token)).json.expenses).toEqual([]);
  });

  it("POST restore 404s an id that's still active, or unknown", async () => {
    const id = await addExpense(1000);
    expect((await post(`/api/groups/${groupId}/expenses/${id}/restore`, {}, token)).status).toBe(404);
    expect((await post(`/api/groups/${groupId}/expenses/ghost/restore`, {}, token)).status).toBe(404);
  });

  it("settlement DELETE/trash/restore mirror expenses", async () => {
    const { json } = await post(`/api/groups/${groupId}/settlements`, { fromId: b, toId: a, amountMinor: 200 }, token);
    const sId = (json.settlement as Json).id as string;

    expect((await del(`/api/groups/${groupId}/settlements/${sId}?deletedBy=${a}`, token)).status).toBe(204);
    expect((await get(`/api/groups/${groupId}`, undefined, token)).json.settlements).toEqual([]);

    const trash = await get(`/api/groups/${groupId}/trash`, undefined, token);
    expect(trash.json.settlements).toMatchObject([{ id: sId, deletedBy: a }]);

    const restore = await post(`/api/groups/${groupId}/settlements/${sId}/restore`, {}, token);
    expect(restore.status).toBe(200);
    expect((await get(`/api/groups/${groupId}`, undefined, token)).json.settlements).toHaveLength(1);
  });

  it("PUT / DELETE a settlement", async () => {
    await addExpense(1000, "Lunch");
    const { json } = await post(
      `/api/groups/${groupId}/settlements`,
      { fromId: b, toId: a, amountMinor: 200 },
      token,
    );
    const sId = (json.settlement as Json).id as string;

    const upd = await put(
      `/api/groups/${groupId}/settlements/${sId}`,
      { fromId: b, toId: a, amountMinor: 500 },
      token,
    );
    expect(upd.status).toBe(200);
    expect(upd.json.settlement).toMatchObject({ id: sId, amountMinor: 500 });

    let state = await get(`/api/groups/${groupId}`, undefined, token);
    expect(state.json.balances).toEqual([]); // 1000 lunch → b owes a 500; settled 500 → clear

    expect((await del(`/api/groups/${groupId}/settlements/${sId}`, token)).status).toBe(204);
    state = await get(`/api/groups/${groupId}`, undefined, token);
    expect(state.json.settlements).toEqual([]);
    expect(state.json.balances).toEqual([
      { memberId: a, currency: "INR", netMinor: 500 },
      { memberId: b, currency: "INR", netMinor: -500 },
    ]);
  });

  it("PUT to an unknown settlement id → 404 NOT_FOUND", async () => {
    const { status, json } = await put(
      `/api/groups/${groupId}/settlements/ghost`,
      { fromId: a, toId: b, amountMinor: 100 },
      token,
    );
    expect(status).toBe(404);
    expect((json.error as Json).code).toBe("NOT_FOUND");
  });

  it("404s edit / delete on an unknown group", async () => {
    expect((await put("/api/groups/nope123/expenses/x", {
      payers: [{ memberId: "a", amountMinor: 1 }], amountMinor: 1, description: "x", date: "2026-01-01T12:00:00Z", splitType: "equal", splits: [],
    })).status).toBe(404);
    expect((await del("/api/groups/nope123/expenses/x")).status).toBe(404);
  });
});

describe('comments (CHECKLIST.md "Comments on an expense")', () => {
  let groupId: string;
  let token: string;
  let a: string;
  let b: string;
  let expenseId: string;

  beforeEach(async () => {
    const g = await makeGroup();
    groupId = g.groupId;
    token = g.token;
    a = g.creatorId;
    b = await addMember(groupId, "Ben", token);
    const { json } = await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 500 }], amountMinor: 500, description: "Taxi", date: "2026-01-01T12:00:00Z",
        splitType: "equal", splits: [{ memberId: a, amountMinor: 250 }, { memberId: b, amountMinor: 250 }],
      },
      token,
    );
    expenseId = (json.expense as Json).id as string;
  });

  it("POST adds a comment, GET lists it; a second lists both, oldest first", async () => {
    const first = await post(`/api/groups/${groupId}/expenses/${expenseId}/comments`, {
      authorMemberId: a, text: "I'll cover the tip",
    }, token);
    expect(first.status).toBe(201);
    expect(first.json.comment).toMatchObject({ expenseId, authorMemberId: a, text: "I'll cover the tip" });
    expect(first.json.comment).toHaveProperty("id");
    expect(first.json.comment).toHaveProperty("createdAt");

    await post(`/api/groups/${groupId}/expenses/${expenseId}/comments`, { authorMemberId: b, text: "Thanks!" }, token);

    const list = await get(`/api/groups/${groupId}/expenses/${expenseId}/comments`, undefined, token);
    expect(list.status).toBe(200);
    expect((list.json.comments as Json[]).map((c) => c.text)).toEqual(["I'll cover the tip", "Thanks!"]);
  });

  it("a client-generated id makes a retried POST an idempotent replay", async () => {
    const body = { id: "c-fixed", authorMemberId: a, text: "original" };
    const first = await post(`/api/groups/${groupId}/expenses/${expenseId}/comments`, body, token);
    expect(first.status).toBe(201);
    const retry = await post(
      `/api/groups/${groupId}/expenses/${expenseId}/comments`,
      { id: "c-fixed", authorMemberId: a, text: "different text" },
      token,
    );
    expect(retry.status).toBe(201);
    expect(retry.json.comment).toMatchObject({ text: "original" }); // unchanged, not a second row
    const list = await get(`/api/groups/${groupId}/expenses/${expenseId}/comments`, undefined, token);
    expect(list.json.comments).toHaveLength(1);
  });

  it("rejects an empty comment, an unknown author, and an unknown expense", async () => {
    const empty = await post(`/api/groups/${groupId}/expenses/${expenseId}/comments`, { authorMemberId: a, text: "  " }, token);
    expect(empty.status).toBe(400);

    const ghostAuthor = await post(
      `/api/groups/${groupId}/expenses/${expenseId}/comments`,
      { authorMemberId: "ghost", text: "hi" },
      token,
    );
    expect(ghostAuthor.status).toBe(400);
    expect((ghostAuthor.json.error as Json).code).toBe("UNKNOWN_MEMBER");

    const ghostExpense = await post(
      `/api/groups/${groupId}/expenses/ghost/comments`,
      { authorMemberId: a, text: "hi" },
      token,
    );
    expect(ghostExpense.status).toBe(404);
    expect((ghostExpense.json.error as Json).code).toBe("NOT_FOUND");
  });

  it("DELETE soft-deletes a comment — gone from the list, idempotent, no restore route", async () => {
    const { json } = await post(`/api/groups/${groupId}/expenses/${expenseId}/comments`, {
      authorMemberId: a, text: "oops",
    }, token);
    const commentId = (json.comment as Json).id as string;

    const first = await del(`/api/groups/${groupId}/expenses/${expenseId}/comments/${commentId}`, token);
    expect(first.status).toBe(204);
    expect((await get(`/api/groups/${groupId}/expenses/${expenseId}/comments`, undefined, token)).json.comments).toEqual([]);

    // idempotent — deleting again, or an id that never existed, is still 204
    expect((await del(`/api/groups/${groupId}/expenses/${expenseId}/comments/${commentId}`, token)).status).toBe(204);
    expect((await del(`/api/groups/${groupId}/expenses/${expenseId}/comments/ghost`, token)).status).toBe(204);
  });

  it("401/403s the same way any group route does without the right credential", async () => {
    const noToken = await post(`/api/groups/${groupId}/expenses/${expenseId}/comments`, { authorMemberId: a, text: "hi" });
    expect(noToken.status).toBe(403);
    const wrongToken = await get(`/api/groups/${groupId}/expenses/${expenseId}/comments`, undefined, "wrong-token");
    expect(wrongToken.status).toBe(403);
  });
});

describe("group + member settings", () => {
  let groupId: string;
  let token: string;
  let a: string;
  let b: string;

  beforeEach(async () => {
    const g = await makeGroup();
    groupId = g.groupId;
    token = g.token;
    a = g.creatorId;
    b = await addMember(groupId, "Ben", token);
  });

  it("PATCH /api/groups/:id renames and changes the default currency", async () => {
    const { status, json } = await patch(`/api/groups/${groupId}`, { name: "Goa 2.0", currency: "USD" }, token);
    expect(status).toBe(200);
    expect(json.group).toMatchObject({ name: "Goa 2.0", currency: "USD" });

    const state = await get(`/api/groups/${groupId}`, undefined, token);
    expect(state.json.group).toMatchObject({ name: "Goa 2.0", currency: "USD" });
  });

  it("PATCH /api/groups/:id changing currency doesn't touch existing expenses", async () => {
    await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 1000 }], amountMinor: 1000, description: "INR lunch", date: "2026-01-01T12:00:00Z",
        splitType: "equal", splits: [{ memberId: a, amountMinor: 500 }, { memberId: b, amountMinor: 500 }],
      },
      token,
    );
    await patch(`/api/groups/${groupId}`, { currency: "USD" }, token);

    const state = await get(`/api/groups/${groupId}`, undefined, token);
    expect((state.json.expenses as Json[])[0]!.currency).toBe("INR");
  });

  it("PATCH /api/groups/:id with no fields → 400", async () => {
    expect((await patch(`/api/groups/${groupId}`, {}, token)).status).toBe(400);
  });

  it("PATCH /api/groups/:id sets, keeps, and clears the group emoji", async () => {
    const stateEmoji = async () =>
      ((await get(`/api/groups/${groupId}`, undefined, token)).json.group as Json).emoji;

    // Absent on a fresh group.
    expect(await stateEmoji()).toBeNull();

    // Set it.
    const set = await patch(`/api/groups/${groupId}`, { emoji: "🏖️" }, token);
    expect(set.status).toBe(200);
    expect((set.json.group as Json).emoji).toBe("🏖️");
    expect(await stateEmoji()).toBe("🏖️");

    // A rename leaves the emoji alone (key absent).
    await patch(`/api/groups/${groupId}`, { name: "Beach Trip" }, token);
    expect(await stateEmoji()).toBe("🏖️");

    // Explicit null clears it.
    const cleared = await patch(`/api/groups/${groupId}`, { emoji: null }, token);
    expect((cleared.json.group as Json).emoji).toBeNull();
    expect(await stateEmoji()).toBeNull();
  });

  it("PATCH /api/groups/:id rejects a non-emoji text label in emoji → 400", async () => {
    expect((await patch(`/api/groups/${groupId}`, { emoji: "the beach house trip 2026" }, token)).status).toBe(400);
  });

  it("PATCH /api/groups/:id archives and unarchives the group", async () => {
    const stateArchivedAt = async () =>
      ((await get(`/api/groups/${groupId}`, undefined, token)).json.group as Json).archivedAt;

    expect(await stateArchivedAt()).toBeNull(); // active on a fresh group

    const archived = await patch(`/api/groups/${groupId}`, { archived: true }, token);
    expect(archived.status).toBe(200);
    expect((archived.json.group as Json).archivedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    expect(await stateArchivedAt()).not.toBeNull();

    // A rename leaves it archived (key absent).
    await patch(`/api/groups/${groupId}`, { name: "Old Trip" }, token);
    expect(await stateArchivedAt()).not.toBeNull();

    const unarchived = await patch(`/api/groups/${groupId}`, { archived: false }, token);
    expect((unarchived.json.group as Json).archivedAt).toBeNull();
    expect(await stateArchivedAt()).toBeNull();
  });

  it("PATCH /api/groups/:id rejects a non-boolean archived → 400", async () => {
    expect((await patch(`/api/groups/${groupId}`, { archived: "yes" }, token)).status).toBe(400);
  });

  it("PATCH /api/groups/:id sets, keeps, and clears the default split", async () => {
    const stateSplit = async () =>
      ((await get(`/api/groups/${groupId}`, undefined, token)).json.group as Json).defaultSplit;

    expect(await stateSplit()).toBeNull(); // "split equally" on a fresh group

    const split = { weights: [{ memberId: a, weight: 60 }, { memberId: b, weight: 40 }] };
    const set = await patch(`/api/groups/${groupId}`, { defaultSplit: split }, token);
    expect(set.status).toBe(200);
    expect((set.json.group as Json).defaultSplit).toEqual(split);
    expect(await stateSplit()).toEqual(split);

    // A rename leaves it alone (key absent).
    await patch(`/api/groups/${groupId}`, { name: "Renamed" }, token);
    expect(await stateSplit()).toEqual(split);

    const cleared = await patch(`/api/groups/${groupId}`, { defaultSplit: null }, token);
    expect((cleared.json.group as Json).defaultSplit).toBeNull();
    expect(await stateSplit()).toBeNull();
  });

  it("PATCH /api/groups/:id sets, keeps, and clears the cover image (CHECKLIST.md \"Group cover image\")", async () => {
    const coverKeyState = async () =>
      ((await get(`/api/groups/${groupId}`, undefined, token)).json.group as Json).coverKey;
    const key = `groups/${groupId}/cover`;

    expect(await coverKeyState()).toBeNull(); // fresh group

    // committing without an uploaded object → 400
    expect((await patch(`/api/groups/${groupId}`, { coverImage: true }, token)).status).toBe(400);

    // stand in for the client's presigned upload, then commit
    await env.MEDIA.put(key, new Uint8Array([1, 2, 3]));
    const set = await patch(`/api/groups/${groupId}`, { coverImage: true }, token);
    expect(set.status).toBe(200);
    expect((set.json.group as Json).coverKey).toBe(key);
    expect(await coverKeyState()).toBe(key);

    // a rename leaves it alone
    await patch(`/api/groups/${groupId}`, { name: "Renamed" }, token);
    expect(await coverKeyState()).toBe(key);

    // removing clears the record and deletes the object
    const cleared = await patch(`/api/groups/${groupId}`, { coverImage: null }, token);
    expect((cleared.json.group as Json).coverKey).toBeNull();
    expect(await coverKeyState()).toBeNull();
    expect(await env.MEDIA.head(key)).toBeNull();
  });

  it("PATCH /api/groups/:id rejects a non-true/null coverImage → 400", async () => {
    expect((await patch(`/api/groups/${groupId}`, { coverImage: "yes" }, token)).status).toBe(400);
    expect((await patch(`/api/groups/${groupId}`, { coverImage: false }, token)).status).toBe(400);
  });

  it("PATCH /api/groups/:id rejects a default split that doesn't sum to 100, or names an unknown member", async () => {
    expect((await patch(`/api/groups/${groupId}`, {
      defaultSplit: { weights: [{ memberId: a, weight: 60 }, { memberId: b, weight: 30 }] },
    }, token)).status).toBe(400);

    expect((await patch(`/api/groups/${groupId}`, {
      defaultSplit: { weights: [{ memberId: a, weight: 50 }, { memberId: "ghost", weight: 50 }] },
    }, token)).status).toBe(404);

    expect((await patch(`/api/groups/${groupId}`, {
      defaultSplit: { weights: [{ memberId: a, weight: 100 }, { memberId: a, weight: 0 }] },
    }, token)).status).toBe(400);
  });

  it("PATCH a member renames them", async () => {
    const { status, json } = await patch(`/api/groups/${groupId}/members/${b}`, { displayName: "Benjamin" }, token);
    expect(status).toBe(200);
    expect(json.member).toEqual({ id: b, displayName: "Benjamin" });

    const state = await get(`/api/groups/${groupId}`, undefined, token);
    expect((state.json.members as Json[]).find((m) => m.id === b)?.displayName).toBe("Benjamin");
  });

  it("PATCH an unknown member → 404 NOT_FOUND", async () => {
    const { status, json } = await patch(`/api/groups/${groupId}/members/ghost`, { displayName: "x" }, token);
    expect(status).toBe(404);
    expect((json.error as Json).code).toBe("NOT_FOUND");
  });

  it("PATCH sets a member's UPI VPA independently of displayName, and an explicit null clears it", async () => {
    const { status, json } = await patch(`/api/groups/${groupId}/members/${b}`, { upiVpa: "ben@upi" }, token);
    expect(status).toBe(200);
    expect(json.member).toEqual({ id: b, displayName: "Ben", upiVpa: "ben@upi" });

    const state = await get(`/api/groups/${groupId}`, undefined, token);
    expect((state.json.members as Json[]).find((m) => m.id === b)).toMatchObject({ upiVpa: "ben@upi" });

    const cleared = await patch(`/api/groups/${groupId}/members/${b}`, { upiVpa: null }, token);
    expect(cleared.json.member).toEqual({ id: b, displayName: "Ben" });
  });

  it("PATCH rejects an empty-string upiVpa (use null to clear)", async () => {
    const { status } = await patch(`/api/groups/${groupId}/members/${b}`, { upiVpa: "" }, token);
    expect(status).toBe(400);
  });

  it("PATCH with neither displayName nor upiVpa → 400", async () => {
    expect((await patch(`/api/groups/${groupId}/members/${b}`, {}, token)).status).toBe(400);
  });

  it("DELETE a member with no activity → 204", async () => {
    const c = await addMember(groupId, "Cara", token);
    expect((await del(`/api/groups/${groupId}/members/${c}`, token)).status).toBe(204);
    const state = await get(`/api/groups/${groupId}`, undefined, token);
    expect((state.json.members as Json[]).map((m) => m.id)).not.toContain(c);
  });

  it("DELETE a member who's on an expense → 409 MEMBER_IN_USE", async () => {
    await post(
      `/api/groups/${groupId}/expenses`,
      {
        payers: [{ memberId: a, amountMinor: 1000 }], amountMinor: 1000, description: "x", date: "2026-01-01T12:00:00Z",
        splitType: "equal", splits: [{ memberId: a, amountMinor: 500 }, { memberId: b, amountMinor: 500 }],
      },
      token,
    );
    const { status, json } = await del(`/api/groups/${groupId}/members/${b}`, token);
    expect(status).toBe(409);
    expect((json.error as Json).code).toBe("MEMBER_IN_USE");
  });

  it("DELETE the last member → 409 MEMBER_IN_USE", async () => {
    const { groupId: solo, creatorId, token: soloToken } = await makeGroup();
    const { status } = await del(`/api/groups/${solo}/members/${creatorId}`, soloToken);
    expect(status).toBe(409);
  });

  it("DELETE an unknown member → 404", async () => {
    expect((await del(`/api/groups/${groupId}/members/ghost`, token)).status).toBe(404);
  });
});

describe("POST /api/groups/:groupId/report (Apple Guideline 1.2, SHIP_PLAN.md Track 3 §7)", () => {
  let groupId: string;
  let token: string;
  let memberId: string;

  beforeEach(async () => {
    const g = await makeGroup();
    groupId = g.groupId;
    token = g.token;
    memberId = g.creatorId;
  });

  it("files a group-level report", async () => {
    const { status, json } = await post(
      `/api/groups/${groupId}/report`,
      { targetType: "group", reason: "spam", details: "This whole group looks fake." },
      token,
    );
    expect(status).toBe(201);
    const report = json.report as Json;
    expect(report.groupId).toBe(groupId);
    expect(report.targetType).toBe("group");
    expect(report.targetId).toBeNull();
    expect(report.reason).toBe("spam");
    expect(report.details).toBe("This whole group looks fake.");
    expect(typeof report.id).toBe("string");
    expect(typeof report.createdAt).toBe("string");
  });

  it("files a member-level report", async () => {
    const { status, json } = await post(
      `/api/groups/${groupId}/report`,
      { targetType: "member", targetId: memberId, reason: "harassment" },
      token,
    );
    expect(status).toBe(201);
    const report = json.report as Json;
    expect(report.targetType).toBe("member");
    expect(report.targetId).toBe(memberId);
    expect(report.details).toBeNull();
  });

  it("requires targetId when targetType is member", async () => {
    const { status } = await post(`/api/groups/${groupId}/report`, { targetType: "member", reason: "spam" }, token);
    expect(status).toBe(400);
  });

  it("rejects an unknown targetType", async () => {
    const { status } = await post(`/api/groups/${groupId}/report`, { targetType: "banana", reason: "spam" }, token);
    expect(status).toBe(400);
  });

  it("requires a reason", async () => {
    const { status } = await post(`/api/groups/${groupId}/report`, { targetType: "group" }, token);
    expect(status).toBe(400);
  });

  it("404s an unknown group", async () => {
    const { status } = await post("/api/groups/does-not-exist/report", { targetType: "group", reason: "spam" });
    expect(status).toBe(404);
  });

  it("requires the group's token like any other group route", async () => {
    const { status } = await post(`/api/groups/${groupId}/report`, { targetType: "group", reason: "spam" });
    expect(status).toBe(403);
  });
});

describe("routing", () => {
  it("404s an unknown route", async () => {
    const { status } = await get("/api/nonsense");
    expect(status).toBe(404);
  });

  it("405s a known path with the wrong method", async () => {
    const { status } = await get("/api/groups"); // POST-only
    expect(status).toBe(405);
  });

  it("serves a noindex capability page at /g/:groupId with an app deep link", async () => {
    const res = await SELF.fetch(`${BASE}/g/somegroup`);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("text/html");
    expect(res.headers.get("X-Robots-Tag")).toBe("noindex");
    const body = await res.text();
    expect(body).toContain('<meta name="robots" content="noindex">');
    expect(body).toContain("clantab://g/somegroup");
  });

  it("carries ?token= through to the capability page's clantab:// link", async () => {
    const res = await SELF.fetch(`${BASE}/g/somegroup?token=tok123`);
    expect(res.status).toBe(200);
    expect(await res.text()).toContain("clantab://g/somegroup?token=tok123");
  });

  it("serves a noindex read-only balances page at /g/:groupId/balances", async () => {
    const { groupId, creatorId, token } = await makeGroup();
    const ben = await addMember(groupId, "Ben <script>", token);
    await post(`/api/groups/${groupId}/expenses`, {
      payers: [{ memberId: creatorId, amountMinor: 1000 }], amountMinor: 1000, description: "Dinner", date: "2026-01-01T12:00:00Z",
      splitType: "equal", splits: [{ memberId: creatorId, amountMinor: 500 }, { memberId: ben, amountMinor: 500 }],
    }, token);

    const res = await SELF.fetch(`${BASE}/g/${groupId}/balances?token=${token}`);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("text/html");
    expect(res.headers.get("X-Robots-Tag")).toBe("noindex");
    const body = await res.text();
    expect(body).toContain('<meta name="robots" content="noindex">');
    expect(body).toContain("Goa Trip");
    expect(body).toContain("Indra"); // is owed ₹5
    expect(body).toContain("is owed");
    expect(body).toContain("owes");
    expect(body).toContain("Settle up");
    // A member name is HTML-escaped, not injected.
    expect(body).not.toContain("<script>");
    expect(body).toContain("Ben &lt;script&gt;");
    // No write surface leaked.
    expect(body).not.toContain("clantab://");
  });

  it("the balances page needs a token when the group has one", async () => {
    const { groupId } = await makeGroup();
    const res = await SELF.fetch(`${BASE}/g/${groupId}/balances`);
    expect(res.status).toBe(403);
    expect(res.headers.get("X-Robots-Tag")).toBe("noindex");
  });

  it("mints a read-only view token that opens the balances page but no write route", async () => {
    const { groupId, creatorId, token } = await makeGroup();

    const minted = await post(`/api/groups/${groupId}/view-link`, {}, token);
    expect(minted.status).toBe(200);
    const viewToken = minted.json.viewToken as string;
    expect(viewToken).toMatch(/^[0-9A-Za-z_-]{22}$/);
    expect(viewToken).not.toBe(token); // distinct from the access token
    // Idempotent.
    expect((await post(`/api/groups/${groupId}/view-link`, {}, token)).json.viewToken).toBe(viewToken);

    // The view token opens the read-only page…
    expect((await SELF.fetch(`${BASE}/g/${groupId}/balances?token=${viewToken}`)).status).toBe(200);
    // …but not a write route.
    const write = await post(`/api/groups/${groupId}/expenses`, {
      payers: [{ memberId: creatorId, amountMinor: 100 }], amountMinor: 100, description: "x", date: "2026-01-01T12:00:00Z",
      splitType: "equal", splits: [{ memberId: creatorId, amountMinor: 100 }],
    }, viewToken);
    expect(write.status).toBe(403);
  });

  it("the balances page 404s for an unknown group", async () => {
    const res = await SELF.fetch(`${BASE}/g/nope/balances`);
    expect(res.status).toBe(404);
  });

  it("serves the apple-app-site-association as application/json, scoped to /g/*", async () => {
    const res = await SELF.fetch(`${BASE}/.well-known/apple-app-site-association`);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("application/json");
    const body = (await res.json()) as {
      applinks: { details: [{ appIDs: string[]; components: [{ "/": string }] }] };
    };
    expect(body.applinks.details[0].appIDs).toEqual(["UK652GNPP7.com.clantab.app"]);
    expect(body.applinks.details[0].components[0]["/"]).toBe("/g/*");
  });

  it("serves a plain page at /", async () => {
    const res = await SELF.fetch(`${BASE}/`);
    expect(res.status).toBe(200);
  });
});

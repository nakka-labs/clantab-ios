import { SELF } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";

const BASE = "https://api.test";

interface Json {
  [k: string]: unknown;
}

async function post(path: string, body: unknown): Promise<{ status: number; json: Json }> {
  const res = await SELF.fetch(`${BASE}${path}`, { method: "POST", body: JSON.stringify(body) });
  return { status: res.status, json: res.status === 204 ? {} : ((await res.json()) as Json) };
}

async function get(path: string): Promise<{ status: number; text: string; json: Json; robots: string | null }> {
  const res = await SELF.fetch(`${BASE}${path}`);
  const text = await res.text();
  return {
    status: res.status,
    text,
    json: text ? (JSON.parse(text) as Json) : {},
    robots: res.headers.get("X-Robots-Tag"),
  };
}

async function makeGroup(): Promise<{ groupId: string; joinCode: string; creatorId: string }> {
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
  };
}

async function addMember(groupId: string, displayName: string): Promise<string> {
  const { status, json } = await post(`/api/groups/${groupId}/members`, { displayName });
  expect(status).toBe(201);
  return (json.member as Json).id as string;
}

describe("POST /api/groups", () => {
  it("creates a group and returns ids, the creator, and the group summary with joinCode", async () => {
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
    const { groupId, joinCode, creatorId } = await makeGroup();
    const { status, json, robots } = await get(`/api/groups/${groupId}`);
    expect(status).toBe(200);
    expect(robots).toBe("noindex");
    expect(json.group).toMatchObject({ name: "Goa Trip", currency: "INR", joinCode });
    expect(json.members).toHaveLength(1);
    expect(json.expenses).toEqual([]);
    expect(json.settlements).toEqual([]);
    expect(json.balances).toEqual([{ memberId: creatorId, netMinor: 0 }]);
    expect(json.simplifiedSettlements).toEqual([]);
  });

  it("returns GROUP_NOT_FOUND for an unknown group", async () => {
    const { status, json } = await get("/api/groups/doesnotexist12345");
    expect(status).toBe(404);
    expect((json.error as Json).code).toBe("GROUP_NOT_FOUND");
  });
});

describe("GET /api/groups/resolve/:joinCode", () => {
  it("resolves a real code (case-insensitively) to its groupId", async () => {
    const { groupId, joinCode } = await makeGroup();
    const { status, json } = await get(`/api/groups/resolve/${joinCode.toLowerCase()}`);
    expect(status).toBe(200);
    expect(json.groupId).toBe(groupId);
  });

  it("returns a bare 404 (no body) for an unknown code", async () => {
    const { status, text } = await get("/api/groups/resolve/ZZZZZZ");
    expect(status).toBe(404);
    expect(text).toBe("");
  });

  it("rate-limits after 20 lookups in a window", async () => {
    await makeGroup();
    const statuses: number[] = [];
    for (let i = 0; i < 22; i++) {
      statuses.push((await get("/api/groups/resolve/ABCDEF")).status);
    }
    expect(statuses.slice(0, 20).every((s) => s === 404)).toBe(true);
    expect(statuses.at(-1)).toBe(429);
  });
});

describe("POST /api/groups/:groupId/members", () => {
  it("adds a member", async () => {
    const { groupId } = await makeGroup();
    const { status, json } = await post(`/api/groups/${groupId}/members`, { displayName: "Meera" });
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
  let a: string;
  let b: string;

  beforeEach(async () => {
    const g = await makeGroup();
    groupId = g.groupId;
    a = g.creatorId;
    b = await addMember(groupId, "Ben");
  });

  it("records an equal-split expense and updates balances", async () => {
    const { status, json } = await post(`/api/groups/${groupId}/expenses`, {
      payerId: a,
      amountMinor: 1000,
      description: "Lunch",
      date: "2026-01-01T12:00:00Z",
      splitType: "equal",
      splits: [
        { memberId: a, amountMinor: 500 },
        { memberId: b, amountMinor: 500 },
      ],
    });
    expect(status).toBe(201);
    expect(json.expense).toMatchObject({ description: "Lunch", amountMinor: 1000 });

    const state = await get(`/api/groups/${groupId}`);
    expect(state.json.balances).toEqual([
      { memberId: a, netMinor: 500 },
      { memberId: b, netMinor: -500 },
    ]);
    expect(state.json.simplifiedSettlements).toEqual([{ fromId: b, toId: a, amountMinor: 500 }]);
  });

  it("treats a repeated client id as an idempotent replay", async () => {
    const payload = {
      id: "11111111-1111-1111-1111-111111111111",
      payerId: a,
      amountMinor: 200,
      description: "Coffee",
      date: "2026-01-01T09:00:00Z",
      splitType: "equal",
      splits: [
        { memberId: a, amountMinor: 100 },
        { memberId: b, amountMinor: 100 },
      ],
    };
    const first = await post(`/api/groups/${groupId}/expenses`, payload);
    const second = await post(`/api/groups/${groupId}/expenses`, payload);
    expect(first.status).toBe(201);
    expect(second.status).toBe(201);
    expect(second.json.expense).toEqual(first.json.expense);

    const state = await get(`/api/groups/${groupId}`);
    expect(state.json.expenses).toHaveLength(1);
  });

  it("rejects splits that don't sum to the amount (SPLIT_MISMATCH)", async () => {
    const { status, json } = await post(`/api/groups/${groupId}/expenses`, {
      payerId: a,
      amountMinor: 1000,
      description: "x",
      date: "2026-01-01T12:00:00Z",
      splitType: "exact",
      splits: [
        { memberId: a, amountMinor: 400 },
        { memberId: b, amountMinor: 400 },
      ],
    });
    expect(status).toBe(400);
    expect((json.error as Json).code).toBe("SPLIT_MISMATCH");
  });

  it("rejects an unknown member (UNKNOWN_MEMBER)", async () => {
    const { status, json } = await post(`/api/groups/${groupId}/expenses`, {
      payerId: a,
      amountMinor: 100,
      description: "x",
      date: "2026-01-01T12:00:00Z",
      splitType: "equal",
      splits: [
        { memberId: a, amountMinor: 50 },
        { memberId: "ghost", amountMinor: 50 },
      ],
    });
    expect(status).toBe(400);
    expect((json.error as Json).code).toBe("UNKNOWN_MEMBER");
  });

  it("rejects a non-positive amount (INVALID_AMOUNT)", async () => {
    const { status, json } = await post(`/api/groups/${groupId}/expenses`, {
      payerId: a,
      amountMinor: 0,
      description: "x",
      date: "2026-01-01T12:00:00Z",
      splitType: "equal",
      splits: [{ memberId: a, amountMinor: 0 }],
    });
    expect(status).toBe(400);
    expect((json.error as Json).code).toBe("INVALID_AMOUNT");
  });

  it("rejects a bad splitType", async () => {
    const { status, json } = await post(`/api/groups/${groupId}/expenses`, {
      payerId: a,
      amountMinor: 100,
      description: "x",
      date: "2026-01-01T12:00:00Z",
      splitType: "percentage",
      splits: [{ memberId: a, amountMinor: 100 }],
    });
    expect(status).toBe(400);
    expect((json.error as Json).code).toBe("BAD_REQUEST");
  });
});

describe("POST /api/groups/:groupId/settlements", () => {
  it("records a settlement and clears the balance", async () => {
    const { groupId, creatorId: a } = await makeGroup();
    const b = await addMember(groupId, "Ben");
    await post(`/api/groups/${groupId}/expenses`, {
      payerId: a,
      amountMinor: 1000,
      description: "Lunch",
      date: "2026-01-01T12:00:00Z",
      splitType: "equal",
      splits: [
        { memberId: a, amountMinor: 500 },
        { memberId: b, amountMinor: 500 },
      ],
    });

    const { status, json } = await post(`/api/groups/${groupId}/settlements`, {
      fromId: b,
      toId: a,
      amountMinor: 500,
    });
    expect(status).toBe(201);
    expect(json.settlement).toMatchObject({ fromId: b, toId: a, amountMinor: 500 });

    const state = await get(`/api/groups/${groupId}`);
    expect(state.json.balances).toEqual([
      { memberId: a, netMinor: 0 },
      { memberId: b, netMinor: 0 },
    ]);
  });

  it("rejects a settlement to oneself", async () => {
    const { groupId, creatorId: a } = await makeGroup();
    const { status, json } = await post(`/api/groups/${groupId}/settlements`, {
      fromId: a,
      toId: a,
      amountMinor: 100,
    });
    expect(status).toBe(400);
    expect((json.error as Json).code).toBe("UNKNOWN_MEMBER");
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
});

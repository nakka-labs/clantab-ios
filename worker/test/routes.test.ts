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

async function put(path: string, body: unknown): Promise<{ status: number; json: Json }> {
  const res = await SELF.fetch(`${BASE}${path}`, { method: "PUT", body: JSON.stringify(body) });
  return { status: res.status, json: res.status === 204 ? {} : ((await res.json()) as Json) };
}

async function patch(path: string, body: unknown): Promise<{ status: number; json: Json }> {
  const res = await SELF.fetch(`${BASE}${path}`, { method: "PATCH", body: JSON.stringify(body) });
  return { status: res.status, json: res.status === 204 ? {} : ((await res.json()) as Json) };
}

async function del(path: string): Promise<{ status: number; json: Json }> {
  const res = await SELF.fetch(`${BASE}${path}`, { method: "DELETE" });
  const text = await res.text();
  return { status: res.status, json: text ? (JSON.parse(text) as Json) : {} };
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
    expect(json.balances).toEqual([]);
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
      { memberId: a, currency: "INR", netMinor: 500 },
      { memberId: b, currency: "INR", netMinor: -500 },
    ]);
    expect(state.json.simplifiedSettlements).toEqual([{ fromId: b, toId: a, amountMinor: 500, currency: "INR" }]);
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
      splitType: "weighted",
      splits: [{ memberId: a, amountMinor: 100 }],
    });
    expect(status).toBe(400);
    expect((json.error as Json).code).toBe("BAD_REQUEST");
  });

  it("records a percentage-split expense (splits already resolved to minor units)", async () => {
    const { status, json } = await post(`/api/groups/${groupId}/expenses`, {
      payerId: a,
      amountMinor: 1000,
      description: "Dinner (70/30)",
      date: "2026-01-01T20:00:00Z",
      splitType: "percentage",
      splits: [
        { memberId: a, amountMinor: 700 },
        { memberId: b, amountMinor: 300 },
      ],
    });
    expect(status).toBe(201);
    expect(json.expense).toMatchObject({ splitType: "percentage", amountMinor: 1000 });

    const state = await get(`/api/groups/${groupId}`);
    expect(state.json.balances).toEqual([
      { memberId: a, currency: "INR", netMinor: 300 },
      { memberId: b, currency: "INR", netMinor: -300 },
    ]);
  });

  it("still rejects percentage splits that don't sum to the amount (SPLIT_MISMATCH)", async () => {
    const { status, json } = await post(`/api/groups/${groupId}/expenses`, {
      payerId: a,
      amountMinor: 1000,
      description: "x",
      date: "2026-01-01T12:00:00Z",
      splitType: "percentage",
      splits: [
        { memberId: a, amountMinor: 700 },
        { memberId: b, amountMinor: 200 },
      ],
    });
    expect(status).toBe(400);
    expect((json.error as Json).code).toBe("SPLIT_MISMATCH");
  });

  it("round-trips a category and its icon", async () => {
    const { status, json } = await post(`/api/groups/${groupId}/expenses`, {
      payerId: a,
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
    });
    expect(status).toBe(201);
    expect(json.expense).toMatchObject({ category: "Transport", categoryIcon: "car" });

    const state = await get(`/api/groups/${groupId}`);
    const stored = (state.json.expenses as Json[]).find((e) => (e as Json).description === "Taxi");
    expect(stored).toMatchObject({ category: "Transport", categoryIcon: "car" });
  });

  it("omits the category keys entirely when no category is given", async () => {
    const { json } = await post(`/api/groups/${groupId}/expenses`, {
      payerId: a,
      amountMinor: 200,
      description: "Uncategorised",
      date: "2026-01-02T10:00:00Z",
      splitType: "equal",
      splits: [
        { memberId: a, amountMinor: 100 },
        { memberId: b, amountMinor: 100 },
      ],
    });
    expect(json.expense).not.toHaveProperty("category");
    expect(json.expense).not.toHaveProperty("categoryIcon");
  });

  it("defaults currency to the group's, and keeps a foreign currency in its own bucket", async () => {
    const base = { date: "2026-01-03T10:00:00Z", splitType: "equal" as const };
    // No currency → group default (INR).
    const inr = await post(`/api/groups/${groupId}/expenses`, {
      ...base, payerId: a, amountMinor: 1000, description: "INR lunch",
      splits: [{ memberId: a, amountMinor: 500 }, { memberId: b, amountMinor: 500 }],
    });
    expect((inr.json.expense as Json).currency).toBe("INR");
    // Explicit USD → its own ledger.
    await post(`/api/groups/${groupId}/expenses`, {
      ...base, payerId: b, amountMinor: 800, currency: "USD", description: "USD dinner",
      splits: [{ memberId: a, amountMinor: 400 }, { memberId: b, amountMinor: 400 }],
    });

    const state = await get(`/api/groups/${groupId}`);
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
    expect(state.json.balances).toEqual([]); // fully settled — no nonzero balances
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

describe("edit / delete", () => {
  let groupId: string;
  let a: string;
  let b: string;

  const equalSplit = (amount: number) => [
    { memberId: a, amountMinor: amount / 2 },
    { memberId: b, amountMinor: amount / 2 },
  ];

  beforeEach(async () => {
    const g = await makeGroup();
    groupId = g.groupId;
    a = g.creatorId;
    b = await addMember(groupId, "Ben");
  });

  async function addExpense(amount: number, description = "x"): Promise<string> {
    const { json } = await post(`/api/groups/${groupId}/expenses`, {
      payerId: a, amountMinor: amount, description, date: "2026-01-01T12:00:00Z",
      splitType: "equal", splits: equalSplit(amount),
    });
    return (json.expense as Json).id as string;
  }

  it("PUT replaces an expense and recomputes balances; created_at keeps feed order", async () => {
    const first = await addExpense(1000, "Lunch");
    await new Promise((r) => setTimeout(r, 2));
    const second = await addExpense(400, "Coffee");

    const { status, json } = await put(`/api/groups/${groupId}/expenses/${first}`, {
      payerId: b, amountMinor: 2000, description: "Lunch (fixed)", date: "2026-01-02T12:00:00Z",
      splitType: "equal", splits: [
        { memberId: a, amountMinor: 1000 },
        { memberId: b, amountMinor: 1000 },
      ],
    });
    expect(status).toBe(200);
    expect(json.expense).toMatchObject({ id: first, payerId: b, amountMinor: 2000, description: "Lunch (fixed)" });

    const state = await get(`/api/groups/${groupId}`);
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
    const { status, json } = await put(`/api/groups/${groupId}/expenses/ghost`, {
      payerId: a, amountMinor: 100, description: "x", date: "2026-01-01T12:00:00Z",
      splitType: "equal", splits: equalSplit(100),
    });
    expect(status).toBe(404);
    expect((json.error as Json).code).toBe("NOT_FOUND");
  });

  it("PUT still validates the splits", async () => {
    const id = await addExpense(1000);
    const { status, json } = await put(`/api/groups/${groupId}/expenses/${id}`, {
      payerId: a, amountMinor: 1000, description: "x", date: "2026-01-01T12:00:00Z",
      splitType: "exact", splits: [
        { memberId: a, amountMinor: 400 },
        { memberId: b, amountMinor: 400 },
      ],
    });
    expect(status).toBe(400);
    expect((json.error as Json).code).toBe("SPLIT_MISMATCH");
  });

  it("PUT rejects a body `id` field", async () => {
    const id = await addExpense(1000);
    const { status } = await put(`/api/groups/${groupId}/expenses/${id}`, {
      id: "spoof", payerId: a, amountMinor: 1000, description: "x", date: "2026-01-01T12:00:00Z",
      splitType: "equal", splits: equalSplit(1000),
    });
    expect(status).toBe(400);
  });

  it("DELETE removes an expense and its splits; balances update; idempotent", async () => {
    const id = await addExpense(1000);
    expect((await del(`/api/groups/${groupId}/expenses/${id}`)).status).toBe(204);

    const state = await get(`/api/groups/${groupId}`);
    expect(state.json.expenses).toEqual([]);
    expect(state.json.balances).toEqual([]);

    // second delete is a no-op success
    expect((await del(`/api/groups/${groupId}/expenses/${id}`)).status).toBe(204);
    expect((await del(`/api/groups/${groupId}/expenses/never-existed`)).status).toBe(204);
  });

  it("PUT / DELETE a settlement", async () => {
    await addExpense(1000, "Lunch");
    const { json } = await post(`/api/groups/${groupId}/settlements`, { fromId: b, toId: a, amountMinor: 200 });
    const sId = (json.settlement as Json).id as string;

    const upd = await put(`/api/groups/${groupId}/settlements/${sId}`, { fromId: b, toId: a, amountMinor: 500 });
    expect(upd.status).toBe(200);
    expect(upd.json.settlement).toMatchObject({ id: sId, amountMinor: 500 });

    let state = await get(`/api/groups/${groupId}`);
    expect(state.json.balances).toEqual([]); // 1000 lunch → b owes a 500; settled 500 → clear

    expect((await del(`/api/groups/${groupId}/settlements/${sId}`)).status).toBe(204);
    state = await get(`/api/groups/${groupId}`);
    expect(state.json.settlements).toEqual([]);
    expect(state.json.balances).toEqual([
      { memberId: a, currency: "INR", netMinor: 500 },
      { memberId: b, currency: "INR", netMinor: -500 },
    ]);
  });

  it("PUT to an unknown settlement id → 404 NOT_FOUND", async () => {
    const { status, json } = await put(`/api/groups/${groupId}/settlements/ghost`, {
      fromId: a, toId: b, amountMinor: 100,
    });
    expect(status).toBe(404);
    expect((json.error as Json).code).toBe("NOT_FOUND");
  });

  it("404s edit / delete on an unknown group", async () => {
    expect((await put("/api/groups/nope123/expenses/x", {
      payerId: "a", amountMinor: 1, description: "x", date: "2026-01-01T12:00:00Z", splitType: "equal", splits: [],
    })).status).toBe(404);
    expect((await del("/api/groups/nope123/expenses/x")).status).toBe(404);
  });
});

describe("group + member settings", () => {
  let groupId: string;
  let a: string;
  let b: string;

  beforeEach(async () => {
    const g = await makeGroup();
    groupId = g.groupId;
    a = g.creatorId;
    b = await addMember(groupId, "Ben");
  });

  it("PATCH /api/groups/:id renames and changes the default currency", async () => {
    const { status, json } = await patch(`/api/groups/${groupId}`, { name: "Goa 2.0", currency: "USD" });
    expect(status).toBe(200);
    expect(json.group).toMatchObject({ name: "Goa 2.0", currency: "USD" });

    const state = await get(`/api/groups/${groupId}`);
    expect(state.json.group).toMatchObject({ name: "Goa 2.0", currency: "USD" });
  });

  it("PATCH /api/groups/:id changing currency doesn't touch existing expenses", async () => {
    await post(`/api/groups/${groupId}/expenses`, {
      payerId: a, amountMinor: 1000, description: "INR lunch", date: "2026-01-01T12:00:00Z",
      splitType: "equal", splits: [{ memberId: a, amountMinor: 500 }, { memberId: b, amountMinor: 500 }],
    });
    await patch(`/api/groups/${groupId}`, { currency: "USD" });

    const state = await get(`/api/groups/${groupId}`);
    expect((state.json.expenses as Json[])[0]!.currency).toBe("INR");
  });

  it("PATCH /api/groups/:id with no fields → 400", async () => {
    expect((await patch(`/api/groups/${groupId}`, {})).status).toBe(400);
  });

  it("PATCH a member renames them", async () => {
    const { status, json } = await patch(`/api/groups/${groupId}/members/${b}`, { displayName: "Benjamin" });
    expect(status).toBe(200);
    expect(json.member).toEqual({ id: b, displayName: "Benjamin" });

    const state = await get(`/api/groups/${groupId}`);
    expect((state.json.members as Json[]).find((m) => m.id === b)?.displayName).toBe("Benjamin");
  });

  it("PATCH an unknown member → 404 NOT_FOUND", async () => {
    const { status, json } = await patch(`/api/groups/${groupId}/members/ghost`, { displayName: "x" });
    expect(status).toBe(404);
    expect((json.error as Json).code).toBe("NOT_FOUND");
  });

  it("DELETE a member with no activity → 204", async () => {
    const c = await addMember(groupId, "Cara");
    expect((await del(`/api/groups/${groupId}/members/${c}`)).status).toBe(204);
    const state = await get(`/api/groups/${groupId}`);
    expect((state.json.members as Json[]).map((m) => m.id)).not.toContain(c);
  });

  it("DELETE a member who's on an expense → 409 MEMBER_IN_USE", async () => {
    await post(`/api/groups/${groupId}/expenses`, {
      payerId: a, amountMinor: 1000, description: "x", date: "2026-01-01T12:00:00Z",
      splitType: "equal", splits: [{ memberId: a, amountMinor: 500 }, { memberId: b, amountMinor: 500 }],
    });
    const { status, json } = await del(`/api/groups/${groupId}/members/${b}`);
    expect(status).toBe(409);
    expect((json.error as Json).code).toBe("MEMBER_IN_USE");
  });

  it("DELETE the last member → 409 MEMBER_IN_USE", async () => {
    const { groupId: solo, creatorId } = await makeGroup();
    const { status } = await del(`/api/groups/${solo}/members/${creatorId}`);
    expect(status).toBe(409);
  });

  it("DELETE an unknown member → 404", async () => {
    expect((await del(`/api/groups/${groupId}/members/ghost`)).status).toBe(404);
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

  it("serves a plain page at /", async () => {
    const res = await SELF.fetch(`${BASE}/`);
    expect(res.status).toBe(200);
  });
});

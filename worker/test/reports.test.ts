import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";

function reports() {
  return env.REPORTS_DO.get(env.REPORTS_DO.idFromName("global"));
}

describe("ReportsDO", () => {
  it("file() stores a report and returns it with an id + ISO createdAt", async () => {
    const now = Date.UTC(2026, 0, 1, 12, 0, 0);
    const report = await reports().file(
      { groupId: "g1", targetType: "member", targetId: "m1", reason: "harassment", details: "Rude in the chat.", reportedBy: "apple:sub1" },
      "rep1",
      now,
    );

    expect(report).toEqual({
      id: "rep1",
      groupId: "g1",
      targetType: "member",
      targetId: "m1",
      reason: "harassment",
      details: "Rude in the chat.",
      reportedBy: "apple:sub1",
      createdAt: new Date(now).toISOString(),
    });
  });

  it("a group-level report has a null targetId", async () => {
    const report = await reports().file(
      { groupId: "g2", targetType: "group", targetId: null, reason: "spam", details: null, reportedBy: null },
      "rep2",
    );
    expect(report.targetType).toBe("group");
    expect(report.targetId).toBeNull();
    expect(report.reportedBy).toBeNull();
  });

  it("list() returns newest first", async () => {
    const store = reports();
    await store.file({ groupId: "g3", targetType: "group", targetId: null, reason: "a", details: null, reportedBy: null }, "a", 1000);
    await store.file({ groupId: "g3", targetType: "group", targetId: null, reason: "b", details: null, reportedBy: null }, "b", 2000);
    await store.file({ groupId: "g3", targetType: "group", targetId: null, reason: "c", details: null, reportedBy: null }, "c", 3000);

    const { reports: listed } = await store.list();
    const ours = listed.filter((r) => r.groupId === "g3");
    expect(ours.map((r) => r.id)).toEqual(["c", "b", "a"]);
  });

  it("list() respects the limit", async () => {
    const store = reports();
    // `ReportsDO` is a singleton shared across every test in this file —
    // real, strictly-increasing `Date.now()`-based timestamps (rather than
    // small fixed ints) keep these writes unambiguously the newest, so the
    // limit clips to exactly this batch regardless of write order between
    // test files.
    const base = Date.now();
    for (let i = 0; i < 5; i++) {
      await store.file(
        { groupId: "g4", targetType: "group", targetId: null, reason: String(i), details: null, reportedBy: null },
        `lim-${i}`,
        base + i,
      );
    }
    const { reports: limited } = await store.list(2);
    expect(limited).toHaveLength(2);
    expect(limited.map((r) => r.id)).toEqual(["lim-4", "lim-3"]);
  });
});

import { env, runInDurableObject } from "cloudflare:test";
import { describe, expect, it } from "vitest";

function user(sub: string) {
  return env.USER_DO.get(env.USER_DO.idFromName(sub));
}

describe("UserDO", () => {
  it("ensureExists is idempotent and flips exists()", async () => {
    const u = user("sub-exists");
    expect(await u.exists()).toBe(false);
    expect(await u.ensureExists("sub-exists")).toEqual({ created: true });
    expect(await u.ensureExists("sub-exists")).toEqual({ created: false });
    expect(await u.exists()).toBe(true);
  });

  it("addMembership → listGroups, newest first, groupIds + member id only", async () => {
    const u = user("sub-list");
    await u.ensureExists("sub-list");
    await u.addMembership("g1", "m1", "Ana");
    await new Promise((r) => setTimeout(r, 2)); // ensure added_at ordering
    await u.addMembership("g2", "m2", "Ana");

    expect(await u.listGroups()).toEqual({
      groups: [
        { groupId: "g2", memberId: "m2", displayName: "Ana", hidden: false },
        { groupId: "g1", memberId: "m1", displayName: "Ana", hidden: false },
      ],
    });
  });

  it("addMembership on the same group overwrites (one membership per group)", async () => {
    const u = user("sub-overwrite");
    await u.addMembership("g1", "m-old", "Old Name");
    await u.addMembership("g1", "m-new", "New Name");

    const { groups } = await u.listGroups();
    expect(groups).toEqual([{ groupId: "g1", memberId: "m-new", displayName: "New Name", hidden: false }]);
  });

  it("addMembership records hidden (private 1:1 tabs, CHECKLIST.md)", async () => {
    const u = user("sub-hidden");
    await u.addMembership("g1", "m1", "Ana", true);
    const { groups } = await u.listGroups();
    expect(groups).toEqual([{ groupId: "g1", memberId: "m1", displayName: "Ana", hidden: true }]);
  });

  it("migrate() upgrades a v1 memberships table (no hidden column) to v2", async () => {
    const u = user("sub-migrate");
    await u.ensureExists("sub-migrate");
    await u.addMembership("g1", "m1", "Ana");

    await runInDurableObject(u, (instance, state) => {
      const sql = state.storage.sql;
      // Rewind to the original v1 shape: no `hidden` column, schema_version 1.
      sql.exec("DROP TABLE memberships");
      sql.exec(`CREATE TABLE memberships (
        group_id     TEXT PRIMARY KEY,
        member_id    TEXT NOT NULL,
        display_name TEXT NOT NULL,
        added_at     INTEGER NOT NULL
      )`);
      sql.exec("INSERT INTO memberships VALUES ('g1', 'm1', 'Ana', 1)");
      sql.exec("UPDATE user_meta SET value = '1' WHERE key = 'schema_version'");
      (instance as unknown as { migrate(): void }).migrate();

      const version = sql
        .exec<{ value: string }>("SELECT value FROM user_meta WHERE key = 'schema_version'")
        .toArray()[0]?.value;
      expect(version).toBe("2");
    });

    // The legacy membership survived, gained hidden = false, and a fresh
    // addMembership (incl. a hidden one, for a private 1:1 tab) works.
    expect((await u.listGroups()).groups).toEqual([{ groupId: "g1", memberId: "m1", displayName: "Ana", hidden: false }]);
    await u.addMembership("g2", "m2", "Bob", true);
    expect((await u.listGroups()).groups).toContainEqual({ groupId: "g2", memberId: "m2", displayName: "Bob", hidden: true });
  });

  it("removeMembership drops one entry", async () => {
    const u = user("sub-remove");
    await u.addMembership("g1", "m1", "Ana");
    await u.addMembership("g2", "m2", "Ana");
    await u.removeMembership("g1");

    expect((await u.listGroups()).groups.map((g) => g.groupId)).toEqual(["g2"]);
  });

  it("stores and clears the Apple refresh token", async () => {
    const u = user("sub-rt");
    await u.ensureExists("sub-rt");
    expect(await u.refreshToken()).toBeNull();

    await u.setRefreshToken("rt-abc");
    expect(await u.refreshToken()).toBe("rt-abc");

    await u.setRefreshToken("rt-def"); // overwrites on re-sign-in
    expect(await u.refreshToken()).toBe("rt-def");

    await u.deleteAll();
    expect(await u.refreshToken()).toBeNull();
  });

  it("deleteAll wipes the identity — exists() goes false, groups empty", async () => {
    const u = user("sub-delete");
    await u.ensureExists("sub-delete");
    await u.addMembership("g1", "m1", "Ana");

    await u.deleteAll();

    expect(await u.exists()).toBe(false);
    expect((await u.listGroups()).groups).toEqual([]);
    // A fresh sign-in with the same Apple ID starts clean.
    expect(await u.ensureExists("sub-delete")).toEqual({ created: true });
  });

  // --- push notifications (FEATURE_BACKLOG.md "Push notifications") ------

  it("registerDevice is idempotent and lists every registered token", async () => {
    const u = user("sub-devices");
    expect(await u.deviceTokens()).toEqual([]);

    await u.registerDevice("tok-1", "ios");
    await u.registerDevice("tok-1", "ios"); // re-registration is a no-op
    await u.registerDevice("tok-2", "ios");

    expect((await u.deviceTokens()).sort()).toEqual(["tok-1", "tok-2"]);
  });

  it("unregisterDevice drops one token and is idempotent", async () => {
    const u = user("sub-unregister");
    await u.registerDevice("tok-1", "ios");
    await u.registerDevice("tok-2", "ios");

    await u.unregisterDevice("tok-1");
    expect(await u.deviceTokens()).toEqual(["tok-2"]);

    await u.unregisterDevice("tok-1"); // already gone — no error
    expect(await u.deviceTokens()).toEqual(["tok-2"]);
  });

  it("deleteAll clears registered devices too", async () => {
    const u = user("sub-delete-devices");
    await u.registerDevice("tok-1", "ios");

    await u.deleteAll();

    expect(await u.deviceTokens()).toEqual([]);
  });
});

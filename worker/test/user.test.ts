import { env } from "cloudflare:test";
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
        { groupId: "g2", memberId: "m2", displayName: "Ana" },
        { groupId: "g1", memberId: "m1", displayName: "Ana" },
      ],
    });
  });

  it("addMembership on the same group overwrites (one membership per group)", async () => {
    const u = user("sub-overwrite");
    await u.addMembership("g1", "m-old", "Old Name");
    await u.addMembership("g1", "m-new", "New Name");

    const { groups } = await u.listGroups();
    expect(groups).toEqual([{ groupId: "g1", memberId: "m-new", displayName: "New Name" }]);
  });

  it("removeMembership drops one entry", async () => {
    const u = user("sub-remove");
    await u.addMembership("g1", "m1", "Ana");
    await u.addMembership("g2", "m2", "Ana");
    await u.removeMembership("g1");

    expect((await u.listGroups()).groups.map((g) => g.groupId)).toEqual(["g2"]);
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
});

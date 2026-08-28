import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";

function registry() {
  return env.REGISTRY_DO.get(env.REGISTRY_DO.idFromName("registry"));
}

describe("RegistryDO", () => {
  it("reserve() returns a fresh 6-char code and resolve() round-trips it", async () => {
    const reg = registry();
    const code = await reg.reserve("group-abc");
    expect(code).toMatch(/^[A-Z2-9]{6}$/);
    expect(await reg.resolve(code, "1.1.1.1")).toEqual({ rateLimited: false, groupId: "group-abc" });
  });

  it("reserve() never hands out the same code twice", async () => {
    const reg = registry();
    const codes = new Set<string>();
    for (let i = 0; i < 50; i++) codes.add(await reg.reserve(`g-${i}`));
    expect(codes.size).toBe(50);
  });

  it("resolve() is case-insensitive and returns null for unknown codes", async () => {
    const reg = registry();
    const code = await reg.reserve("group-xyz");
    expect(await reg.resolve(code.toLowerCase(), "1.1.1.1")).toEqual({
      rateLimited: false,
      groupId: "group-xyz",
    });
    expect(await reg.resolve("NOPE00", "1.1.1.1")).toEqual({ rateLimited: false, groupId: null });
  });

  it("rate-limits a single IP to 20 lookups per window", async () => {
    const reg = registry();
    for (let i = 0; i < 20; i++) {
      expect((await reg.resolve("MISSNG", "9.9.9.9")).rateLimited).toBe(false);
    }
    expect((await reg.resolve("MISSNG", "9.9.9.9")).rateLimited).toBe(true);
    // A different IP is unaffected.
    expect((await reg.resolve("MISSNG", "8.8.8.8")).rateLimited).toBe(false);
  });
});

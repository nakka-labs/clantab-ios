import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { reserveJoinCode, resolveJoinCode } from "../src/lib/join-codes.ts";

describe("join codes (Workers KV, SHIP_PLAN.md Track 3 §3)", () => {
  it("reserveJoinCode() returns a fresh 6-char code and resolveJoinCode() round-trips it", async () => {
    const code = await reserveJoinCode(env.JOIN_CODES, "group-abc");
    expect(code).toMatch(/^[A-Z2-9]{6}$/);
    expect(await resolveJoinCode(env.JOIN_CODES, env.RESOLVE_RATE_LIMITER, code, "1.1.1.1")).toEqual({
      rateLimited: false,
      groupId: "group-abc",
    });
  });

  it("reserveJoinCode() never hands out the same code twice", async () => {
    const codes = new Set<string>();
    for (let i = 0; i < 50; i++) codes.add(await reserveJoinCode(env.JOIN_CODES, `g-${i}`));
    expect(codes.size).toBe(50);
  });

  it("resolveJoinCode() is case-insensitive and returns null for unknown codes", async () => {
    const code = await reserveJoinCode(env.JOIN_CODES, "group-xyz");
    expect(
      await resolveJoinCode(env.JOIN_CODES, env.RESOLVE_RATE_LIMITER, code.toLowerCase(), "1.1.1.1"),
    ).toEqual({ rateLimited: false, groupId: "group-xyz" });
    expect(await resolveJoinCode(env.JOIN_CODES, env.RESOLVE_RATE_LIMITER, "NOPE00", "1.1.1.1")).toEqual({
      rateLimited: false,
      groupId: null,
    });
  });

  it("rate-limits a single IP to 20 lookups per window", async () => {
    for (let i = 0; i < 20; i++) {
      expect(
        (await resolveJoinCode(env.JOIN_CODES, env.RESOLVE_RATE_LIMITER, "MISSNG", "9.9.9.9")).rateLimited,
      ).toBe(false);
    }
    expect(
      (await resolveJoinCode(env.JOIN_CODES, env.RESOLVE_RATE_LIMITER, "MISSNG", "9.9.9.9")).rateLimited,
    ).toBe(true);
    // A different IP is unaffected.
    expect(
      (await resolveJoinCode(env.JOIN_CODES, env.RESOLVE_RATE_LIMITER, "MISSNG", "8.8.8.8")).rateLimited,
    ).toBe(false);
  });
});

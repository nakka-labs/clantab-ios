import { newJoinCode } from "./ids.ts";

/** `resolveJoinCode` outcome. */
export type ResolveResult =
  | { rateLimited: true }
  | { rateLimited: false; groupId: string | null };

/**
 * Thin `joinCode → groupId` index, backed by Workers KV instead of a Durable
 * Object (`SHIP_PLAN.md` Track 3 §3). `RegistryDO` used to serialize every
 * group creation and every join-code lookup for the entire app through one
 * singleton instance — the one real architectural scaling ceiling
 * (`DESIGN.md` §3). KV has no such chokepoint: writes are write-once at group
 * creation, reads are globally distributed. KV's eventual consistency
 * (propagation up to ~60s) is a non-issue here — a code is looked up by a
 * friend well after the creator shares it, never in the same request.
 */

/**
 * Allocate a unique `joinCode` for `groupId`. Generates a candidate, checks
 * for a collision, regenerates if needed (`DESIGN.md` §1). Returns the
 * winning code.
 */
export async function reserveJoinCode(kv: KVNamespace, groupId: string): Promise<string> {
  for (let attempt = 0; attempt < 12; attempt++) {
    const code = newJoinCode();
    const taken = (await kv.get(code)) !== null;
    if (!taken) {
      await kv.put(code, groupId);
      return code;
    }
  }
  // 32^6 keyspace — twelve collisions in a row is effectively impossible.
  throw new Error("Could not allocate a unique join code");
}

/**
 * Resolve a typed code to its `groupId` (or `null`), unless the caller's IP is
 * rate-limited. The 20-per-minute cap moved from `RegistryDO`'s in-memory
 * counter (reset on DO eviction) to a real Cloudflare Rate Limiting binding
 * (`RESOLVE_RATE_LIMITER` in `wrangler.jsonc`) — durable across the Worker's
 * lifecycle, not just one instance's memory.
 */
export async function resolveJoinCode(
  kv: KVNamespace,
  limiter: RateLimit,
  code: string,
  clientIp: string,
): Promise<ResolveResult> {
  const { success } = await limiter.limit({ key: clientIp });
  if (!success) return { rateLimited: true };
  const groupId = await kv.get(code.toUpperCase());
  return { rateLimited: false, groupId };
}

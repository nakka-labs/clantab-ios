import { DurableObject } from "cloudflare:workers";
import { newJoinCode } from "./lib/ids.ts";
import { REGISTRY_SCHEMA } from "./lib/schema.ts";

/** `resolve` outcome — a plain object so it survives the RPC boundary intact. */
export type ResolveResult =
  | { rateLimited: true }
  | { rateLimited: false; groupId: string | null };

/**
 * The single well-known Durable Object (`idFromName("registry")`) holding a thin
 * `joinCode → groupId` index (`DESIGN.md` §1). Written once per group at creation,
 * read only when someone types a code instead of following a link.
 */
export class RegistryDO extends DurableObject {
  private readonly sql: SqlStorage;

  /** Per-IP fixed-window counter for `resolve` (`DESIGN.md` §8). In memory: a DO
   * eviction resets the window, which is acceptable for defence-in-depth given
   * the 32^6 keyspace already makes brute force impractical. */
  private readonly hits = new Map<string, { count: number; windowStart: number }>();
  private static readonly WINDOW_MS = 60_000;
  private static readonly MAX_PER_WINDOW = 20;

  constructor(ctx: DurableObjectState, env: Cloudflare.Env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    ctx.blockConcurrencyWhile(async () => {
      this.sql.exec(REGISTRY_SCHEMA);
    });
  }

  /**
   * Allocate a unique `joinCode` for `groupId`. Generates a candidate, checks for
   * a collision, regenerates if needed (`DESIGN.md` §1). Returns the winning code.
   */
  async reserve(groupId: string): Promise<string> {
    for (let attempt = 0; attempt < 12; attempt++) {
      const code = newJoinCode();
      const taken = this.sql.exec("SELECT 1 FROM join_codes WHERE code = ?", code).toArray().length > 0;
      if (!taken) {
        this.sql.exec(
          "INSERT INTO join_codes (code, group_id, created_at) VALUES (?, ?, ?)",
          code,
          groupId,
          Date.now(),
        );
        return code;
      }
    }
    // 32^6 keyspace — twelve collisions in a row is effectively impossible.
    throw new Error("Could not allocate a unique join code");
  }

  /** Resolve a typed code to its `groupId` (or `null`), unless the IP is rate-limited. */
  async resolve(code: string, clientIp: string): Promise<ResolveResult> {
    if (!this.withinRateLimit(clientIp)) {
      return { rateLimited: true };
    }
    const rows = this.sql
      .exec<{ group_id: string }>("SELECT group_id FROM join_codes WHERE code = ?", code.toUpperCase())
      .toArray();
    return { rateLimited: false, groupId: rows.length > 0 ? rows[0]!.group_id : null };
  }

  /** Fixed-window per-IP counter; returns false once the window's budget is spent. */
  private withinRateLimit(ip: string): boolean {
    const now = Date.now();
    const entry = this.hits.get(ip);
    if (entry === undefined || now - entry.windowStart >= RegistryDO.WINDOW_MS) {
      this.hits.set(ip, { count: 1, windowStart: now });
      return true;
    }
    entry.count += 1;
    return entry.count <= RegistryDO.MAX_PER_WINDOW;
  }
}

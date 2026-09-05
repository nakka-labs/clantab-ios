import { DurableObject } from "cloudflare:workers";
import { REPORTS_SCHEMA } from "./lib/schema.ts";

export type ReportTargetType = "group" | "member";

export interface Report {
  id: string;
  groupId: string;
  targetType: ReportTargetType;
  /** The member id being reported — `null` for a `"group"` report (the
   * group's own name/content in general, not one specific person). */
  targetId: string | null;
  reason: string;
  details: string | null;
  /** The composite `"<provider>:<sub>"` identity that filed it, or `null` —
   * reporting doesn't require being signed in (`requireGroup`'s usual
   * groupId/token possession is enough), so there isn't always one. */
  reportedBy: string | null;
  createdAt: string; // ISO 8601
}

type ReportRow = Record<string, SqlStorageValue> & {
  id: string;
  group_id: string;
  target_type: ReportTargetType;
  target_id: string | null;
  reason: string;
  details: string | null;
  reported_by: string | null;
  created_at: number;
};

/**
 * One global singleton (`idFromName("global")`) — the content-report log
 * Apple Guideline 1.2 requires for shared user-generated content
 * (`SHIP_PLAN.md` Track 3 §7). Deliberately global rather than per-group:
 * the owner needs one place to see every report, not a reason to poll each
 * group's own unguessable `groupId` on the chance something was filed there.
 * Low, human-moderation volume by design — nothing here needs to scale the
 * way `GroupDO`/`UserDO` do.
 */
export class ReportsDO extends DurableObject {
  private readonly sql: SqlStorage;

  constructor(ctx: DurableObjectState, env: Cloudflare.Env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    ctx.blockConcurrencyWhile(async () => {
      this.sql.exec(REPORTS_SCHEMA);
    });
  }

  async file(report: Omit<Report, "id" | "createdAt">, id: string, now: number = Date.now()): Promise<Report> {
    this.sql.exec(
      `INSERT INTO reports (id, group_id, target_type, target_id, reason, details, reported_by, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      id,
      report.groupId,
      report.targetType,
      report.targetId,
      report.reason,
      report.details,
      report.reportedBy,
      now,
    );
    return { ...report, id, createdAt: new Date(now).toISOString() };
  }

  /** Newest first, capped — a moderation log, not a paginated feed; nothing
   * needs more than the most recent few hundred at a time. */
  async list(limit: number = 200): Promise<{ reports: Report[] }> {
    const rows = this.sql
      .exec<ReportRow>("SELECT * FROM reports ORDER BY created_at DESC, rowid DESC LIMIT ?", limit)
      .toArray();
    return {
      reports: rows.map((r) => ({
        id: r.id,
        groupId: r.group_id,
        targetType: r.target_type,
        targetId: r.target_id,
        reason: r.reason,
        details: r.details,
        reportedBy: r.reported_by,
        createdAt: new Date(r.created_at).toISOString(),
      })),
    };
  }
}

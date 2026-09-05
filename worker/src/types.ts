// Wire request/response DTOs — the API contract in `DESIGN.md` §2, mirroring the
// iOS client's `ClanTabKit/Sources/ClanTabKit/Network/ClanTabWireTypes.swift`.

import type {
  Balance,
  Expense,
  Member,
  Settlement,
  SimplifiedSettlement,
  SplitType,
} from "./lib/types.ts";

export type { Balance, Expense, Member, Settlement, SimplifiedSettlement, SplitType };

/**
 * The subset of a group returned alongside its state. `joinCode` is included per
 * the decision recorded in `DESIGN.md` §12 (returned from `GET /api/groups/:groupId`
 * so it can be re-shared, not only shown once at creation).
 *
 * `accessToken` (`ACCESS_TOKEN_PLAN.md`) is likewise re-shareable, and for the
 * same reason: whoever's asking already holds a valid credential for this
 * group, so returning the *current* one exposes nothing they don't already
 * have. `null` only for a group created before this feature shipped and
 * never regenerated since — `requireGroup` treats that as open access, same
 * as before.
 */
export interface GroupSummary {
  name: string;
  currency: string;
  createdAt: string; // ISO 8601, seconds precision
  joinCode: string;
  accessToken: string | null;
}

// POST /api/groups
export interface CreateGroupRequest {
  name: string;
  currency: string;
  creatorDisplayName: string;
}
export interface CreateGroupResponse {
  groupId: string;
  joinCode: string;
  member: Member;
  group: GroupSummary;
}

// GET /api/groups/resolve/:joinCode
export interface ResolveJoinCodeResponse {
  groupId: string;
  /** The group's *current* access token (`ACCESS_TOKEN_PLAN.md` Part 3) —
   * always up to date even across a link rotation, since a code is resolved
   * fresh each time rather than bookmarked. `null` for a group that
   * predates this feature and has never regenerated its link. */
  accessToken: string | null;
}

// POST /api/groups/:groupId/members
export interface JoinGroupRequest {
  displayName: string;
}
export interface JoinGroupResponse {
  member: Member;
}

// GET /api/groups/:groupId
export interface GroupStateResponse {
  group: GroupSummary;
  members: Member[];
  expenses: Expense[];
  settlements: Settlement[];
  balances: Balance[];
  simplifiedSettlements: SimplifiedSettlement[];
}

// POST /api/groups/:groupId/expenses
export interface AddExpenseRequest {
  /** Optional client-generated UUID; a retry with the same id is a no-op replay. */
  id?: string;
  payerId: string;
  amountMinor: number;
  /** ISO 4217 code. Optional — defaults to the group's currency server-side. */
  currency?: string;
  description: string;
  date: string; // ISO 8601
  splitType: SplitType;
  splits: { memberId: string; amountMinor: number }[];
  category?: string;
  categoryIcon?: string;
}
export interface AddExpenseResponse {
  expense: Expense;
}

// POST /api/groups/:groupId/settlements
export interface AddSettlementRequest {
  id?: string;
  fromId: string;
  toId: string;
  amountMinor: number;
  /** ISO 4217 code. Optional — defaults to the group's currency server-side. */
  currency?: string;
}
export interface AddSettlementResponse {
  settlement: Settlement;
}

/** `{ "error": { "code", "message" } }` — every non-bare error response (`DESIGN.md` §2). */
export interface ErrorEnvelope {
  error: { code: string; message: string };
}

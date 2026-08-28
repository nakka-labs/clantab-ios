// Wire request/response DTOs — the API contract in `DESIGN.md` §2, mirroring the
// iOS client's `SquareKit/Sources/SquareKit/Network/SquarelyWireTypes.swift`.

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
 */
export interface GroupSummary {
  name: string;
  currency: string;
  createdAt: string; // ISO 8601, seconds precision
  joinCode: string;
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
  description: string;
  date: string; // ISO 8601
  splitType: SplitType;
  splits: { memberId: string; amountMinor: number }[];
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
}
export interface AddSettlementResponse {
  settlement: Settlement;
}

/** `{ "error": { "code", "message" } }` — every non-bare error response (`DESIGN.md` §2). */
export interface ErrorEnvelope {
  error: { code: string; message: string };
}

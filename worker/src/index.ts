import { GroupDO } from "./group-do.ts";
import { UserDO, type Membership } from "./user-do.ts";
import { ReportsDO } from "./reports-do.ts";
import { AppleAuthError, verifyAppleIdentityToken } from "./lib/apple-auth.ts";
import { GoogleAuthError, verifyGoogleIdentityToken } from "./lib/google-auth.ts";
import { exchangeAuthorizationCode, revokeToken, siwaConfigFromEnv } from "./lib/apple-oauth.ts";
import { b64urlEncode } from "./lib/base64url.ts";
import {
  BadRequestError,
  BareNotFoundError,
  ForbiddenError,
  GroupNotFoundError,
  HttpError,
  RateLimitedError,
  UnauthorizedError,
} from "./lib/errors.ts";
import { newGroupId, newRecordId, oneOnOneGroupId } from "./lib/ids.ts";
import { reserveJoinCode, resolveJoinCode } from "./lib/join-codes.ts";
import {
  assertReceiptKeysBelong,
  assertUploadAllowed,
  avatarKey,
  groupCoverKey,
  groupIdForKey,
  presignDownload,
  presignUpload,
  r2CredentialsFromEnv,
  receiptKey,
} from "./lib/media.ts";
import { newExpensePayload, notifyGroup, settlementPayload } from "./lib/notify.ts";
import { SessionError, mintSession, verifySession } from "./lib/session.ts";
import {
  assertPlainObject,
  optionalBoolean,
  optionalString,
  optionalStringOrNull,
  readJsonObject,
  rejectUnknownKeys,
  requireArray,
  requireInteger,
  requireString,
} from "./lib/parse.ts";
import { ValidationFailure } from "./lib/validation.ts";
import type { AddExpenseRequest, AddSettlementRequest } from "./types.ts";

export { GroupDO, UserDO, ReportsDO };

interface Env {
  GROUP_DO: DurableObjectNamespace<GroupDO>;
  USER_DO: DurableObjectNamespace<UserDO>;
  REPORTS_DO: DurableObjectNamespace<ReportsDO>;
  /** `joinCode → groupId` index (`SHIP_PLAN.md` Track 3 §3, `src/lib/join-codes.ts`). */
  JOIN_CODES: KVNamespace;
  /** Per-IP cap on `GET /api/groups/resolve/:joinCode` — 20/min, configured in
   * `wrangler.jsonc`'s `unsafe.bindings` (Workers Rate Limiting is still
   * `unsafe`-namespaced as of wrangler 4.35). */
  RESOLVE_RATE_LIMITER: RateLimit;
  /** HMAC key for session tokens (`ACCOUNTS_DESIGN.md` §3). A `vars` entry for
   * dev/tests; `wrangler secret put SESSION_SIGNING_KEY` overrides it in prod. */
  SESSION_SIGNING_KEY: string;
  /** The `aud` an Apple identity token must carry — the app's bundle id. */
  APPLE_AUDIENCE: string;
  /** The `aud` a Google identity token must carry — the iOS OAuth client id
   * from Google Cloud Console (`MANDATORY_LOGIN_PLAN.md` Part 1). */
  GOOGLE_AUDIENCE: string;
  /** Sign in with Apple OAuth secrets, for token revocation on account deletion
   * (`ACCOUNTS_DESIGN.md` §11). All four or none — revocation is a no-op until
   * they're set. */
  SIWA_SERVICES_ID?: string;
  SIWA_TEAM_ID?: string;
  SIWA_KEY_ID?: string;
  SIWA_PRIVATE_KEY?: string;
  /** APNs push (`FEATURE_BACKLOG.md` "Push notifications", `lib/apns.ts`).
   * All four required, plus `APNS_TOPIC` — a no-op (not an error) until
   * they're set (`NEXT_STEPS.md` Phase 6's owner action). */
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_PRIVATE_KEY?: string;
  APNS_TOPIC?: string;
  APNS_ENVIRONMENT?: string;
  /** Image storage (`CHECKLIST.md` "Image storage backend (R2)"). The `MEDIA`
   * bucket binding is used only for server-side deletes; uploads and views go
   * through short-lived presigned S3 URLs signed with the R2 API credentials
   * (`src/lib/media.ts`). `R2_BUCKET` is a `vars` entry (overridden to the
   * preview bucket in `worker/.dev.vars`); the three credential values are
   * secrets. All unset → `POST /api/media/presign` returns 503, same
   * "safe until configured" posture as `APNS_*`. */
  MEDIA: R2Bucket;
  R2_BUCKET: string;
  R2_ACCOUNT_ID?: string;
  R2_ACCESS_KEY_ID?: string;
  R2_SECRET_ACCESS_KEY?: string;
  /** Gates `GET /api/admin/reports` (`SHIP_PLAN.md` Track 3 §7, Apple
   * Guideline 1.2) — a bearer shared secret, not a real auth system; there's
   * exactly one owner. Unset means the endpoint refuses every request
   * (never "wide open by default"), same "safe until configured" posture
   * as `APNS_*`. `wrangler secret put ADMIN_TOKEN`. */
  ADMIN_TOKEN?: string;
}

type Params = Record<string, string>;
type Handler = (request: Request, env: Env, params: Params, ctx: ExecutionContext) => Promise<Response>;

interface Route {
  method: string;
  pattern: URLPattern;
  handler: Handler;
}

const ROUTES: Route[] = [
  route("POST", "/api/groups", handleCreateGroup),
  route("GET", "/api/groups/resolve/:joinCode", handleResolveJoinCode),
  route("POST", "/api/groups/:groupId/members", handleJoinGroup),
  route("PATCH", "/api/groups/:groupId/members/:memberId", handleRenameMember),
  route("DELETE", "/api/groups/:groupId/members/:memberId", handleRemoveMember),
  route("GET", "/api/groups/:groupId", handleGetState),
  route("PATCH", "/api/groups/:groupId", handleUpdateGroup),
  route("POST", "/api/groups/:groupId/regenerate-link", handleRegenerateLink),
  route("POST", "/api/groups/:groupId/view-link", handleViewLink),
  route("POST", "/api/groups/:groupId/expenses", handleAddExpense),
  route("PUT", "/api/groups/:groupId/expenses/:expenseId", handleUpdateExpense),
  route("DELETE", "/api/groups/:groupId/expenses/:expenseId", handleDeleteExpense),
  route("POST", "/api/groups/:groupId/expenses/:expenseId/restore", handleRestoreExpense),
  route("POST", "/api/groups/:groupId/settlements", handleAddSettlement),
  route("PUT", "/api/groups/:groupId/settlements/:settlementId", handleUpdateSettlement),
  route("DELETE", "/api/groups/:groupId/settlements/:settlementId", handleDeleteSettlement),
  route("POST", "/api/groups/:groupId/settlements/:settlementId/restore", handleRestoreSettlement),
  route("GET", "/api/groups/:groupId/trash", handleTrash),
  route("GET", "/api/groups/:groupId/claimable", handleClaimable),
  route("POST", "/api/groups/:groupId/members/:memberId/claim", handleClaim),
  route("POST", "/api/groups/:groupId/report", handleReport),
  route("POST", "/api/auth/apple", handleAuthApple),
  route("POST", "/api/auth/google", handleAuthGoogle),
  route("POST", "/api/auth/refresh", handleAuthRefresh),
  route("GET", "/api/auth/groups", handleAuthGroups),
  route("GET", "/api/auth/groups/balances", handleAuthGroupBalances),
  route("POST", "/api/auth/devices", handleRegisterDevice),
  route("DELETE", "/api/auth/devices/:token", handleUnregisterDevice),
  route("GET", "/api/auth/people", handleAuthPeople),
  route("GET", "/api/auth/friends", handleAuthFriends),
  route("POST", "/api/auth/friends/tab", handleEnsureFriendTab),
  route("DELETE", "/api/auth/account", handleAuthDeleteAccount),
  route("GET", "/api/auth/avatar", handleGetAvatar),
  route("PUT", "/api/auth/avatar", handleSetAvatar),
  route("DELETE", "/api/auth/avatar", handleClearAvatar),
  route("POST", "/api/media/presign", handleMediaPresign),
  route("GET", "/api/admin/reports", handleAdminReports),
  route("GET", "/g/:groupId/balances", handleBalancesPage),
  route("GET", "/g/:groupId", handleCapabilityPage),
  route("GET", "/.well-known/apple-app-site-association", handleAppleAppSiteAssociation),
  route("GET", "/", handleRoot),
];

function route(method: string, pathname: string, handler: Handler): Route {
  return { method, pattern: new URLPattern({ pathname }), handler };
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    let response: Response;
    try {
      response = await dispatch(request, env, ctx);
    } catch (err) {
      response = toErrorResponse(err);
    }
    if (new URL(request.url).pathname.startsWith("/api/")) {
      // A capability URL that gets indexed defeats its own security model (DESIGN.md §8).
      response.headers.set("X-Robots-Tag", "noindex");
    }
    return response;
  },
} satisfies ExportedHandler<Env>;

async function dispatch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const url = new URL(request.url);
  const matches = ROUTES.filter((r) => r.pattern.test(url));
  if (matches.length === 0) {
    return json(404, { error: { code: "NOT_FOUND", message: "No such route." } });
  }
  const matched = matches.find((r) => r.method === request.method);
  if (matched === undefined) {
    return json(405, {
      error: { code: "METHOD_NOT_ALLOWED", message: `${request.method} is not allowed on this route.` },
    });
  }
  const params = (matched.pattern.exec(url)?.pathname.groups ?? {}) as Params;
  return matched.handler(request, env, params, ctx);
}

// --- handlers ------------------------------------------------------------

async function handleCreateGroup(request: Request, env: Env): Promise<Response> {
  const body = await readJsonObject(request);
  rejectUnknownKeys(body, ["name", "currency", "creatorDisplayName"]);
  const name = requireString(body, "name");
  const currency = requireString(body, "currency");
  const creatorDisplayName = requireString(body, "creatorDisplayName");

  const groupId = newGroupId();
  const joinCode = await reserveJoinCode(env.JOIN_CODES, groupId);
  const { member, group } = await env.GROUP_DO.get(env.GROUP_DO.idFromName(groupId)).initGroup(
    name,
    currency,
    creatorDisplayName,
    joinCode,
  );

  return json(201, { groupId, joinCode, member, group });
}

async function handleResolveJoinCode(request: Request, env: Env, params: Params): Promise<Response> {
  const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const result = await resolveJoinCode(env.JOIN_CODES, env.RESOLVE_RATE_LIMITER, params.joinCode ?? "", ip);
  if (result.rateLimited) throw new RateLimitedError();
  if (result.groupId === null) throw new BareNotFoundError();
  // The *current* access_token, not whatever was live when the code was
  // reserved (ACCESS_TOKEN_PLAN.md Part 3) — a code is typed fresh each
  // time, not bookmarked, so it stays evergreen across a link rotation.
  const accessToken = await env.GROUP_DO.get(env.GROUP_DO.idFromName(result.groupId)).currentAccessToken();
  return json(200, { groupId: result.groupId, accessToken });
}

async function handleJoinGroup(request: Request, env: Env, params: Params): Promise<Response> {
  const group = await requireGroup(request, env, params.groupId ?? "");
  const body = await readJsonObject(request);
  rejectUnknownKeys(body, ["displayName"]);
  const { member } = await group.addMember(requireString(body, "displayName"));
  return json(201, { member });
}

async function handleGetState(request: Request, env: Env, params: Params): Promise<Response> {
  const group = await requireGroup(request, env, params.groupId ?? "");
  return json(200, await group.getState());
}

async function handleUpdateGroup(request: Request, env: Env, params: Params): Promise<Response> {
  const groupId = params.groupId ?? "";
  const group = await requireGroup(request, env, groupId);
  const body = await readJsonObject(request);
  rejectUnknownKeys(body, ["name", "currency", "emoji", "archived", "defaultSplit", "coverImage"]);
  const name = optionalString(body, "name");
  const currency = optionalString(body, "currency");
  // `null` clears the group's emoji; a string sets it; absent leaves it.
  const emoji = optionalStringOrNull(body, "emoji");
  // `true` archives, `false` unarchives, absent leaves it (`CHECKLIST.md`).
  const archived = optionalBoolean(body, "archived");
  // An object sets the default split, `null` clears it, absent leaves it.
  const defaultSplit = parseDefaultSplitPatch(body);
  // `true` commits a cover the client just uploaded to R2, `null` removes it,
  // absent leaves it (`CHECKLIST.md` "Group cover image").
  const coverImage = "coverImage" in body ? body.coverImage : undefined;
  if (coverImage !== undefined && coverImage !== null && coverImage !== true) {
    throw new BadRequestError('Field "coverImage" must be true (commit an uploaded cover) or null (remove it).');
  }
  if (
    name === undefined && currency === undefined && emoji === undefined &&
    archived === undefined && defaultSplit === undefined && coverImage === undefined
  ) {
    throw new BadRequestError('Provide "name", "currency", "emoji", "archived", "defaultSplit", and/or "coverImage".');
  }
  // A single emoji can be several code points (ZWJ sequences, skin tones,
  // flags); 16 is generous headroom while still rejecting a text label
  // pasted in. Content itself is the report mechanism's job, same as the
  // group name.
  if (typeof emoji === "string" && [...emoji].length > 16) {
    throw new BadRequestError('Field "emoji" must be a single emoji.');
  }

  // Resolve `coverImage` to the `coverKey` patch the DO stores. `true` →
  // verify the object is actually in the bucket first (same trust-but-verify
  // as the avatar commit).
  let coverKey: string | null | undefined;
  if (coverImage === true) {
    if ((await env.MEDIA.head(groupCoverKey(groupId))) === null) {
      throw new BadRequestError("No uploaded cover image found. Upload it via /api/media/presign first.");
    }
    coverKey = groupCoverKey(groupId);
  } else if (coverImage === null) {
    coverKey = null;
  }

  const result = await group.updateGroup({ name, currency, emoji, archived, defaultSplit, coverKey });
  if (!result.ok) return domainErrorResponse(result.error);
  // Deleted the record — now delete the object. Best-effort after the fact:
  // a leftover object is just wasted storage, never a correctness problem.
  if (coverImage === null) await env.MEDIA.delete(groupCoverKey(groupId));
  return json(200, result.value);
}

/** `undefined` (key absent) / `null` (clear) / a validated
 * `{ weights: [{ memberId, weight }] }` — positive integer weights, distinct
 * members, summing to 100 (`FEATURE_BACKLOG.md` "Default split config"). The
 * `GroupDO` checks the members actually exist. */
function parseDefaultSplitPatch(body: Record<string, unknown>): { weights: { memberId: string; weight: number }[] } | null | undefined {
  const raw = body.defaultSplit;
  if (raw === undefined) return undefined;
  if (raw === null) return null;
  assertPlainObject(raw, "defaultSplit");
  rejectUnknownKeys(raw, ["weights"]);
  const weights = requireArray(raw, "weights").map((entry, i) => {
    assertPlainObject(entry, `defaultSplit.weights[${i}]`);
    rejectUnknownKeys(entry, ["memberId", "weight"]);
    const weight = requireInteger(entry, "weight");
    if (weight <= 0) throw new BadRequestError(`Field "defaultSplit.weights[${i}].weight" must be positive.`);
    return { memberId: requireString(entry, "memberId"), weight };
  });
  if (weights.length === 0) throw new BadRequestError('Field "defaultSplit.weights" must not be empty.');
  if (new Set(weights.map((w) => w.memberId)).size !== weights.length) {
    throw new BadRequestError('Field "defaultSplit.weights" has a duplicate member.');
  }
  if (weights.reduce((sum, w) => sum + w.weight, 0) !== 100) {
    throw new BadRequestError('Field "defaultSplit.weights" must sum to 100.');
  }
  return { weights };
}

/**
 * Rotate the group's `access_token` (`ACCESS_TOKEN_PLAN.md`) — every
 * previously shared link/code stops working immediately. No special
 * "owner" tier: same flat trust model as every other group-data route
 * (`DESIGN.md` §8) — whoever currently has valid access can regenerate it.
 * Also the lazy-mint path for a group that predates this feature.
 */
async function handleRegenerateLink(request: Request, env: Env, params: Params): Promise<Response> {
  const group = await requireGroup(request, env, params.groupId ?? "");
  return json(200, await group.regenerateAccessToken());
}

/** Mint (or return the existing) read-only `view_token` for the group
 * (`FEATURE_BACKLOG.md` "Read-only web link for balances") — the app calls
 * this before sharing a `/g/:groupId/balances` link. Same auth as any other
 * group-data route; idempotent. */
async function handleViewLink(request: Request, env: Env, params: Params): Promise<Response> {
  const group = await requireGroup(request, env, params.groupId ?? "");
  return json(200, await group.ensureViewToken());
}

/** Rename a member and/or set their UPI VPA (`FEATURE_BACKLOG.md` "UPI deep
 * link on Settle Up") — at least one of the two fields is required. `upiVpa`
 * is an explicit JSON `null` to clear a previously-set one (an empty string
 * is rejected as invalid, same as everywhere else `optionalString` is used —
 * `null` is the one unambiguous way to say "nothing" here). */
async function handleRenameMember(request: Request, env: Env, params: Params): Promise<Response> {
  const group = await requireGroup(request, env, params.groupId ?? "");
  const body = await readJsonObject(request);
  rejectUnknownKeys(body, ["displayName", "upiVpa"]);
  const displayName = optionalString(body, "displayName");
  const upiVpa = optionalStringOrNull(body, "upiVpa");
  if (displayName === undefined && upiVpa === undefined) {
    throw new BadRequestError('Provide "displayName" and/or "upiVpa".');
  }
  const result = await group.updateMember(params.memberId ?? "", {
    displayName,
    // GroupDO's own patch shape uses "" to mean clear — translate here so
    // the wire's null-vs-absent distinction doesn't leak into the DO layer.
    upiVpa: upiVpa === undefined ? undefined : (upiVpa ?? ""),
  });
  return result.ok ? json(200, result.value) : domainErrorResponse(result.error);
}

async function handleRemoveMember(request: Request, env: Env, params: Params): Promise<Response> {
  const group = await requireGroup(request, env, params.groupId ?? "");
  const result = await group.removeMember(params.memberId ?? "");
  return result.ok ? new Response(null, { status: 204 }) : domainErrorResponse(result.error);
}

/** Parse an expense request body. `allowId` is true only for `POST` (the
 * idempotency key); on `PUT` the id lives in the path and a body `id` is rejected. */
function parseExpenseBody(body: Record<string, unknown>, allowId: boolean): AddExpenseRequest {
  rejectUnknownKeys(body, [
    ...(allowId ? ["id"] : []),
    "payerId",
    "amountMinor",
    "currency",
    "description",
    "date",
    "splitType",
    "splits",
    "items",
    "shares",
    "category",
    "categoryIcon",
    "attachments",
  ]);

  const splitType = requireString(body, "splitType");
  if (
    splitType !== "equal" &&
    splitType !== "exact" &&
    splitType !== "percentage" &&
    splitType !== "itemized" &&
    splitType !== "shares"
  ) {
    throw new BadRequestError('Field "splitType" must be "equal", "exact", "percentage", "itemized", or "shares".');
  }

  const splits = requireArray(body, "splits").map((raw, i) => {
    assertPlainObject(raw, `splits[${i}]`);
    rejectUnknownKeys(raw, ["memberId", "amountMinor"]);
    return { memberId: requireString(raw, "memberId"), amountMinor: requireInteger(raw, "amountMinor") };
  });

  // `items` and `splitType: "itemized"` are the same choice from opposite
  // sides — each requires the other, neither is valid alone.
  const hasItems = body.items !== undefined;
  if (splitType === "itemized" && !hasItems) {
    throw new BadRequestError('An "itemized" expense requires an "items" array.');
  }
  if (splitType !== "itemized" && hasItems) {
    throw new BadRequestError('Field "items" is only valid when "splitType" is "itemized".');
  }
  const items = hasItems
    ? requireArray(body, "items").map((raw, i) => {
        assertPlainObject(raw, `items[${i}]`);
        rejectUnknownKeys(raw, ["id", "name", "amountMinor", "participantIds"]);
        if (typeof raw.name !== "string") {
          throw new BadRequestError(`Field "items[${i}].name" must be a string.`);
        }
        return {
          id: requireString(raw, "id"),
          name: raw.name, // may be empty — the amount and the people are what matter
          amountMinor: requireInteger(raw, "amountMinor"),
          participantIds: requireArray(raw, "participantIds").map((p, j) => {
            if (typeof p !== "string") {
              throw new BadRequestError(`Field "items[${i}].participantIds[${j}]" must be a string.`);
            }
            return p;
          }),
        };
      })
    : undefined;

  // `shares` and `splitType: "shares"` require each other, same as items.
  const hasShares = body.shares !== undefined;
  if (splitType === "shares" && !hasShares) {
    throw new BadRequestError('A "shares" expense requires a "shares" array.');
  }
  if (splitType !== "shares" && hasShares) {
    throw new BadRequestError('Field "shares" is only valid when "splitType" is "shares".');
  }
  const shares = hasShares
    ? requireArray(body, "shares").map((raw, i) => {
        assertPlainObject(raw, `shares[${i}]`);
        rejectUnknownKeys(raw, ["memberId", "weight"]);
        return {
          memberId: requireString(raw, "memberId"),
          weight: requireInteger(raw, "weight"),
        };
      })
    : undefined;

  // `attachments` absent → leave the stored receipt list alone; `[]` → clear
  // it; a list → replace it. The route handler checks each key belongs to this
  // expense before it's stored.
  const attachments =
    body.attachments === undefined
      ? undefined
      : requireArray(body, "attachments").map((a, i) => {
          if (typeof a !== "string") {
            throw new BadRequestError(`Field "attachments[${i}]" must be a string.`);
          }
          return a;
        });

  return {
    id: allowId ? optionalString(body, "id") : undefined,
    payerId: requireString(body, "payerId"),
    amountMinor: requireInteger(body, "amountMinor"),
    currency: optionalString(body, "currency"),
    description: requireString(body, "description"),
    date: requireString(body, "date"),
    splitType,
    splits,
    items,
    shares,
    category: optionalString(body, "category"),
    categoryIcon: optionalString(body, "categoryIcon"),
    attachments,
  };
}

function parseSettlementBody(body: Record<string, unknown>, allowId: boolean): AddSettlementRequest {
  rejectUnknownKeys(body, [...(allowId ? ["id"] : []), "fromId", "toId", "amountMinor", "currency"]);
  return {
    id: allowId ? optionalString(body, "id") : undefined,
    fromId: requireString(body, "fromId"),
    toId: requireString(body, "toId"),
    amountMinor: requireInteger(body, "amountMinor"),
    currency: optionalString(body, "currency"),
  };
}

/** A `Result` domain error → HTTP status: `NOT_FOUND` → 404, `MEMBER_IN_USE` →
 * 409, everything else (bad split, unknown split member, …) → 400. */
function domainErrorResponse(error: { code: string; message: string }): Response {
  const status = error.code === "NOT_FOUND" ? 404 : error.code === "MEMBER_IN_USE" ? 409 : 400;
  return json(status, { error });
}

async function handleAddExpense(request: Request, env: Env, params: Params, ctx: ExecutionContext): Promise<Response> {
  const groupId = params.groupId ?? "";
  const group = await requireGroup(request, env, groupId);
  const req = parseExpenseBody(await readJsonObject(request), true);

  // Receipt keys must belong to this exact expense (`CHECKLIST.md`). On add the
  // client supplies the id it uploaded the receipts under; a bare add with
  // attachments but no id has nowhere valid for the keys to point.
  if (req.attachments && req.attachments.length > 0) {
    if (req.id === undefined) {
      throw new BadRequestError('An expense with "attachments" must also supply an "id".');
    }
    assertReceiptKeysBelong(req.attachments, groupId, req.id);
  }

  const result = await group.addExpense(req);
  if (!result.ok) return domainErrorResponse(result.error);

  const actingSub = await optionalSessionSub(request, env);
  if (actingSub !== undefined) {
    const expense = result.value.expense;
    ctx.waitUntil(
      (async () => {
        const state = await group.getState();
        const payerName = state.members.find((m) => m.id === expense.payerId)?.displayName ?? "Someone";
        await notifyGroup(
          env,
          group,
          actingSub,
          newExpensePayload({
            groupId,
            groupName: state.group.name,
            payerName,
            amountMinor: expense.amountMinor,
            currency: expense.currency,
            description: expense.description,
          }),
          { recipientBalance: { currency: expense.currency, balances: state.balances } },
        );
      })(),
    );
  }
  return json(201, result.value);
}

async function handleUpdateExpense(request: Request, env: Env, params: Params): Promise<Response> {
  const groupId = params.groupId ?? "";
  const expenseId = params.expenseId ?? "";
  const group = await requireGroup(request, env, groupId);
  const req = parseExpenseBody(await readJsonObject(request), false);

  if (req.attachments && req.attachments.length > 0) {
    assertReceiptKeysBelong(req.attachments, groupId, expenseId);
  }

  const result = await group.updateExpense(expenseId, req);
  if (!result.ok) return domainErrorResponse(result.error);
  // Delete the R2 objects for any receipts this edit dropped.
  await Promise.all(result.value.removedAttachments.map((key) => env.MEDIA.delete(key)));
  return json(200, { expense: result.value.expense });
}

async function handleDeleteExpense(request: Request, env: Env, params: Params): Promise<Response> {
  const group = await requireGroup(request, env, params.groupId ?? "");
  await group.deleteExpense(params.expenseId ?? "", deletedByParam(request));
  return new Response(null, { status: 204 });
}

/** Undo a soft delete (`FEATURE_BACKLOG.md` "Delete goes to trash") — the
 * fast-path "Undo" toast and the "Recently Deleted" screen's Restore both
 * call this. `NOT_FOUND` if the id doesn't exist or isn't currently trashed. */
async function handleRestoreExpense(request: Request, env: Env, params: Params): Promise<Response> {
  const group = await requireGroup(request, env, params.groupId ?? "");
  const result = await group.restoreExpense(params.expenseId ?? "");
  return result.ok ? json(200, result.value) : domainErrorResponse(result.error);
}

/** The app's Apple-assigned application identifier — `<TeamID>.<bundleId>`
 * (`CHECKLIST.md` "Custom domain + Universal Links"). Same team as the
 * `APNS_*` / `SIWA_*` secrets. Used only in the AASA below. */
const APPLE_APP_ID = "UK652GNPP7.com.clantab.app";

/**
 * `apple-app-site-association` for Universal Links (`CHECKLIST.md` "Custom
 * domain + Universal Links", `DESIGN.md` §1/§8). Scoped to `/g/*` so a group
 * invite link opens the app directly; nothing else on the host is claimed.
 * Must be `application/json`, HTTP 200, no redirect — served here for the
 * workers.dev host; the production `clantab.nakka.dev` copy lives in the
 * `nakka-labs/clantab-website` Pages repo (same JSON).
 */
function handleAppleAppSiteAssociation(): Promise<Response> {
  const body = {
    applinks: {
      details: [
        {
          appIDs: [APPLE_APP_ID],
          components: [{ "/": "/g/*", comment: "Group invite links open directly in the ClanTab app" }],
        },
      ],
    },
  };
  return Promise.resolve(
    new Response(JSON.stringify(body), {
      status: 200,
      headers: { "content-type": "application/json", "cache-control": "public, max-age=3600" },
    }),
  );
}

/**
 * The human-facing capability link (`DESIGN.md` §1/§8). With Universal Links
 * live (see `handleAppleAppSiteAssociation`), a device with the app installed
 * opens it directly and never sees this — it's the fallback for no app,
 * desktop, or a long-press "open in browser". The `clantab://` button carries
 * the `?token=` through so the manual path still reaches the group.
 * Deliberately reveals nothing about the group.
 */
function handleCapabilityPage(request: Request, _env: Env, params: Params): Promise<Response> {
  const groupId = params.groupId ?? "";
  const token = new URL(request.url).searchParams.get("token");
  const deepLink = token
    ? `clantab://g/${encodeURIComponent(groupId)}?token=${encodeURIComponent(token)}`
    : `clantab://g/${encodeURIComponent(groupId)}`;
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Open in ClanTab</title>
<style>
  body { font: 16px/1.5 -apple-system, system-ui, sans-serif; margin: 0; display: grid; place-items: center; min-height: 100vh; text-align: center; color: #1c1c1e; background: #f2f2f7; }
  main { padding: 2rem; max-width: 22rem; }
  h1 { font-size: 1.5rem; margin: 0 0 .25rem; }
  p { color: #636366; }
  a.btn { display: inline-block; margin-top: 1rem; padding: .75rem 1.5rem; border-radius: 999px; background: #0a84ff; color: #fff; text-decoration: none; font-weight: 600; }
</style>
</head>
<body>
<main>
  <h1>ClanTab 🧾</h1>
  <p>You've been invited to a shared expense group. Open this link on a device with the ClanTab app installed.</p>
  <a class="btn" href="${deepLink}">Open in ClanTab</a>
</main>
</body>
</html>`;
  return Promise.resolve(
    new Response(html, {
      status: 200,
      headers: { "content-type": "text/html; charset=utf-8", "X-Robots-Tag": "noindex" },
    }),
  );
}

function handleRoot(): Promise<Response> {
  return Promise.resolve(
    new Response("ClanTab API. See https://github.com/nakka-labs/clantab-ios\n", {
      status: 200,
      headers: { "content-type": "text/plain; charset=utf-8", "X-Robots-Tag": "noindex" },
    }),
  );
}

const HTML_ESCAPES: Record<string, string> = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };
function esc(s: string): string {
  return s.replace(/[&<>"']/g, (c) => HTML_ESCAPES[c]!);
}

/** `en-IN` locale money; drops a round amount's `.00`, matching the app's
 * `MoneyFormat`. */
function money(amountMinor: number, currency: string): string {
  try {
    const fractionDigits = amountMinor % 100 === 0 ? 0 : 2;
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency,
      minimumFractionDigits: fractionDigits,
      maximumFractionDigits: fractionDigits,
    }).format(amountMinor / 100);
  } catch {
    return `${(amountMinor / 100).toFixed(2)} ${currency}`;
  }
}

/**
 * A **read-only** web view of a group's balances and settle-up plan
 * (`FEATURE_BACKLOG.md` "Read-only web link for balances") — same
 * `groupId` (+ `?token=`) capability check as every group route, but it
 * only ever *reads*, so it's safe to hand to someone you don't want
 * writing to the ledger. `noindex`, like the capability page. Deliberately
 * shows names + amounts and nothing else (no expense list, no join code).
 */
async function handleBalancesPage(request: Request, env: Env, params: Params): Promise<Response> {
  let state: Awaited<ReturnType<GroupDO["getState"]>>;
  try {
    const group = await requireReadableGroup(request, env, params.groupId ?? "");
    state = await group.getState();
  } catch (err) {
    const status = err instanceof GroupNotFoundError ? 404 : err instanceof ForbiddenError ? 403 : 500;
    return htmlPage(status, "Not available", "<p>This link is no longer valid, or you don't have access to it.</p>");
  }

  const name = (id: string) => esc(state.members.find((m) => m.id === id)?.displayName ?? "Someone");
  const nonzero = state.balances.filter((b) => b.netMinor !== 0);

  const balanceRows = state.members
    .map((member) => {
      const bals = nonzero.filter((b) => b.memberId === member.id);
      if (bals.length === 0) return `<li><span>${esc(member.displayName)}</span><span class="settled">settled up</span></li>`;
      return bals
        .map((b) => {
          const owed = b.netMinor > 0;
          return `<li><span>${esc(member.displayName)}</span><span class="${owed ? "pos" : "neg"}">${
            owed ? "is owed" : "owes"
          } ${esc(money(Math.abs(b.netMinor), b.currency))}</span></li>`;
        })
        .join("");
    })
    .join("");

  const planRows = state.simplifiedSettlements
    .map((s) => `<li>${name(s.fromId)} &rarr; ${name(s.toId)} <strong>${esc(money(s.amountMinor, s.currency))}</strong></li>`)
    .join("");

  const heading = `${state.group.emoji ? esc(state.group.emoji) + " " : ""}${esc(state.group.name)}`;
  const body = `
  <h1>${heading}</h1>
  <p class="sub">View-only balances &middot; nobody can add or change anything from this link.</p>
  ${nonzero.length === 0 ? "<p>Everyone's settled up. 🎉</p>" : `<h2>Balances</h2><ul class="balances">${balanceRows}</ul>`}
  ${planRows ? `<h2>Settle up</h2><ul class="plan">${planRows}</ul>` : ""}`;
  return htmlPage(200, `${heading} — balances`, body);
}

function htmlPage(status: number, title: string, bodyHtml: string): Response {
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>${esc(title)}</title>
<style>
  body { font: 16px/1.5 -apple-system, system-ui, sans-serif; margin: 0; color: #1c1c1e; background: #f2f2f7; }
  main { max-width: 30rem; margin: 0 auto; padding: 2rem 1.25rem 3rem; }
  h1 { font-size: 1.5rem; margin: 0 0 .25rem; }
  h2 { font-size: .8rem; text-transform: uppercase; letter-spacing: .04em; color: #8e8e93; margin: 2rem 0 .5rem; }
  .sub { color: #636366; margin: 0 0 1rem; }
  ul { list-style: none; padding: 0; margin: 0; background: #fff; border-radius: .8rem; overflow: hidden; }
  li { display: flex; justify-content: space-between; gap: 1rem; padding: .75rem 1rem; border-top: 1px solid #e5e5ea; }
  li:first-child { border-top: 0; }
  .pos, .plan strong { color: #248a3d; }
  .neg { color: #d70015; }
  .settled { color: #8e8e93; }
  footer { color: #aeaeb2; font-size: .8rem; margin-top: 2rem; text-align: center; }
</style>
</head>
<body>
<main>
${bodyHtml}
<footer>Made with ClanTab</footer>
</main>
</body>
</html>`;
  return new Response(html, {
    status,
    headers: { "content-type": "text/html; charset=utf-8", "X-Robots-Tag": "noindex" },
  });
}

async function handleAddSettlement(
  request: Request,
  env: Env,
  params: Params,
  ctx: ExecutionContext,
): Promise<Response> {
  const groupId = params.groupId ?? "";
  const group = await requireGroup(request, env, groupId);
  const req = parseSettlementBody(await readJsonObject(request), true);
  const result = await group.addSettlement(req);
  if (!result.ok) return domainErrorResponse(result.error);

  const actingSub = await optionalSessionSub(request, env);
  if (actingSub !== undefined) {
    const settlement = result.value.settlement;
    ctx.waitUntil(
      (async () => {
        const state = await group.getState();
        const nameFor = (memberId: string) => state.members.find((m) => m.id === memberId)?.displayName ?? "Someone";
        await notifyGroup(
          env,
          group,
          actingSub,
          settlementPayload({
            groupId,
            groupName: state.group.name,
            fromName: nameFor(settlement.fromId),
            toName: nameFor(settlement.toId),
            amountMinor: settlement.amountMinor,
            currency: settlement.currency,
          }),
          { recipientBalance: { currency: settlement.currency, balances: state.balances } },
        );
      })(),
    );
  }
  return json(201, result.value);
}

async function handleUpdateSettlement(request: Request, env: Env, params: Params): Promise<Response> {
  const group = await requireGroup(request, env, params.groupId ?? "");
  const req = parseSettlementBody(await readJsonObject(request), false);
  const result = await group.updateSettlement(params.settlementId ?? "", req);
  return result.ok ? json(200, result.value) : domainErrorResponse(result.error);
}

async function handleDeleteSettlement(request: Request, env: Env, params: Params): Promise<Response> {
  const group = await requireGroup(request, env, params.groupId ?? "");
  await group.deleteSettlement(params.settlementId ?? "", deletedByParam(request));
  return new Response(null, { status: 204 });
}

/** See `handleRestoreExpense`. */
async function handleRestoreSettlement(request: Request, env: Env, params: Params): Promise<Response> {
  const group = await requireGroup(request, env, params.groupId ?? "");
  const result = await group.restoreSettlement(params.settlementId ?? "");
  return result.ok ? json(200, result.value) : domainErrorResponse(result.error);
}

/** Soft-deleted expenses/settlements for this group's "Recently Deleted"
 * screen (`FEATURE_BACKLOG.md`). */
async function handleTrash(request: Request, env: Env, params: Params): Promise<Response> {
  const group = await requireGroup(request, env, params.groupId ?? "");
  return json(200, await group.trash());
}

// --- accounts / auth (ACCOUNTS_DESIGN.md §5–§7, §11) --------------------

// Every identity is addressed everywhere (session tokens, `UserDO.idFromName`,
// `GroupDO.members.identity_sub`) by a provider-prefixed composite string —
// `"apple:" + sub` / `"google:" + sub` — never the bare provider `sub`. Two
// providers' subject ids are independent opaque strings with no cross-provider
// uniqueness guarantee; prefixing is what keeps an Apple and a Google identity
// from ever colliding (`MANDATORY_LOGIN_PLAN.md` Part 2).

async function handleAuthApple(request: Request, env: Env): Promise<Response> {
  const body = await readJsonObject(request);
  rejectUnknownKeys(body, ["identityToken", "authorizationCode"]);
  const identityToken = requireString(body, "identityToken");
  const authorizationCode = optionalString(body, "authorizationCode");

  let sub: string;
  try {
    ({ sub } = await verifyAppleIdentityToken(identityToken, { audience: env.APPLE_AUDIENCE }));
  } catch (err) {
    if (err instanceof AppleAuthError) {
      throw new UnauthorizedError("INVALID_APPLE_TOKEN", "That Apple sign-in could not be verified.");
    }
    throw err;
  }
  const identity = `apple:${sub}`;

  const user = env.USER_DO.get(env.USER_DO.idFromName(identity));
  await user.ensureExists(identity);

  // If the client sent an authorization code and the SIWA secrets are set,
  // trade it for a refresh token and stash it for revocation on deletion
  // (`ACCOUNTS_DESIGN.md` §11). Best-effort — a failure here never blocks sign-in.
  // Apple-only: Google's OAuth flow here doesn't request offline access, so
  // there's no equivalent refresh token to store for a Google identity.
  const siwa = siwaConfigFromEnv(env);
  if (authorizationCode !== undefined && siwa !== null) {
    try {
      const { refreshToken } = await exchangeAuthorizationCode(authorizationCode, siwa);
      await user.setRefreshToken(refreshToken);
    } catch (err) {
      console.error("Apple authorization-code exchange failed:", err);
    }
  }

  const [{ token, expiresAt }, { groups }] = await Promise.all([
    mintSession(identity, env.SESSION_SIGNING_KEY),
    user.listGroups(),
  ]);
  return json(200, { sessionToken: token, expiresAt, groups });
}

async function handleAuthGoogle(request: Request, env: Env): Promise<Response> {
  const body = await readJsonObject(request);
  rejectUnknownKeys(body, ["identityToken"]);
  const identityToken = requireString(body, "identityToken");

  let sub: string;
  try {
    ({ sub } = await verifyGoogleIdentityToken(identityToken, { audience: env.GOOGLE_AUDIENCE }));
  } catch (err) {
    if (err instanceof GoogleAuthError) {
      throw new UnauthorizedError("INVALID_GOOGLE_TOKEN", "That Google sign-in could not be verified.");
    }
    throw err;
  }
  const identity = `google:${sub}`;

  const user = env.USER_DO.get(env.USER_DO.idFromName(identity));
  await user.ensureExists(identity);

  const [{ token, expiresAt }, { groups }] = await Promise.all([
    mintSession(identity, env.SESSION_SIGNING_KEY),
    user.listGroups(),
  ]);
  return json(200, { sessionToken: token, expiresAt, groups });
}

async function handleAuthRefresh(request: Request, env: Env): Promise<Response> {
  const sub = await requireSession(request, env);
  const { token, expiresAt } = await mintSession(sub, env.SESSION_SIGNING_KEY);
  return json(200, { sessionToken: token, expiresAt });
}

async function handleAuthGroups(request: Request, env: Env): Promise<Response> {
  const sub = await requireSession(request, env);
  const { groups } = await env.USER_DO.get(env.USER_DO.idFromName(sub)).listGroups();
  return json(200, { groups });
}

/**
 * Dashboard fallback sync (`CHECKLIST.md` "Dashboard fallback sync for
 * missed/denied push"): the signed-in member's own per-currency balance in
 * every group they're in — one figure set per group, for the client to fold
 * into its local `KnownGroupsStore` cache when a push was missed or
 * notifications are denied. Same read-side concurrent fan-out shape as
 * `handleAuthPeople`; a group whose membership no longer checks out is
 * silently dropped.
 */
async function handleAuthGroupBalances(request: Request, env: Env): Promise<Response> {
  const sub = await requireSession(request, env);
  const { groups } = await env.USER_DO.get(env.USER_DO.idFromName(sub)).listGroups();

  const results = await Promise.all(
    groups.map(async (g) => {
      const view = await env.GROUP_DO.get(env.GROUP_DO.idFromName(g.groupId)).myBalances(sub, g.memberId);
      return view === null ? null : { groupId: g.groupId, balances: view.balances, archivedAt: view.archivedAt };
    }),
  );

  return json(200, { groups: results.filter((r) => r !== null) });
}

/** Register this device for push (`FEATURE_BACKLOG.md` "Push
 * notifications") — called on launch after the OS hands the app an APNs
 * device token. Idempotent; call it again any time the token changes. */
async function handleRegisterDevice(request: Request, env: Env): Promise<Response> {
  const sub = await requireSession(request, env);
  const body = await readJsonObject(request);
  rejectUnknownKeys(body, ["token", "platform"]);
  const token = requireString(body, "token");
  const platform = optionalString(body, "platform") ?? "ios";
  await env.USER_DO.get(env.USER_DO.idFromName(sub)).registerDevice(token, platform);
  return new Response(null, { status: 204 });
}

/** Forget a device token — called on sign-out so a shared/reset device
 * stops getting pushed for an identity no longer signed in on it. */
async function handleUnregisterDevice(request: Request, env: Env, params: Params): Promise<Response> {
  const sub = await requireSession(request, env);
  await env.USER_DO.get(env.USER_DO.idFromName(sub)).unregisterDevice(decodeURIComponent(params.token ?? ""));
  return new Response(null, { status: 204 });
}

/** Concurrently fetch each shared group's `peerSettlements` view for `sub` —
 * shared by `handleAuthPeople` and `handleAuthFriends` (`CHECKLIST.md`
 * "Worker: parallelize the handleAuthPeople fan-out loop"). Independent
 * `GroupDO` calls, so `Promise.all`; order preserved (`listGroups()` is
 * newest-first, which the `displayName` "first name wins" rule relies on). */
function fetchPeerViews(sub: string, groups: Membership[], env: Env) {
  return Promise.all(
    groups.map(async (g) => ({
      g,
      view: await env.GROUP_DO.get(env.GROUP_DO.idFromName(g.groupId)).peerSettlements(sub, g.memberId),
    })),
  );
}

/**
 * Cross-group settling (`FEATURE_BACKLOG.md`): for each linked person the caller
 * shares groups with, the net owed per currency and the per-group edges the
 * client settles one by one. A read-side aggregation — no cross-group ledger.
 * Nonzero balances only — a settled-up person has nothing to settle, so they
 * don't belong on this worklist (contrast `handleAuthFriends`, a directory of
 * every linked person regardless of balance).
 */
async function handleAuthPeople(request: Request, env: Env): Promise<Response> {
  const sub = await requireSession(request, env);
  const { groups } = await env.USER_DO.get(env.USER_DO.idFromName(sub)).listGroups();

  interface Agg {
    displayName: string;
    net: Map<string, number>;
    groups: {
      groupId: string;
      groupName: string;
      currency: string;
      amountMinor: number;
      youPay: boolean;
      myMemberId: string;
      theirMemberId: string;
    }[];
  }
  const byPerson = new Map<string, Agg>();

  const views = await fetchPeerViews(sub, groups, env);

  for (const { g, view } of views) {
    if (view === null) continue;
    for (const peer of view.peers) {
      if (peer.edges.length === 0) continue;
      let agg = byPerson.get(peer.sub);
      if (agg === undefined) {
        // groups come newest-first, so the first name we see is the most recent.
        agg = { displayName: peer.displayName, net: new Map(), groups: [] };
        byPerson.set(peer.sub, agg);
      }
      for (const edge of peer.edges) {
        agg.net.set(
          edge.currency,
          (agg.net.get(edge.currency) ?? 0) + (edge.youPay ? edge.amountMinor : -edge.amountMinor),
        );
        agg.groups.push({
          groupId: g.groupId,
          groupName: view.groupName,
          currency: edge.currency,
          amountMinor: edge.amountMinor,
          youPay: edge.youPay,
          myMemberId: g.memberId,
          theirMemberId: peer.memberId,
        });
      }
    }
  }

  const people = await Promise.all(
    [...byPerson.entries()]
      .filter(([, agg]) => agg.groups.length > 0)
      .map(async ([peerSub, agg]) => ({
        id: await opaquePersonId(peerSub),
        displayName: agg.displayName,
        net: [...agg.net.entries()]
          .filter(([, netMinor]) => netMinor !== 0)
          .map(([currency, netMinor]) => ({ currency, netMinor }))
          .sort((a, b) => a.currency.localeCompare(b.currency)),
        groups: agg.groups,
      })),
  );
  people.sort((a, b) => a.displayName.localeCompare(b.displayName));

  return json(200, { people });
}

/**
 * Friends directory (`CHECKLIST.md` "Friends/contacts list... + private 1:1
 * tabs"): every OTHER claimed member the caller shares a group with — formal
 * or a private 1:1 tab — regardless of balance. Unlike `handleAuthPeople` (a
 * settle-up worklist, nonzero-only), this is a directory: a settled friend
 * still appears. Each friend carries every shared group, each flagged
 * `hidden` or not, so the client can pick one — preferring an existing tab —
 * to prove the relationship when calling `POST /api/auth/friends/tab`.
 */
async function handleAuthFriends(request: Request, env: Env): Promise<Response> {
  const sub = await requireSession(request, env);
  const { groups } = await env.USER_DO.get(env.USER_DO.idFromName(sub)).listGroups();
  const views = await fetchPeerViews(sub, groups, env);

  interface FriendAgg {
    displayName: string;
    net: Map<string, number>;
    groups: { groupId: string; groupName: string; hidden: boolean; myMemberId: string; theirMemberId: string }[];
  }
  const byPerson = new Map<string, FriendAgg>();

  for (const { g, view } of views) {
    if (view === null) continue;
    for (const peer of view.peers) {
      let agg = byPerson.get(peer.sub);
      if (agg === undefined) {
        // groups come newest-first, so the first name we see is the most recent.
        agg = { displayName: peer.displayName, net: new Map(), groups: [] };
        byPerson.set(peer.sub, agg);
      }
      agg.groups.push({
        groupId: g.groupId,
        groupName: view.groupName,
        hidden: view.hidden,
        myMemberId: g.memberId,
        theirMemberId: peer.memberId,
      });
      for (const edge of peer.edges) {
        agg.net.set(
          edge.currency,
          (agg.net.get(edge.currency) ?? 0) + (edge.youPay ? edge.amountMinor : -edge.amountMinor),
        );
      }
    }
  }

  const friends = await Promise.all(
    [...byPerson.entries()].map(async ([peerSub, agg]) => ({
      id: await opaquePersonId(peerSub),
      displayName: agg.displayName,
      net: [...agg.net.entries()]
        .filter(([, netMinor]) => netMinor !== 0)
        .map(([currency, netMinor]) => ({ currency, netMinor }))
        .sort((a, b) => a.currency.localeCompare(b.currency)),
      groups: agg.groups,
    })),
  );
  friends.sort((a, b) => a.displayName.localeCompare(b.displayName));

  return json(200, { friends });
}

/**
 * Ensure the private 1:1 tab between the caller and a friend exists, and
 * return it — a hidden two-person group created lazily the first time either
 * side calls this, idempotent after (`CHECKLIST.md` "Friends/contacts list...
 * + private 1:1 tabs"). No invite/join ceremony: both members are claimed
 * directly, server-side.
 *
 * `groupId`/`theirMemberId` is any group the caller shares with that friend
 * (from `GET /api/auth/friends`, which prefers an existing tab if there is
 * one) — proof the two are actually connected: the caller must have a
 * claimed member there, and `theirMemberId` must resolve to a *different*
 * claimed identity. A group proves itself, so passing the tab's own id (once
 * it exists) works too — no separate lookup needed to just re-open it.
 */
async function handleEnsureFriendTab(request: Request, env: Env): Promise<Response> {
  const sub = await requireSession(request, env);
  const body = await readJsonObject(request);
  rejectUnknownKeys(body, ["groupId", "theirMemberId", "myDisplayName", "theirDisplayName", "currency"]);
  const groupId = requireString(body, "groupId");
  const theirMemberId = requireString(body, "theirMemberId");
  const myDisplayName = requireString(body, "myDisplayName");
  const theirDisplayName = requireString(body, "theirDisplayName");
  const currency = requireString(body, "currency");

  const sharedGroup = env.GROUP_DO.get(env.GROUP_DO.idFromName(groupId));
  if (!(await sharedGroup.exists())) throw new GroupNotFoundError();
  if (!(await sharedGroup.hasClaimedMember(sub))) throw new ForbiddenError();

  const { sub: peerSub } = await sharedGroup.memberIdentity(theirMemberId);
  if (peerSub === null) throw new BadRequestError('"theirMemberId" isn\'t a linked account.');
  if (peerSub === sub) throw new BadRequestError("You can't start a private tab with yourself.");

  const tabGroupId = await oneOnOneGroupId(sub, peerSub);
  const tabGroup = env.GROUP_DO.get(env.GROUP_DO.idFromName(tabGroupId));

  if (!(await tabGroup.exists())) {
    const joinCode = await reserveJoinCode(env.JOIN_CODES, tabGroupId);
    const me = env.USER_DO.get(env.USER_DO.idFromName(sub));
    const peer = env.USER_DO.get(env.USER_DO.idFromName(peerSub));
    // Seed each side's avatar from their identity, same as a normal claim
    // (`handleClaim`).
    const myAvatarKey = (await me.hasAvatar()) ? await avatarKey(sub) : null;
    const peerAvatarKey = (await peer.hasAvatar()) ? await avatarKey(peerSub) : null;

    const { member: mine } = await tabGroup.initGroup("Private tab", currency, myDisplayName, joinCode);
    await tabGroup.claim(mine.id, sub, myAvatarKey);
    const { member: theirs } = await tabGroup.addMember(theirDisplayName);
    await tabGroup.claim(theirs.id, peerSub, peerAvatarKey);
    await tabGroup.markHidden();

    // `GroupDO` is authoritative; both `UserDO` indexes are self-healing
    // caches updated after the fact, same as `handleClaim`. This is what
    // makes the tab reachable from *either* side with no invite step: the
    // peer's own `GET /api/auth/friends` / `GET /api/auth/groups` now lists
    // it too.
    await Promise.all([
      me.addMembership(tabGroupId, mine.id, myDisplayName, true),
      peer.addMembership(tabGroupId, theirs.id, theirDisplayName, true),
    ]);
  }

  const accessToken = await tabGroup.currentAccessToken();
  return json(200, { groupId: tabGroupId, accessToken });
}

/** A stable, non-reversible client-facing id for a person — never expose the
 * underlying identity string. */
async function opaquePersonId(sub: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`clantab-person:${sub}`));
  return b64urlEncode(new Uint8Array(digest).slice(0, 9));
}

async function handleAuthDeleteAccount(request: Request, env: Env): Promise<Response> {
  const sub = await requireSession(request, env);
  const user = env.USER_DO.get(env.USER_DO.idFromName(sub));

  // Revoke the Apple refresh token first (Apple Guideline 5.1.1(v)) — best
  // effort, so Apple being unreachable never blocks the user's deletion.
  const siwa = siwaConfigFromEnv(env);
  const refreshToken = await user.refreshToken();
  if (siwa !== null && refreshToken !== null) {
    try {
      await revokeToken(refreshToken, siwa);
    } catch (err) {
      console.error("Apple token revocation failed during account deletion:", err);
    }
  }

  const { groups } = await user.listGroups();
  // Release every claimed membership back to a placeholder (also clears that
  // member's `avatar_key`), then wipe the index.
  for (const g of groups) {
    await env.GROUP_DO.get(env.GROUP_DO.idFromName(g.groupId)).unclaim(g.memberId, sub);
  }
  // Remove the profile photo too, if any — nothing else references this key.
  if (await user.hasAvatar()) {
    await env.MEDIA.delete(await avatarKey(sub));
  }
  await user.deleteAll();
  return new Response(null, { status: 204 });
}

async function handleClaimable(request: Request, env: Env, params: Params): Promise<Response> {
  await requireSession(request, env);
  const group = await requireGroup(request, env, params.groupId ?? "");
  return json(200, await group.claimable());
}

async function handleClaim(request: Request, env: Env, params: Params): Promise<Response> {
  const sub = await requireSession(request, env);
  const groupId = params.groupId ?? "";
  const group = await requireGroup(request, env, groupId);
  const user = env.USER_DO.get(env.USER_DO.idFromName(sub));

  // Seed the new member's `avatar_key` from this identity's photo, if any
  // (`CHECKLIST.md` "Profile photos") — one write, no follow-up fan-out to this
  // group needed.
  const avatarKeyForSub = (await user.hasAvatar()) ? await avatarKey(sub) : null;
  const result = await group.claim(params.memberId ?? "", sub, avatarKeyForSub);
  if (!result.ok) {
    return json(result.error.code === "UNKNOWN_MEMBER" ? 404 : 409, { error: result.error });
  }
  // `GroupDO` is authoritative; the `UserDO` index is a self-healing cache we
  // update after the fact (a miss just briefly hides one group from
  // `GET /api/auth/groups`). ACCOUNTS_DESIGN.md §2.
  await user.addMembership(groupId, result.value.member.id, result.value.member.displayName);
  return json(200, result.value);
}

/**
 * Mark this identity as having (or no longer having) a profile photo
 * (`CHECKLIST.md` "Profile photos"). The client uploads the image to its
 * `avatars/<hash>` key via `POST /api/media/presign` first, then `PUT`s here to
 * commit; `DELETE` removes both the flag and the R2 object. Either way the new
 * state is fanned out to `members.avatar_key` in every group this identity has
 * claimed, so other members see the change without any identity-subject leak.
 */
/** This identity's current profile-photo key, or `null` — for the client to
 * render "my photo" in Settings on a cold launch (`CHECKLIST.md`). The key is
 * deterministic from the subject; the `UserDO` flag is what says it's real. */
async function handleGetAvatar(request: Request, env: Env): Promise<Response> {
  const sub = await requireSession(request, env);
  const has = await env.USER_DO.get(env.USER_DO.idFromName(sub)).hasAvatar();
  return json(200, { key: has ? await avatarKey(sub) : null });
}

async function handleSetAvatar(request: Request, env: Env): Promise<Response> {
  const sub = await requireSession(request, env);
  const key = await avatarKey(sub);

  // Trust-but-verify: the object must actually be in the bucket. Guards against
  // a client marking a photo it never uploaded, which would fan a 404ing key
  // across every group.
  if ((await env.MEDIA.head(key)) === null) {
    throw new BadRequestError("No uploaded image found. Upload it via /api/media/presign first.");
  }
  await fanOutAvatar(env, sub, key);
  return new Response(null, { status: 204 });
}

async function handleClearAvatar(request: Request, env: Env): Promise<Response> {
  const sub = await requireSession(request, env);
  await fanOutAvatar(env, sub, null);
  await env.MEDIA.delete(await avatarKey(sub));
  return new Response(null, { status: 204 });
}

/** Set (`key`) or clear (`null`) this identity's `avatar_uploaded_at` flag and
 * push the same to `members.avatar_key` in each of its groups. Group fan-out is
 * concurrent — independent `GroupDO`s, same shape as `handleAuthPeople`. */
async function fanOutAvatar(env: Env, sub: string, key: string | null): Promise<void> {
  const user = env.USER_DO.get(env.USER_DO.idFromName(sub));
  await user.setAvatarUploaded(key !== null);
  const { groups } = await user.listGroups();
  await Promise.all(
    groups.map((g) => env.GROUP_DO.get(env.GROUP_DO.idFromName(g.groupId)).setMemberAvatar(sub, key)),
  );
}

/**
 * File a content report (Apple Guideline 1.2, `SHIP_PLAN.md` Track 3 §7) —
 * a group's name/content in general (`targetType: "group"`, no `targetId`),
 * or one specific member (`targetType: "member"`, that member's id). Same
 * groupId-possession trust model as every other group route; reporting
 * doesn't itself require being signed in, so `reportedBy` is best-effort
 * attribution, not a requirement.
 */
async function handleReport(request: Request, env: Env, params: Params): Promise<Response> {
  const groupId = params.groupId ?? "";
  await requireGroup(request, env, groupId);
  const body = await readJsonObject(request);
  rejectUnknownKeys(body, ["targetType", "targetId", "reason", "details"]);
  const targetType = requireString(body, "targetType");
  if (targetType !== "group" && targetType !== "member") {
    throw new BadRequestError('Field "targetType" must be "group" or "member".');
  }
  const targetId = optionalString(body, "targetId") ?? null;
  if (targetType === "member" && targetId === null) {
    throw new BadRequestError('Field "targetId" is required when targetType is "member".');
  }
  const reason = requireString(body, "reason");
  const details = optionalString(body, "details") ?? null;

  const reportedBy = (await optionalSessionSub(request, env)) ?? null;
  const report = await env.REPORTS_DO
    .get(env.REPORTS_DO.idFromName("global"))
    .file({ groupId, targetType, targetId, reason, details, reportedBy }, newRecordId());
  return json(201, { report });
}

/**
 * Hand the client a short-lived presigned S3 URL for one image, so R2 does the
 * byte transfer and the Worker's compute cost stays flat regardless of image
 * volume (`CHECKLIST.md` "Image storage backend (R2)").
 *
 * `operation: "upload"` → a `PUT` URL for a new object; the key is derived
 * server-side from `purpose` (+ `groupId` / `expenseId`), never taken from the
 * client, and the declared `contentType` / `contentLength` are validated and
 * signed into the URL so the actual PUT can't deviate. `operation: "view"` → a
 * `GET` URL for an existing `key`.
 *
 * Auth: a valid session, plus — for anything group-scoped — the same
 * `requireGroup` capability check as every other group route (a matching
 * `?token=` or a claimed membership). Avatars are session-only (the key is the
 * caller's own) and viewable by any signed-in user.
 */
async function handleMediaPresign(request: Request, env: Env): Promise<Response> {
  const creds = r2CredentialsFromEnv(env);
  if (creds === null) {
    throw new HttpError(503, "NOT_CONFIGURED", "Image uploads aren't available yet.");
  }
  const sub = await requireSession(request, env);
  const body = await readJsonObject(request);
  rejectUnknownKeys(body, ["operation", "purpose", "groupId", "expenseId", "key", "contentType", "contentLength"]);

  const operation = requireString(body, "operation");
  if (operation === "view") {
    const key = requireString(body, "key");
    const groupId = groupIdForKey(key);
    if (groupId !== null) await requireGroup(request, env, groupId);
    return json(200, { url: await presignDownload(creds, key), key });
  }
  if (operation !== "upload") {
    throw new BadRequestError('Field "operation" must be "upload" or "view".');
  }

  const contentType = requireString(body, "contentType");
  const contentLength = requireInteger(body, "contentLength");
  assertUploadAllowed(contentType, contentLength);

  const purpose = requireString(body, "purpose");
  let key: string;
  if (purpose === "avatar") {
    key = await avatarKey(sub);
  } else if (purpose === "groupCover") {
    const groupId = requireString(body, "groupId");
    await requireGroup(request, env, groupId);
    key = groupCoverKey(groupId);
  } else if (purpose === "receipt") {
    const groupId = requireString(body, "groupId");
    const expenseId = requireString(body, "expenseId");
    await requireGroup(request, env, groupId);
    key = receiptKey(groupId, expenseId, newRecordId());
  } else {
    throw new BadRequestError('Field "purpose" must be "avatar", "groupCover", or "receipt".');
  }

  return json(200, {
    url: await presignUpload(creds, key, contentType, contentLength),
    key,
    method: "PUT",
    // The client must echo these exactly on the PUT — they're signed into the URL.
    headers: { "Content-Type": contentType, "Content-Length": String(contentLength) },
  });
}

/** The owner's one place to see every report across every group — gated by
 * a shared-secret bearer token, not a real auth system (there's exactly one
 * owner). Refuses every request, not just unauthorized ones, until
 * `ADMIN_TOKEN` is actually set — never "wide open by default". */
async function handleAdminReports(request: Request, env: Env): Promise<Response> {
  if (!env.ADMIN_TOKEN) throw new BareNotFoundError();
  if (bearerToken(request) !== env.ADMIN_TOKEN) throw new UnauthorizedError();
  const reports = await env.REPORTS_DO.get(env.REPORTS_DO.idFromName("global")).list();
  return json(200, reports);
}

// --- helpers ------------------------------------------------------------

/** The `?deletedBy=<memberId>` query param on a delete request
 * (`FEATURE_BACKLOG.md` "Delete goes to trash, with attribution") — optional,
 * a client that omits it just gets an unattributed trash entry. */
function deletedByParam(request: Request): string | undefined {
  return new URL(request.url).searchParams.get("deletedBy") ?? undefined;
}

/** Extract the `Authorization: Bearer <token>` value or throw a 401. */
function bearerToken(request: Request): string {
  const match = /^Bearer (.+)$/.exec(request.headers.get("Authorization") ?? "");
  if (match === null) throw new UnauthorizedError("INVALID_SESSION", "Missing bearer token.");
  return match[1]!;
}

/** Verify the session token on an identity-scoped route → the composite
 * `"<provider>:<sub>"` identity string (`MANDATORY_LOGIN_PLAN.md` Part 2). */
async function requireSession(request: Request, env: Env): Promise<string> {
  try {
    const { sub } = await verifySession(bearerToken(request), env.SESSION_SIGNING_KEY);
    return sub;
  } catch (err) {
    if (err instanceof SessionError) throw new UnauthorizedError();
    throw err;
  }
}

/**
 * `groupId` possession is necessary but no longer always sufficient
 * (`ACCESS_TOKEN_PLAN.md`): once a group has an `access_token`, a request
 * also needs either a matching `?token=` or a valid session Bearer token for
 * an identity already claimed in that group (the alternate path for a device
 * that only ever synced via `GET /api/auth/groups`, never saw the original
 * link/code). A group created before this feature shipped has no stored
 * token and stays open, unchanged.
 */
async function requireGroup(request: Request, env: Env, groupId: string) {
  const stub = env.GROUP_DO.get(env.GROUP_DO.idFromName(groupId));
  if (!(await stub.exists())) throw new GroupNotFoundError();

  const required = await stub.currentAccessToken();
  if (required !== null) {
    const token = new URL(request.url).searchParams.get("token");
    const tokenMatches = token !== null && token === required;
    if (!tokenMatches) {
      const sub = await optionalSessionSub(request, env);
      const memberMatches = sub !== undefined && (await stub.hasClaimedMember(sub));
      if (!memberMatches) throw new ForbiddenError();
    }
  }
  return stub;
}

/** Like `requireGroup`, but the read-only `view_token` also grants access
 * (`FEATURE_BACKLOG.md` "Read-only web link for balances") — used only by
 * `GET /g/:groupId/balances`, which never writes, so a caller holding just
 * the view token can't reach any mutating route with it. */
async function requireReadableGroup(request: Request, env: Env, groupId: string) {
  const stub = env.GROUP_DO.get(env.GROUP_DO.idFromName(groupId));
  if (!(await stub.exists())) throw new GroupNotFoundError();

  const [access, view] = await Promise.all([stub.currentAccessToken(), stub.currentViewToken()]);
  if (access === null) return stub; // pre-token group: open, unchanged
  const token = new URL(request.url).searchParams.get("token");
  if (token !== null && (token === access || token === view)) return stub;
  const sub = await optionalSessionSub(request, env);
  if (sub !== undefined && (await stub.hasClaimedMember(sub))) return stub;
  throw new ForbiddenError();
}

/** Best-effort session check for a route where a Bearer token is an
 * *optional* alternate credential, not a requirement — unlike
 * `requireSession`, a missing or invalid token here is not an error, just
 * "no identity to check." */
async function optionalSessionSub(request: Request, env: Env): Promise<string | undefined> {
  if (request.headers.get("Authorization") === null) return undefined;
  try {
    const { sub } = await verifySession(bearerToken(request), env.SESSION_SIGNING_KEY);
    return sub;
  } catch {
    return undefined;
  }
}

function json(status: number, data: unknown): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function toErrorResponse(err: unknown): Response {
  if (err instanceof BareNotFoundError) {
    return new Response(null, { status: 404 });
  }
  if (err instanceof HttpError) {
    return json(err.status, { error: { code: err.code, message: err.message } });
  }
  if (err instanceof ValidationFailure) {
    return json(400, { error: { code: err.code, message: err.message } });
  }
  console.error("Unhandled worker error:", err);
  return json(500, { error: { code: "INTERNAL", message: "Something went wrong." } });
}

import { GroupDO } from "./group-do.ts";
import { UserDO } from "./user-do.ts";
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
import { newGroupId } from "./lib/ids.ts";
import { reserveJoinCode, resolveJoinCode } from "./lib/join-codes.ts";
import { newExpensePayload, notifyGroup, settlementPayload } from "./lib/notify.ts";
import { SessionError, mintSession, verifySession } from "./lib/session.ts";
import {
  assertPlainObject,
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

export { GroupDO, UserDO };

interface Env {
  GROUP_DO: DurableObjectNamespace<GroupDO>;
  USER_DO: DurableObjectNamespace<UserDO>;
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
  route("POST", "/api/auth/apple", handleAuthApple),
  route("POST", "/api/auth/google", handleAuthGoogle),
  route("POST", "/api/auth/refresh", handleAuthRefresh),
  route("GET", "/api/auth/groups", handleAuthGroups),
  route("POST", "/api/auth/devices", handleRegisterDevice),
  route("DELETE", "/api/auth/devices/:token", handleUnregisterDevice),
  route("GET", "/api/auth/people", handleAuthPeople),
  route("DELETE", "/api/auth/account", handleAuthDeleteAccount),
  route("GET", "/g/:groupId", handleCapabilityPage),
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
  const group = await requireGroup(request, env, params.groupId ?? "");
  const body = await readJsonObject(request);
  rejectUnknownKeys(body, ["name", "currency"]);
  const name = optionalString(body, "name");
  const currency = optionalString(body, "currency");
  if (name === undefined && currency === undefined) {
    throw new BadRequestError('Provide "name" and/or "currency".');
  }
  return json(200, await group.updateGroup({ name, currency }));
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
    "category",
    "categoryIcon",
  ]);

  const splitType = requireString(body, "splitType");
  if (splitType !== "equal" && splitType !== "exact" && splitType !== "percentage") {
    throw new BadRequestError('Field "splitType" must be "equal", "exact", or "percentage".');
  }

  const splits = requireArray(body, "splits").map((raw, i) => {
    assertPlainObject(raw, `splits[${i}]`);
    rejectUnknownKeys(raw, ["memberId", "amountMinor"]);
    return { memberId: requireString(raw, "memberId"), amountMinor: requireInteger(raw, "amountMinor") };
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
    category: optionalString(body, "category"),
    categoryIcon: optionalString(body, "categoryIcon"),
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
        );
      })(),
    );
  }
  return json(201, result.value);
}

async function handleUpdateExpense(request: Request, env: Env, params: Params): Promise<Response> {
  const group = await requireGroup(request, env, params.groupId ?? "");
  const req = parseExpenseBody(await readJsonObject(request), false);
  const result = await group.updateExpense(params.expenseId ?? "", req);
  return result.ok ? json(200, result.value) : domainErrorResponse(result.error);
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

/**
 * The human-facing capability link (`DESIGN.md` §1/§8). A stub for now: a
 * noindex page pointing at the app. A richer landing page + Universal Links
 * (`apple-app-site-association`) come with a production domain — `BACKEND_PLAN.md`
 * §6. Deliberately reveals nothing about the group.
 */
function handleCapabilityPage(_request: Request, _env: Env, params: Params): Promise<Response> {
  const groupId = params.groupId ?? "";
  const deepLink = `clantab://g/${encodeURIComponent(groupId)}`;
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

/**
 * Cross-group settling (`FEATURE_BACKLOG.md`): for each linked person the caller
 * shares groups with, the net owed per currency and the per-group edges the
 * client settles one by one. A read-side aggregation — no cross-group ledger.
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

  for (const g of groups) {
    const view = await env.GROUP_DO.get(env.GROUP_DO.idFromName(g.groupId)).peerSettlements(sub, g.memberId);
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
  // Release every claimed membership back to a placeholder, then wipe the index.
  for (const g of groups) {
    await env.GROUP_DO.get(env.GROUP_DO.idFromName(g.groupId)).unclaim(g.memberId, sub);
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

  const result = await group.claim(params.memberId ?? "", sub);
  if (!result.ok) {
    return json(result.error.code === "UNKNOWN_MEMBER" ? 404 : 409, { error: result.error });
  }
  // `GroupDO` is authoritative; the `UserDO` index is a self-healing cache we
  // update after the fact (a miss just briefly hides one group from
  // `GET /api/auth/groups`). ACCOUNTS_DESIGN.md §2.
  await env.USER_DO
    .get(env.USER_DO.idFromName(sub))
    .addMembership(groupId, result.value.member.id, result.value.member.displayName);
  return json(200, result.value);
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

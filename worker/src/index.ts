import { GroupDO } from "./group-do.ts";
import { RegistryDO } from "./registry-do.ts";
import {
  BadRequestError,
  BareNotFoundError,
  GroupNotFoundError,
  HttpError,
  RateLimitedError,
} from "./lib/errors.ts";
import { newGroupId } from "./lib/ids.ts";
import {
  assertPlainObject,
  optionalString,
  readJsonObject,
  rejectUnknownKeys,
  requireArray,
  requireInteger,
  requireString,
} from "./lib/parse.ts";
import { ValidationFailure } from "./lib/validation.ts";
import type { AddExpenseRequest, AddSettlementRequest } from "./types.ts";

export { GroupDO, RegistryDO };

interface Env {
  GROUP_DO: DurableObjectNamespace<GroupDO>;
  REGISTRY_DO: DurableObjectNamespace<RegistryDO>;
}

type Params = Record<string, string>;
type Handler = (request: Request, env: Env, params: Params) => Promise<Response>;

interface Route {
  method: string;
  pattern: URLPattern;
  handler: Handler;
}

const ROUTES: Route[] = [
  route("POST", "/api/groups", handleCreateGroup),
  route("GET", "/api/groups/resolve/:joinCode", handleResolveJoinCode),
  route("POST", "/api/groups/:groupId/members", handleJoinGroup),
  route("GET", "/api/groups/:groupId", handleGetState),
  route("POST", "/api/groups/:groupId/expenses", handleAddExpense),
  route("POST", "/api/groups/:groupId/settlements", handleAddSettlement),
  route("GET", "/g/:groupId", handleCapabilityPage),
  route("GET", "/", handleRoot),
];

function route(method: string, pathname: string, handler: Handler): Route {
  return { method, pattern: new URLPattern({ pathname }), handler };
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    let response: Response;
    try {
      response = await dispatch(request, env);
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

async function dispatch(request: Request, env: Env): Promise<Response> {
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
  return matched.handler(request, env, params);
}

// --- handlers ------------------------------------------------------------

async function handleCreateGroup(request: Request, env: Env): Promise<Response> {
  const body = await readJsonObject(request);
  rejectUnknownKeys(body, ["name", "currency", "creatorDisplayName"]);
  const name = requireString(body, "name");
  const currency = requireString(body, "currency");
  const creatorDisplayName = requireString(body, "creatorDisplayName");

  const groupId = newGroupId();
  const joinCode = await registry(env).reserve(groupId);
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
  const result = await registry(env).resolve(params.joinCode ?? "", ip);
  if (result.rateLimited) throw new RateLimitedError();
  if (result.groupId === null) throw new BareNotFoundError();
  return json(200, { groupId: result.groupId });
}

async function handleJoinGroup(request: Request, env: Env, params: Params): Promise<Response> {
  const group = await requireGroup(env, params.groupId ?? "");
  const body = await readJsonObject(request);
  rejectUnknownKeys(body, ["displayName"]);
  const { member } = await group.addMember(requireString(body, "displayName"));
  return json(201, { member });
}

async function handleGetState(_request: Request, env: Env, params: Params): Promise<Response> {
  const group = await requireGroup(env, params.groupId ?? "");
  return json(200, await group.getState());
}

async function handleAddExpense(request: Request, env: Env, params: Params): Promise<Response> {
  const group = await requireGroup(env, params.groupId ?? "");
  const body = await readJsonObject(request);
  rejectUnknownKeys(body, [
    "id",
    "payerId",
    "amountMinor",
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

  const req: AddExpenseRequest = {
    id: optionalString(body, "id"),
    payerId: requireString(body, "payerId"),
    amountMinor: requireInteger(body, "amountMinor"),
    description: requireString(body, "description"),
    date: requireString(body, "date"),
    splitType,
    splits,
    category: optionalString(body, "category"),
    categoryIcon: optionalString(body, "categoryIcon"),
  };
  const result = await group.addExpense(req);
  return result.ok ? json(201, result.value) : json(400, { error: result.error });
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

async function handleAddSettlement(request: Request, env: Env, params: Params): Promise<Response> {
  const group = await requireGroup(env, params.groupId ?? "");
  const body = await readJsonObject(request);
  rejectUnknownKeys(body, ["id", "fromId", "toId", "amountMinor"]);

  const req: AddSettlementRequest = {
    id: optionalString(body, "id"),
    fromId: requireString(body, "fromId"),
    toId: requireString(body, "toId"),
    amountMinor: requireInteger(body, "amountMinor"),
  };
  const result = await group.addSettlement(req);
  return result.ok ? json(201, result.value) : json(400, { error: result.error });
}

// --- helpers ------------------------------------------------------------

function registry(env: Env) {
  return env.REGISTRY_DO.get(env.REGISTRY_DO.idFromName("registry"));
}

async function requireGroup(env: Env, groupId: string) {
  const stub = env.GROUP_DO.get(env.GROUP_DO.idFromName(groupId));
  if (!(await stub.exists())) throw new GroupNotFoundError();
  return stub;
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

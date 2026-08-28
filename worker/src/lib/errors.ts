// HTTP-level failures. The router turns these (and `ValidationFailure` from
// `validation.ts`) into `DESIGN.md` §2 error responses.

export class HttpError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "HttpError";
  }
}

/** Unknown `groupId` on a group route → `404 { error: { code: "GROUP_NOT_FOUND" } }`. */
export class GroupNotFoundError extends HttpError {
  constructor() {
    super(404, "GROUP_NOT_FOUND", "That group could not be found.");
  }
}

/** Registry lookup rate limit tripped (`DESIGN.md` §8) → 429. */
export class RateLimitedError extends HttpError {
  constructor() {
    super(429, "RATE_LIMITED", "Too many code lookups. Please wait a minute and try again.");
  }
}

/** Malformed request: bad JSON, wrong types, unknown fields (`DESIGN.md` §6) → 400. */
export class BadRequestError extends HttpError {
  constructor(message: string) {
    super(400, "BAD_REQUEST", message);
  }
}

/**
 * `GET /api/groups/resolve/:joinCode` for an unknown code returns a **bare** 404
 * with no body — the iOS client maps that to `.notFound` (`DESIGN.md` §2).
 */
export class BareNotFoundError extends Error {
  constructor() {
    super("Not found");
    this.name = "BareNotFoundError";
  }
}

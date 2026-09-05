import type { GroupDO } from "../src/group-do.ts";
import type { UserDO } from "../src/user-do.ts";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    GROUP_DO: DurableObjectNamespace<GroupDO>;
    USER_DO: DurableObjectNamespace<UserDO>;
    JOIN_CODES: KVNamespace;
    RESOLVE_RATE_LIMITER: RateLimit;
    SESSION_SIGNING_KEY: string;
    APPLE_AUDIENCE: string;
  }
}

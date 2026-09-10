import type { GroupDO } from "../src/group-do.ts";
import type { UserDO } from "../src/user-do.ts";
import type { ReportsDO } from "../src/reports-do.ts";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    GROUP_DO: DurableObjectNamespace<GroupDO>;
    USER_DO: DurableObjectNamespace<UserDO>;
    REPORTS_DO: DurableObjectNamespace<ReportsDO>;
    JOIN_CODES: KVNamespace;
    RESOLVE_RATE_LIMITER: RateLimit;
    SESSION_SIGNING_KEY: string;
    APPLE_AUDIENCE: string;
    MEDIA: R2Bucket;
    R2_BUCKET: string;
    R2_ACCOUNT_ID: string;
    R2_ACCESS_KEY_ID: string;
    R2_SECRET_ACCESS_KEY: string;
  }
}

import type { GroupDO } from "../src/group-do.ts";
import type { RegistryDO } from "../src/registry-do.ts";
import type { UserDO } from "../src/user-do.ts";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    GROUP_DO: DurableObjectNamespace<GroupDO>;
    REGISTRY_DO: DurableObjectNamespace<RegistryDO>;
    USER_DO: DurableObjectNamespace<UserDO>;
    SESSION_SIGNING_KEY: string;
    APPLE_AUDIENCE: string;
  }
}

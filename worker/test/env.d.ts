import type { GroupDO } from "../src/group-do.ts";
import type { RegistryDO } from "../src/registry-do.ts";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    GROUP_DO: DurableObjectNamespace<GroupDO>;
    REGISTRY_DO: DurableObjectNamespace<RegistryDO>;
  }
}

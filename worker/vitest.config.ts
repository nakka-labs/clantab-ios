import { defineConfig } from "vitest/config";

// Two projects:
//  - "logic"  — pure functions, plain Node, reads test-fixtures/ from disk
//  - "worker" — RegistryDO + GroupDO + the router, in the real Workers runtime
//               (Miniflare), via @cloudflare/vitest-pool-workers
export default defineConfig({
  test: {
    projects: ["vitest.logic.config.ts", "vitest.workers.config.ts"],
  },
});

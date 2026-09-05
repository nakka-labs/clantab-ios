import { defineConfig } from "vitest/config";

// Two projects:
//  - "logic"  — pure functions, plain Node, reads test-fixtures/ from disk
//  - "worker" — GroupDO + UserDO + the router (incl. KV-backed join codes),
//               in the real Workers runtime (Miniflare), via
//               @cloudflare/vitest-pool-workers
export default defineConfig({
  test: {
    projects: ["vitest.logic.config.ts", "vitest.workers.config.ts"],
  },
});

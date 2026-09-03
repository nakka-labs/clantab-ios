import { defineWorkersProject } from "@cloudflare/vitest-pool-workers/config";

export default defineWorkersProject({
  test: {
    name: "worker",
    include: [
      "test/registry.test.ts",
      "test/group.test.ts",
      "test/routes.test.ts",
      "test/user.test.ts",
      "test/auth.test.ts",
      "test/auth-routes.test.ts",
    ],
    poolOptions: {
      workers: {
        wrangler: { configPath: "./wrangler.jsonc" },
      },
    },
  },
});

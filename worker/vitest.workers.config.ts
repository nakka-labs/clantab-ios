import { defineWorkersProject } from "@cloudflare/vitest-pool-workers/config";

export default defineWorkersProject({
  test: {
    name: "worker",
    include: [
      "test/join-codes.test.ts",
      "test/group.test.ts",
      "test/routes.test.ts",
      "test/user.test.ts",
      "test/auth.test.ts",
      "test/google-auth.test.ts",
      "test/auth-routes.test.ts",
      "test/apple-oauth.test.ts",
    ],
    poolOptions: {
      workers: {
        wrangler: { configPath: "./wrangler.jsonc" },
        // SESSION_SIGNING_KEY isn't in wrangler.jsonc `vars` (see the note there);
        // supply a fixed test value here so it's identical in CI and locally.
        miniflare: {
          bindings: { SESSION_SIGNING_KEY: "test-only-session-signing-key" },
        },
      },
    },
  },
});

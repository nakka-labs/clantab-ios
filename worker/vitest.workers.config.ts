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
      "test/apns.test.ts",
      "test/notify.test.ts",
      "test/reports.test.ts",
      "test/media.test.ts",
    ],
    poolOptions: {
      workers: {
        wrangler: { configPath: "./wrangler.jsonc" },
        // SESSION_SIGNING_KEY isn't in wrangler.jsonc `vars` (see the note there);
        // supply a fixed test value here so it's identical in CI and locally.
        // ADMIN_TOKEN likewise, for GET /api/admin/reports (SHIP_PLAN.md
        // Track 3 §7) — every test here sees it configured, so its "unset →
        // refuses every request" guard is a one-line, by-inspection case
        // this suite doesn't separately exercise.
        miniflare: {
          bindings: {
            SESSION_SIGNING_KEY: "test-only-session-signing-key",
            ADMIN_TOKEN: "test-only-admin-token",
            // R2 presign credentials (`src/lib/media.ts`) — dummy values so
            // `r2CredentialsFromEnv` returns non-null and the presign path runs.
            // The tests check URL shape / signing / auth, never a real R2 round
            // trip; the `MEDIA` binding itself is miniflare's simulated bucket,
            // configured from `wrangler.jsonc`'s `preview_bucket_name`.
            R2_BUCKET: "clantab-media-test",
            R2_ACCOUNT_ID: "test-account-id",
            R2_ACCESS_KEY_ID: "test-access-key-id",
            R2_SECRET_ACCESS_KEY: "test-secret-access-key",
          },
        },
      },
    },
  },
});

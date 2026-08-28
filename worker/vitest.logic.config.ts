import { defineProject } from "vitest/config";

export default defineProject({
  test: {
    name: "logic",
    environment: "node",
    include: ["test/logic.test.ts", "test/validation.test.ts"],
  },
});

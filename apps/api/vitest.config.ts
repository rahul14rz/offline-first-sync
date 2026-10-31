import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    globalSetup: ["./test/globalSetup.ts"],
    // Test files share one database and truncate tables, so they must not overlap.
    fileParallelism: false,
  },
});

import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "tests/browser",
  timeout: 60000,
  // Emulated Electron rendering under Rosetta can exceed the default 5 s.
  expect: { timeout: 15000 },
  workers: 1,
  reporter: "list",
  use: { trace: "retain-on-failure" },
});

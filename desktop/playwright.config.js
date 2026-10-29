import { defineConfig } from "@playwright/test";
export default defineConfig({ testDir: "tests/browser", timeout: 60000, workers: 1, reporter: "list", use: { trace: "retain-on-failure" } });

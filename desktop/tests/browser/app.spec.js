import { test, expect, _electron as electron } from "@playwright/test";
import path from "node:path";
import fs from "node:fs/promises";
import { lensDisplayPoint } from "../../vendor/aym-devkit-ui/src/vendor/crt.js";

test.describe.configure({ mode: "serial" });
let app, page, profile;
const errors = [];
const original = process.env.PACKAGER_TEST_ORIGINAL;
const fixed = process.env.PACKAGER_TEST_FIXED;
const legacy = process.env.PACKAGER_TEST_LEGACY;
const output = path.resolve("../.build/validation/ui-output");

test.beforeAll(async () => {
  for (const file of [original, fixed, legacy].filter(Boolean)) await fs.stat(file);
  await fs.mkdir(output, { recursive: true });
  profile = await fs.mkdtemp(path.resolve("../.build/gui-profile-"));
  app = await electron.launch({ ...(process.env.PACKAGER_TEST_APP ? { executablePath: process.env.PACKAGER_TEST_APP, args: [] } : { args: ["."] }), cwd: process.cwd(), env: { ...process.env, ELECTRON_ENABLE_LOGGING: "1", PACKAGER_TEST_USER_DATA: profile } });
  page = await app.firstWindow();
  page.on("pageerror", (error) => errors.push(error.message));
  await page.waitForSelector("#start", { state: "attached" });
  // Test text and hitboxes without a lens; CRT pointer mapping has its own upstream tests.
  await page.evaluate(() => { localStorage.clear(); localStorage.setItem("aym-crt", "false"); localStorage.setItem("packager-interface", JSON.stringify({ appearance: "dark", language: "zh", motion: true, sound: true, softness: 0.2 })); });
  await page.addInitScript(() => {
    window.entryFrames = [];
    let started = false;
    function record() {
      const site = document.querySelector("#site"), hero = document.querySelector(".hero"), workspace = document.querySelector(".quick-body.workspace");
      if (site?.dataset.assembling === "true") {
        started = true;
        window.entryFrames.push({ transform: getComputedStyle(hero).transform, clip: getComputedStyle(workspace).clipPath });
      }
      if (!started || !document.querySelector("#welcome")?.hidden) requestAnimationFrame(record);
    }
    requestAnimationFrame(record);
  });
  await page.reload();
});
test.afterAll(async () => { await app?.close(); if (profile) await fs.rm(profile, { recursive: true, force: true }); });

async function select(file) {
  await app.evaluate(({ dialog }, selected) => { dialog.showOpenDialog = async () => ({ canceled: false, filePaths: [selected] }); }, file);
  await page.locator('[data-action="open"]').first().click();
}

test("startup automatically morphs and wipes into Quick mode", async () => {
  await expect(page.locator("#welcome")).toBeHidden();
  await expect(page.locator("#site")).toHaveAttribute("data-view", "overview");
  const frames = await page.evaluate(() => window.entryFrames);
  expect(frames.length).toBeGreaterThan(5);
  expect(frames.some((frame) => {
    const values = frame.transform.match(/^matrix\((.*)\)$/)?.[1].split(",").map(Number);
    return values && Math.abs(values[0] - values[3]) > 0.03;
  })).toBeTruthy();
  expect(frames.some((frame) => frame.clip !== "none" && frame.clip !== "inset(0px)" && frame.clip !== "inset(0px 0px 0px 0px)")).toBeTruthy();
  const palette = await page.evaluate(() => ({
    accent: getComputedStyle(document.querySelector(".nav.active")).backgroundColor,
    primary: getComputedStyle(document.querySelector(".quick-hero button.primary")).backgroundColor,
    strata: getComputedStyle(document.querySelector(".quick-hero .strata-mid")).fill,
  }));
  console.log("Library palette:", palette);
  await expect(page.locator(".notice")).toContainText("转换可能失败");
  await expect(page.locator(".notice")).toContainText("推荐使用完整模式");
  await expect(page.locator("#quick-convert")).toBeDisabled();
  await expect(page.locator("#error")).toBeHidden();
  await page.screenshot({ scale: "css", path: "../docs/quick-mode.png" });
});

test("real Spectral package is inspected and quickly repaired through IPC", async () => {
  test.skip(!original, "Set PACKAGER_TEST_ORIGINAL");
  await select(original);
  await expect(page.locator("#quick-convert")).toBeEnabled({ timeout: 30000 });
  await expect(page.locator("#quick-project")).toContainText("可修复 0 KB");
  await expect(page.locator("#quick-project")).toContainText("ARM 64");
  await expect(page.locator("#quick-project")).toContainText("尚未实际安装");
  await app.evaluate(({ dialog }, folder) => { dialog.showOpenDialog = async () => ({ canceled: false, filePaths: [folder] }); }, output);
  await page.locator('[data-action="directory"]').first().click();
  await page.locator("#quick-convert").click();
  await expect(page.locator("#quick-result")).toContainText("归档验证通过", { timeout: 30000 });
  await expect(page.locator("#quick-result")).toContainText("5 项修改");
  await expect(page.locator("#quick-result")).toContainText("运行兼容性仍需");
  const files = await fs.readdir(output);
  expect(files.some((file) => file.endsWith(".pkg"))).toBeTruthy();
});

test("full mode exposes issues, file search, preview and conservative options", async () => {
  test.skip(!original);
  await page.locator('.nav[data-page="foundations"]').click();
  await expect(page.locator("#main")).toHaveAttribute("aria-busy", "false");
  await expect(page.locator("#full-workspace")).toBeVisible();
  await expect(page.locator("#fix-scripts")).not.toBeChecked();
  await page.locator("#issues-tab").click();
  await expect(page.locator("#issues-panel")).toContainText("安装尺寸为零");
  await page.locator("#structure-tab").click();
  await page.locator("#search").fill("postinstall");
  await expect(page.locator(".tree-leaf").first()).toBeVisible();
  await page.locator(".tree-leaf").first().click();
  await expect(page.locator("#preview-text")).toContainText("#!/");
  await page.locator("#close-preview").click();
  await page.locator("#search").fill("");
  await page.evaluate(() => { document.querySelector("#main").scrollTop = 0; });
  await page.screenshot({ scale: "css", path: "../docs/full-mode-dark.png" });
});

test("fixed sample stays clean and legacy bundle exposes i386 incompatibility", async () => {
  test.skip(!fixed || !legacy);
  await select(fixed);
  await expect(page.locator("#full-rebuild")).toBeEnabled({ timeout: 30000 });
  await expect(page.locator("#fix-installSizes")).not.toBeChecked();
  await select(legacy);
  await expect(page.locator("#full-rebuild")).toBeEnabled({ timeout: 30000 });
  await page.locator("#issues-tab").click();
  await expect(page.locator("#compatibility-summary")).toContainText("无法在本机运行");
  await expect(page.locator("#compatibility-summary")).toContainText("Intel 32 位");
  await page.locator("#structure-tab").click();
  await page.locator("#tree-filter").selectOption("binary");
  await expect(page.locator("#tree")).toContainText("i386");
  await expect(page.locator("#package-list .package-item")).toHaveCount(3);
});

test("settings stay in the window and language, appearance and keyboard work", async () => {
  await page.locator("#system-open").click();
  await expect(page.locator("#system-dialog")).toBeVisible();
  await expect(page.locator("#system-dialog .system-content")).not.toHaveAttribute("inert", "");
  await page.locator('[data-appearance-choice="light"]').click();
  await expect(page.locator("html")).toHaveAttribute("data-appearance", "light");
  await page.locator('[data-language="en"]').click();
  await expect(page.locator("html")).toHaveAttribute("lang", "en");
  await page.keyboard.press("Escape");
  await expect(page.locator("#system-dialog")).not.toBeVisible();
  await expect(page.locator("#site")).not.toHaveAttribute("inert", "");
  await page.locator('.nav[data-page="overview"]').click();
  await expect(page.locator("#main")).toHaveAttribute("aria-busy", "false");
  await expect(page.locator(".notice")).toContainText("Full mode is recommended");
  await page.screenshot({ scale: "css", path: "../docs/quick-mode-light-en.png" });
  await page.locator("#system-open").click();
  await page.locator('[data-appearance-choice="dark"]').click();
  await page.locator('[data-language="zh"]').click();
  await page.keyboard.press("Escape");
  // Verify a physical pointer against the actual enabled CRT lens at the far corner.
  await page.locator("#system-open").click();
  await page.locator("#crt-toggle").click();
  await page.keyboard.press("Escape");
  await expect(page.locator("#system-dialog")).not.toBeVisible();
  await expect(page.locator("html")).toHaveClass(/crt-mode/);
  const rect = await page.locator("#system-open").boundingBox();
  const viewport = await page.evaluate(() => ({ width: document.querySelector(".crt-surface").clientWidth, height: innerHeight }));
  const physical = lensDisplayPoint(rect.x + rect.width / 2, rect.y + rect.height / 2, viewport.width, viewport.height);
  await page.mouse.click(physical.x, physical.y);
  await expect(page.locator("#system-dialog")).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(page.locator("#system-dialog")).not.toBeVisible();
  await page.screenshot({ scale: "css", path: "../docs/quick-mode-crt.png" });
  expect(errors).toEqual([]);
  await expect(page.locator("#error")).toBeHidden();
});


test("reduced motion enters immediately and releases every control", async () => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.evaluate(() => localStorage.setItem("aym-crt", "false"));
  await page.reload();
  await expect(page.locator("#welcome")).toBeHidden();
  await expect(page.locator("#site")).not.toHaveAttribute("data-assembling", "true");
  await expect(page.locator("#system-open")).toBeEnabled();
  const frames = await page.evaluate(() => window.entryFrames);
  expect(frames.length).toBe(0);
  await page.locator("#system-open").click();
  await expect(page.locator("#system-dialog")).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(page.locator("#system-dialog")).not.toBeVisible();
  await page.emulateMedia({ reducedMotion: "no-preference" });
});

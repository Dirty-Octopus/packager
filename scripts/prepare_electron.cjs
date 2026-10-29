const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const crypto = require("node:crypto");
const { execFileSync } = require("node:child_process");
const root = path.join(__dirname, "..", "desktop", "node_modules", "electron");
const version = require(path.join(root, "package.json")).version;
const arch = process.env.ELECTRON_INSTALL_ARCH || process.arch;
const filename = `electron-v${version}-darwin-${arch}.zip`;
const expected = require(path.join(root, "checksums.json"))[filename];
const cache = path.join(os.homedir(), "Library", "Caches", "electron");
let cached;
if (fs.existsSync(cache)) for (const folder of fs.readdirSync(cache)) {
  const candidate = path.join(cache, folder, filename);
  if (fs.existsSync(candidate) && crypto.createHash("sha256").update(fs.readFileSync(candidate)).digest("hex") === expected) { cached = candidate; break; }
}
if (cached) {
  const destination = path.join(root, "dist");
  fs.mkdirSync(destination, { recursive: true });
  execFileSync("/usr/bin/ditto", ["-x", "-k", cached, destination]);
  fs.writeFileSync(path.join(root, "path.txt"), "Electron.app/Contents/MacOS/Electron");
  console.log(`Prepared verified cached Electron ${version} (${arch})`);
} else execFileSync(process.execPath, [path.join(root, "install.js")], { stdio: "inherit" });

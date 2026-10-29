const { app, BrowserWindow, Menu, ipcMain, dialog, shell } = require("electron");
const fs = require("node:fs/promises");
const path = require("node:path");
const crypto = require("node:crypto");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");
const { runBackend } = require("./backend.cjs");
const execute = promisify(execFile);
let window, sessionRoot;
const projects = new Map(), jobs = new Map();
const queuedPaths = [];
const backend = () => app.isPackaged ? path.join(process.resourcesPath, "backend", "Packager") : path.join(__dirname, "..", ".build", "backend", "Packager");
const projectFor = (id) => { if (!projects.has(id)) throw new Error("Unknown project"); return projects.get(id); };
const inside = (file, directory) => file === directory || file.startsWith(directory + path.sep);
async function addPackages(paths) {
  const added = [];
  for (const file of paths) {
    const source = await fs.realpath(file);
    if (![".pkg", ".mpkg"].includes(path.extname(source).toLowerCase())) throw new Error("Choose a .pkg or .mpkg / 请选择安装包");
    const existing = [...projects.values()].find((p) => p.source === source);
    if (existing) { added.push(existing); continue; }
    const id = crypto.randomUUID();
    const project = { id, source, name: path.basename(source), workspace: path.join(sessionRoot, id), outputDirectory: path.join(app.getPath("downloads"), "Packager") };
    await fs.mkdir(project.workspace, { recursive: true });
    projects.set(id, project); added.push(project);
  }
  return added;
}
function register(channel, fn) {
  ipcMain.handle(channel, (event, args) => {
    if (event.sender !== window?.webContents) throw new Error("Unknown sender");
    return fn(args);
  });
}
function bindIPC() {
  register("app:info", () => ({ version: app.getVersion(), outputDirectory: path.join(app.getPath("downloads"), "Packager") }));
  register("packages:open", async (paths) => {
    if (!paths) {
      const result = await dialog.showOpenDialog(window, { properties: ["openFile", "multiSelections"], filters: [{ name: "Installer packages", extensions: ["pkg", "mpkg"] }] });
      paths = result.canceled ? [] : result.filePaths;
    }
    if (!Array.isArray(paths) || paths.some((p) => typeof p !== "string" || !path.isAbsolute(p))) throw new Error("Invalid file selection");
    return addPackages(paths);
  });
  register("packages:run", async ({ id, operation, options = {}, language }) => {
    const project = projectFor(id);
    if (!["inspect", "rebuild"].includes(operation) || jobs.has(id)) throw new Error("Operation unavailable");
    if (options.outputDirectory && options.outputDirectory !== project.outputDirectory) throw new Error("Choose the output directory through the native picker");
    const job = runBackend(backend(), { operation, source: project.source, workspace: project.workspace, language, options: { ...options, outputDirectory: project.outputDirectory } }, (event) => {
      // Administrator commands stay in the main process; the renderer receives only a status.
      const safe = { ...event, id };
      if (safe.authorization) safe.authorization = true;
      if (!window.isDestroyed()) window.webContents.send("job:event", safe);
    });
    jobs.set(id, job);
    try {
      const result = await job.promise;
      if (result.output) { project.output = result.output; project.authorization = null; }
      return { ok: true, value: result };
    } catch (error) {
      project.authorization = error.authorization;
      return { ok: false, error: error.message, authorization: Boolean(error.authorization) };
    } finally { jobs.delete(id); }
  });
  register("packages:cancel", (id) => { jobs.get(id)?.cancel(); return true; });
  register("packages:remove", async (id) => {
    const project = projectFor(id);
    const job = jobs.get(id); job?.cancel();
    await job?.promise.catch(() => {});
    await fs.rm(project.workspace, { recursive: true, force: true }); projects.delete(id);
  });
  register("output:directory", async () => {
    const result = await dialog.showOpenDialog(window, { properties: ["openDirectory", "createDirectory"] });
    if (result.canceled) return null;
    // All current projects may use this explicitly chosen destination.
    for (const project of projects.values()) project.outputDirectory = result.filePaths[0];
    return result.filePaths[0];
  });
  register("packages:reveal", ({ id, target }) => {
    const project = projectFor(id);
    const file = { source: project.source, workspace: project.workspace, output: project.output }[target];
    if (file) shell.showItemInFolder(file);
  });
  register("packages:preview", async ({ id, path: file }) => {
    const project = projectFor(id);
    const real = await fs.realpath(file);
    if (!inside(real, project.workspace)) throw new Error("Preview is limited to this workspace");
    const stat = await fs.stat(real);
    if (!stat.isFile() || stat.size > 1_500_000) return { text: "File is binary, too large, or a directory. / 此文件为二进制、目录或过大。" };
    const data = await fs.readFile(real);
    return { text: data.includes(0) ? "Binary file / 二进制文件" : data.toString("utf8") };
  });
  register("packages:authorize", async (id) => {
    const project = projectFor(id), request = project.authorization;
    if (!request || !inside(request.source, project.workspace)) throw new Error("No pending output");
    const result = await dialog.showMessageBox(window, { type: "question", message: "Save to a protected folder / 保存到受保护目录", detail: request.command, buttons: ["Cancel / 取消", "Authorize / 授权"], defaultId: 0, cancelId: 0 });
    if (result.response !== 1) return { ok: false, error: "Cancelled / 已取消" };
    const escaped = request.command.replaceAll("\\", "\\\\").replaceAll('"', '\\"');
    try {
      await execute("/usr/bin/osascript", ["-e", `do shell script "${escaped}" with administrator privileges`]);
      project.output = request.destination; project.authorization = null;
      return { ok: true, value: { output: project.output, size: request.size, fixes: request.fixes, verified: true } };
    } catch (error) { return { ok: false, error: error.stderr || error.message }; }
  });
}
function sendMenu(action) { window?.webContents.send("app:menu", action); }
app.on("open-file", (event, file) => {
  event.preventDefault();
  if (sessionRoot && window && !window.webContents.isLoading()) addPackages([file]).then((files) => window.webContents.send("packages:opened", files));
  else queuedPaths.push(file);
});
if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on("second-instance", () => { window?.show(); window?.focus(); });
  app.whenReady().then(async () => {
    app.setName("Packager");
    const root = path.join(app.getPath("appData"), "Packager", "Workspace");
    await fs.mkdir(root, { recursive: true }); sessionRoot = await fs.mkdtemp(path.join(root, "session-"));
    window = new BrowserWindow({ width: 1380, height: 940, minWidth: 1080, minHeight: 760, title: "Packager", titleBarStyle: "hiddenInset", backgroundColor: "#080808", webPreferences: { preload: path.join(__dirname, "preload.cjs"), contextIsolation: true, nodeIntegration: false, sandbox: true, autoplayPolicy: "no-user-gesture-required" }, show: false });
    bindIPC();
    Menu.setApplicationMenu(Menu.buildFromTemplate([
      { label: "Packager", submenu: [{ role: "about" }, { label: "Settings…", accelerator: "CmdOrCtrl+,", click: () => sendMenu("settings") }, { type: "separator" }, { role: "hide" }, { role: "hideOthers" }, { role: "unhide" }, { type: "separator" }, { role: "quit" }] },
      { label: "File", submenu: [{ label: "Open Package…", accelerator: "CmdOrCtrl+O", click: () => sendMenu("open") }, { label: "Repackage", accelerator: "CmdOrCtrl+R", click: () => sendMenu("rebuild") }] },
      { role: "editMenu" }, { role: "windowMenu" },
    ]));
    window.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
    window.webContents.on("will-navigate", (event) => event.preventDefault());
    window.once("ready-to-show", () => window.show());
    window.webContents.on("did-finish-load", async () => {
      if (queuedPaths.length) window.webContents.send("packages:opened", await addPackages(queuedPaths.splice(0)));
    });
    if (process.env.PACKAGER_DEV_URL === "http://127.0.0.1:1421") await window.loadURL(process.env.PACKAGER_DEV_URL);
    else await window.loadFile(path.join(__dirname, "dist", "index.html"));
  });
  app.on("window-all-closed", () => app.quit());
  app.on("before-quit", (event) => {
    if (!sessionRoot) return;
    event.preventDefault();
    const root = sessionRoot; sessionRoot = null;
    for (const job of jobs.values()) job.cancel();
    Promise.allSettled([...jobs.values()].map((job) => job.promise)).then(() => fs.rm(root, { recursive: true, force: true })).finally(() => app.quit());
  });
}

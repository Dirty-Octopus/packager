import { t, prefs, page, sound, drawMarks } from "@aym-devkit/ui/shell";
import brand from "../../Resources/BrandMark.json";
import "./app.css";
drawMarks(brand.rows);

const $ = (selector) => document.querySelector(selector);
const api = window.packager;
const projects = new Map();
let selectedId = null, outputDirectory = "", activeTab = "structure", version = "";
const selected = () => projects.get(selectedId);
const escape = (value = "") => String(value).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const size = (bytes) => bytes ? bytes >= 1048576 ? `${(bytes / 1048576).toFixed(1)} MB` : `${Math.ceil(bytes / 1024)} KB` : "—";
const showError = (error) => { $("#error").hidden = false; $("#error").textContent = error.message || String(error); setTimeout(() => { $("#error").hidden = true; }, 9000); };
const busy = (project) => ["inspecting", "rebuilding", "cancelling"].includes(project?.state);
function label(zh, en) { return escape(t(zh, en)); }
function appendLog(project, text) {
  project.log.push(`${new Date().toLocaleTimeString()}  ${text}`);
  project.log = project.log.slice(-500);
  if (project.id === selectedId) {
    $("#activity-log").textContent = project.log.join("\n");
    $("#footer-status").textContent = text.slice(0, 110);
    if (busy(project)) {
      for (const selector of ["#quick-result", "#full-result"]) $(selector).textContent = text;
    }
  }
}

async function receive(files) {
  for (const file of files) {
    if (!projects.has(file.id)) projects.set(file.id, { ...file, state: "idle", log: [], options: {}, report: null, result: null, error: "", authorization: false });
    selectedId = file.id;
    render();
    if (!projects.get(file.id).report && !busy(projects.get(file.id))) await inspect(projects.get(file.id));
  }
}
async function open() { try { await receive(await api.open()); } catch (error) { showError(error); } }
async function inspect(project) {
  project.state = "inspecting"; project.error = ""; render();
  try {
    const response = await api.run(project.id, "inspect", {}, prefs.language);
    if (!response.ok) throw new Error(response.error);
    project.report = response.value;
    const stats = project.report.stats;
    project.options = { versionLimits: stats.versionLimits > 0, relocatable: stats.relocatable > 0, installSizes: stats.installSizes > 0, scripts: false, outputName: project.name.replace(/\.(m?pkg)$/i, "-modernized.pkg") };
    project.state = "ready";
  } catch (error) { project.state = "failed"; project.error = error.message; }
  render();
}
async function rebuild(quick) {
  const project = selected();
  if (!project?.report || busy(project)) return;
  project.state = "rebuilding"; project.error = ""; project.result = null; project.authorization = false;
  const stats = project.report.stats;
  const options = quick ? { versionLimits: stats.versionLimits > 0, relocatable: stats.relocatable > 0, installSizes: stats.installSizes > 0, scripts: false, outputName: project.options.outputName } : { ...project.options };
  render();
  appendLog(project, t(quick ? "快速转换：保留脚本；仅应用可识别的修复" : "按所选选项重新封装", quick ? "Quick conversion: preserve scripts; apply supported repairs" : "Repackage using selected options"));
  try {
    const response = await api.run(project.id, "rebuild", options, prefs.language);
    project.authorization = response.authorization;
    if (!response.ok) throw new Error(response.error);
    project.result = response.value; project.state = "success";
    appendLog(project, t("已验证并保存：", "Verified and saved: ") + response.value.output);
  } catch (error) {
    project.state = "failed"; project.error = error.message;
    appendLog(project, project.error);
  }
  render();
}
function renderResult(project) {
  if (!project) return "";
  if (busy(project)) return `<div class="job-state"><span class="spinner"></span>${label(project.state === "inspecting" ? "检查中…" : "处理中…", project.state === "inspecting" ? "INSPECTING…" : "WORKING…")}</div>`;
  if (project.result) return `<div class="result-card success"><strong>${label("归档验证通过", "ARCHIVE VERIFIED")}</strong><code>${escape(project.result.output)}</code>${(project.result.warnings || []).map((warning) => `<p class="remaining-warning">${escape(warning)}</p>`).join("")}<span>${size(project.result.size)} · ${project.result.fixes} ${label("项修改", "CHANGES")}</span><p>${label("安装和运行兼容性仍需在目标环境验证。", "Installation and runtime compatibility still require validation on the target Mac.")}</p><button data-action="reveal-output">${label("在 Finder 中显示 ↗", "REVEAL IN FINDER ↗")}</button></div>`;
  if (project.error) return `<div class="result-card failure"><strong>${label("操作未完成", "OPERATION INCOMPLETE")}</strong><p>${escape(project.error)}</p>${project.authorization ? `<button data-action="authorize">${label("授权保存", "AUTHORIZE SAVE")}</button>` : !project.report ? `<button data-action="retry">${label("重新检查", "RETRY INSPECTION")}</button>` : ""}<button data-goto="foundations">${label("在完整模式中检查", "REVIEW IN FULL MODE")}</button></div>`;
  return "";
}

function runtimeLabel(value) {
  return ({
    native: t("有本机原生架构，有运行可能", "NATIVE ARCHITECTURE: MAY RUN"),
    translated: t("Intel 64 位：可能通过 Rosetta 运行", "INTEL 64-BIT: MAY RUN WITH ROSETTA"),
    needsRosetta: t("需要 Rosetta，本机尚未检测到", "ROSETTA REQUIRED; NOT DETECTED"),
    partial: t("部分内容不兼容，可能无法完整运行", "SOME CONTENT IS INCOMPATIBLE"),
    incompatible: t("检测到的程序无法在本机运行", "DETECTED EXECUTABLES CANNOT RUN HERE"),
    unknown: t("信息不足，暂时无法判断运行可能性", "INSUFFICIENT DATA TO ASSESS RUNTIME"),
  })[value] || t("未判断", "NOT ASSESSED");
}
function architectureLabel(value) {
  const known = { i386: ["Intel", 32], x86_64: ["Intel", 64], arm: ["ARM", 32], arm64: ["ARM", 64], arm64_32: ["ARM", 32], ppc: ["PowerPC", 32], ppc64: ["PowerPC", 64] };
  const info = known[value];
  return info ? `${value} · ${info[0]} ${info[1]}${t(" 位", "-bit")}` : value;
}
function compatibility(report) {
  const check = report?.compatibility;
  if (!check?.host) return "";
  const host = check.host;
  const computer = `${host.architecture === "arm64" ? "Apple Silicon / ARM 64" : "Intel 64"} · macOS ${host.macOS}`;
  const rosetta = host.architecture === "arm64" ? ` · Rosetta ${t(host.rosetta ? "已检测到" : "未检测到", host.rosetta ? "detected" : "not detected")}` : "";
  const architectures = check.architectures.map((item) => architectureLabel(item.name));
  return `<div class="compat-card runtime-${escape(check.runtime)}"><p class="eyebrow">${label("本机兼容性初判", "THIS MAC / COMPATIBILITY")}</p><strong class="runtime-verdict">${escape(runtimeLabel(check.runtime))}</strong><p class="host-info">${escape(computer + rosetta)}</p><div class="architecture-chips">${architectures.map((arch) => `<span>${escape(arch)}</span>`).join("") || label("未检测到可识别的二进制", "NO RECOGNIZED BINARIES")}</div><p><b>${label("安装", "INSTALL")}</b> · ${label("已识别包结构，可尝试重建后安装；尚未实际安装。", "Package structure recognized. A rebuild can be attempted; installation has not been tested.")}</p><p><b>${label("运行", "RUN")}</b> · ${label("基于已扫描架构初判；系统 API、依赖、授权与插件宿主仍会影响结果。Intel 插件还需要兼容的宿主或桥接。", "Architecture assessment only. OS APIs, dependencies, licensing and plug-in hosts still affect runtime. Intel plug-ins require a compatible host or bridge.")}</p><details class="component-compatibility"><summary>${label("查看各组件的架构与判断", "COMPONENT ARCHITECTURES & VERDICTS")}</summary><table><thead><tr><th>${label("组件", "COMPONENT")}</th><th>${label("架构", "ARCHITECTURES")}</th><th>${label("运行初判", "RUNTIME")}</th></tr></thead><tbody>${check.components.map((component) => `<tr><td>${escape(component.name)}</td><td>${component.architectures.map((arch) => escape(architectureLabel(arch.name))).join("<br>") || "—"}</td><td>${escape(runtimeLabel(component.runtime))}</td></tr>`).join("")}</tbody></table></details></div>`;
}

function render() {
  const project = selected(), report = project?.report;
  document.body.classList.toggle("has-project", Boolean(project));
  $("#package-list").innerHTML = [...projects.values()].map((p) => `<div class="package-item ${p.id === selectedId ? "selected" : ""}"><button class="package-select" data-select="${p.id}"><b>${escape(p.report?.title || p.name)}</b><small>${escape(busy(p) ? t("处理中", "WORKING") : p.state === "failed" ? t("未完成", "INCOMPLETE") : p.report?.format || "PKG")}</small></button><button class="package-remove" data-remove="${p.id}" aria-label="${label("移除安装包", "Remove package")}" ${busy(p) ? "disabled" : ""}>×</button></div>`).join("");
  $("#quick-drop").hidden = Boolean(project);
  $("#quick-project").hidden = !project;
  $("#quick-project").innerHTML = project ? `<div class="package-summary"><span class="package-tag">${escape(report?.format || "PKG")}</span><div><h2>${escape(report?.title || project.name)}</h2><code>${escape(project.source)}</code></div><button data-action="open">${label("更换 / 添加", "CHANGE / ADD")}</button></div>${report ? `<div class="quick-facts"><span>${report.stats.components} ${label("组件", "COMPONENTS")}</span><span>${report.stats.binaries} ${label("二进制", "BINARIES")}</span><span>${report.stats.installSizes ? label("可修复 0 KB 尺寸", "ZERO SIZES DETECTED") : label("已完成结构检查", "STRUCTURE INSPECTED")}</span></div>${report.stats.legacy ? `<p class="compatibility-warning">${label("含有旧架构切片；转换不会生成 64 位代码。请在完整模式查看每个二进制的架构。", "Contains legacy slices. Conversion cannot generate 64-bit code. Review each binary in Full mode.")}</p>` : ""}` : ""}` : "";
  if (report) $("#quick-project").insertAdjacentHTML("beforeend", compatibility(report));
  $("#quick-convert").disabled = !report || busy(project);
  $("#quick-cancel").hidden = !busy(project);
  $("#quick-output-directory").textContent = project?.outputDirectory || outputDirectory;
  $("#quick-result").innerHTML = renderResult(project);
  $("#full-empty").hidden = Boolean(project);
  $("#full-workspace").hidden = !project;
  if (project) {
    $("#project-heading").innerHTML = `<div><h2>${escape(report?.title || project.name)}</h2><code>${escape(project.source)}</code></div><span class="format-label">${escape(report?.format || "PKG")} · ${escape(report?.signature || "—")}</span>`;
    $("#compatibility-summary").innerHTML = compatibility(report);
    const stats = report?.stats;
    $("#stats").innerHTML = stats ? [[stats.components, t("组件", "COMPONENTS")], [stats.files, t("文件", "FILES")], [stats.binaries, t("二进制", "BINARIES")], [stats.legacy, t("含旧切片", "WITH LEGACY SLICES")], [stats.riskyScripts, t("高风险脚本", "HIGH-RISK SCRIPTS")]].map(([n, title]) => `<div><b>${n}</b><span>${escape(title)}</span></div>`).join("") : "";
    for (const key of ["versionLimits", "relocatable", "installSizes", "scripts"]) { $(`#fix-${key}`).checked = Boolean(project.options[key]); $(`#fix-${key}`).disabled = !report || busy(project); }
    $("#output-name").value = project.options.outputName || "";
    $("#output-name").disabled = busy(project);
    $("#output-directory").textContent = project.outputDirectory;
    $("#full-rebuild").disabled = !report || busy(project);
    $("#cancel").hidden = !busy(project);
    $("#cancel").disabled = project.state === "cancelling";
    $("#full-result").innerHTML = renderResult(project);
    renderIssues(); renderTree();
  }
  $("#activity-log").textContent = project?.log.join("\n") || t("尚无活动记录。", "No activity yet.");
  $("#footer-status").textContent = project ? t(busy(project) ? "处理中" : "就绪", busy(project) ? "WORKING" : "READY") : "READY";
}
function renderIssues() {
  const project = selected();
  const issues = (prefs.language === "zh" ? project?.report?.issuesZH : project?.report?.issues) || [];
  $("#issues-panel").innerHTML = issues.length ? issues.map((issue) => `<article class="issue severity-${issue.severity}"><div class="issue-title"><span>${escape([t("严重", "CRITICAL"), t("警告", "WARNING"), t("提示", "NOTE")][issue.severity])}</span><strong>${escape(issue.title)}</strong></div><p>${escape(issue.message)}</p>${issue.paths.length ? `<code>${issue.paths.map(escape).join("<br>")}</code>` : ""}${issue.fix ? `<button data-fix="${escape(issue.fix)}" aria-pressed="${Boolean(project.options[{ versionLimits: "versionLimits", relocatable: "relocatable", scripts: "scripts", installSizes: "installSizes" }[issue.fix]])}">${label("切换此项修复", "TOGGLE THIS FIX")}</button>` : ""}</article>`).join("") : `<p class="empty-state">${label("未发现可识别的问题；仍需自行验证安装与运行。", "No recognized issues. Installation and runtime still need validation.")}</p>`;
}
function renderTree() {
  const report = selected()?.report;
  if (!report) { $("#tree").textContent = t("等待检查结果…", "Waiting for inspection…"); return; }
  const query = $("#search").value.toLocaleLowerCase(), filter = $("#tree-filter").value;
  function visit(node, depth) {
    const children = node.children.map((child) => visit(child, depth + 1)).filter(Boolean).join("");
    const match = (!query || (node.name + node.path).toLocaleLowerCase().includes(query)) && (filter === "all" || node.kind === filter || filter === "warning" && (node.legacy || node.risk !== "none"));
    if (!match && !children) return "";
    const row = `<span class="node-kind">${escape(node.kind)}</span><span class="node-name">${escape(node.name)}</span>${node.architectures.length ? `<span class="arch ${node.legacy ? "legacy" : ""}">${escape(node.architectures.map(architectureLabel).join(" / "))}</span>` : ""}<small>${size(node.size)}</small>`;
    return node.children.length ? `<details role="treeitem" ${depth < 2 || query || filter !== "all" ? "open" : ""}><summary>${row}</summary><div role="group">${children}</div>${node.hiddenCount ? `<p class="tree-truncated">+ ${node.hiddenCount} ${label("项已折叠显示；可在工作区查看", "ITEMS OMITTED; SEE WORKSPACE")}</p>` : ""}</details>` : `<button class="tree-leaf" role="treeitem" data-preview="${escape(node.path)}" data-filename="${escape(node.name)}">${row}</button>`;
  }
  $("#tree").innerHTML = visit(report.tree, 0) || `<p class="empty-state">${label("无匹配结果", "NO MATCHES")}</p>`;
}
function setTab(tab) {
  activeTab = tab;
  for (const value of ["structure", "issues"]) { $(`#${value}-tab`).setAttribute("aria-selected", String(tab === value)); $(`#${value}-panel`).hidden = tab !== value; }
}

document.addEventListener("click", async (event) => {
  const button = event.target.closest("button");
  if (!button || button.disabled) return;
  try {
    if (button.dataset.select) { selectedId = button.dataset.select; $("#file-preview").hidden = true; render(); }
    if (button.dataset.remove) {
      await api.remove(button.dataset.remove); projects.delete(button.dataset.remove);
      if (!projects.has(selectedId)) selectedId = [...projects.keys()][0] || null;
      render();
    }
    if (button.dataset.goto) page(button.dataset.goto);
    if (button.dataset.fix) { const p = selected(); const key = button.dataset.fix; p.options[key] = !p.options[key]; render(); }
    if (button.dataset.preview) {
      const p = selected(); const path = button.dataset.preview;
      const result = await api.preview(p.id, path);
      $("#file-preview").hidden = false; $("#preview-title").textContent = button.dataset.filename; $("#preview-text").textContent = result.text;
    }
    const action = button.dataset.action;
    if (action === "open") await open();
    if (action === "retry") await inspect(selected());
    if (action === "directory") {
      const directory = await api.directory();
      if (directory) { outputDirectory = directory; for (const project of projects.values()) project.outputDirectory = directory; render(); }
    }
    if (action === "reveal-output") await api.reveal(selectedId, "output");
    if (action === "authorize") {
      const p = selected(); const response = await api.authorize(p.id);
      if (response.ok) { p.result = response.value; p.error = ""; p.authorization = false; p.state = "success"; }
      else p.error = response.error;
      render();
    }
  } catch (error) { showError(error); }
});
$("#quick-convert").onclick = () => rebuild(true);
$("#full-rebuild").onclick = () => rebuild(false);
$("#cancel").onclick = async () => { const p = selected(); if (p && busy(p)) { p.state = "cancelling"; await api.cancel(p.id); render(); } };
$("#quick-cancel").onclick = () => $("#cancel").click();
$("#structure-tab").onclick = () => setTab("structure");
$("#issues-tab").onclick = () => setTab("issues");
$("#search").oninput = renderTree;
$("#tree-filter").onchange = renderTree;
$("#expand-all").onclick = () => document.querySelectorAll("#tree details").forEach((node) => { node.open = true; });
$("#collapse-all").onclick = () => document.querySelectorAll("#tree details").forEach((node, index) => { node.open = index === 0; });
$("#close-preview").onclick = () => { $("#file-preview").hidden = true; };
$("#clear-log").onclick = () => { if (selected()) { selected().log = []; render(); } };
for (const key of ["versionLimits", "relocatable", "installSizes", "scripts"]) $(`#fix-${key}`).onchange = (event) => { selected().options[key] = event.target.checked; renderIssues(); };
$("#output-name").oninput = (event) => { if (selected()) selected().options.outputName = event.target.value; };
$("#quick-drop").onclick = open;
$("#quick-drop").onkeydown = (event) => { if (["Enter", " "].includes(event.key)) { event.preventDefault(); open(); } };
document.addEventListener("dragover", (event) => { event.preventDefault(); document.body.classList.add("drag-target"); });
document.addEventListener("dragleave", (event) => { if (!event.relatedTarget) document.body.classList.remove("drag-target"); });
document.addEventListener("drop", async (event) => {
  event.preventDefault(); document.body.classList.remove("drag-target");
  try { await receive(await api.drop([...event.dataTransfer.files])); } catch (error) { showError(error); }
});
document.addEventListener("languagechange", () => { render(); setTab(activeTab); });
api?.onEvent((event) => { const p = projects.get(event.id); if (p && event.type === "log") appendLog(p, event.message); });
api?.onOpen((files) => receive(files).catch(showError));
api?.onMenu((action) => {
  if (action === "open") open();
  if (action === "rebuild") rebuild($("#site").dataset.view === "overview");
  if (action === "settings" && $("#welcome").hidden) $("#system-open").click();
});
if (api) {
  api.info().then((info) => { version = info.version; outputDirectory = info.outputDirectory; document.querySelectorAll("[data-app-version]").forEach((el) => { el.textContent = version; }); render(); }).catch(showError);
} else {
  $("#error").hidden = false; $("#error").textContent = "Desktop bridge unavailable. Open Packager.app / 请打开 Packager.app";
}
render();

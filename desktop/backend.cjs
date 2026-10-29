const { spawn } = require("node:child_process");
const readline = require("node:readline");

// One process group per operation lets cancellation stop pkgutil/pkgbuild too.
function runBackend(executable, request, onEvent) {
  const child = spawn(executable, ["--rpc"], { detached: true, stdio: ["pipe", "pipe", "pipe"] });
  let settled = false, cancelled = false, stderr = "", final;
  const promise = new Promise((resolve, reject) => {
    readline.createInterface({ input: child.stdout }).on("line", (line) => {
      try {
        const event = JSON.parse(line);
        if (event.type === "result" || event.type === "error") final = event;
        onEvent(event);
      } catch { /* Never treat command output as a control message. */ }
    });
    child.stderr.on("data", (chunk) => { stderr = (stderr + chunk).slice(-8000); });
    child.on("error", (error) => { settled = true; reject(error); });
    child.on("close", (code, signal) => {
      settled = true;
      if (final?.type === "result" && code === 0) resolve(final.value);
      else {
        const error = new Error(cancelled ? "Operation cancelled / 操作已取消" : final?.message || (signal ? "Operation cancelled / 操作已取消" : stderr || `Backend exited (${code})`));
        error.authorization = final?.authorization;
        reject(error);
      }
    });
    child.stdin.on("error", () => {});
    child.stdin.end(JSON.stringify(request) + "\n");
  });
  return { promise, pid: child.pid, cancel() { if (!settled) { cancelled = true; try { process.kill(-child.pid, "SIGTERM"); } catch {} } } };
}
module.exports = { runBackend };

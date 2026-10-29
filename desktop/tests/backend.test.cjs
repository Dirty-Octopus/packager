const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const { runBackend } = require("../backend.cjs");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");
const execute = promisify(execFile);

test("backend errors are returned without pretending an output succeeded", async () => {
  const executable = path.resolve("../.build/backend/Packager");
  const events = [];
  const job = runBackend(executable, { operation: "inspect", source: "/nonexistent/Packager-test.pkg", workspace: path.join(os.tmpdir(), "Packager-missing-test") }, (event) => events.push(event));
  await assert.rejects(job.promise, /no longer exists|不存在/);
  assert.equal(events.at(-1).type, "error");
  assert.equal(events.some((event) => event.type === "result"), false);
  await fs.rm(path.join(os.tmpdir(), "Packager-missing-test"), { force: true, recursive: true });
});

test("cancel terminates the worker's child command as well", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "Packager-cancel-test-"));
  const helper = path.join(directory, "worker");
  await fs.writeFile(helper, '#!/bin/sh\nread -r input\n/bin/sleep 30 &\nchild=$!\nprintf \'{"type":"log","pid":%s}\\n\' "$child"\nwait "$child"\n', { mode: 0o755 });
  let ready;
  const started = new Promise((resolve) => { ready = resolve; });
  const job = runBackend(helper, {}, (event) => ready(event.pid));
  const rejected = assert.rejects(job.promise, /cancelled/);
  const pid = await started;
  job.cancel();
  await rejected;
  await new Promise((resolve) => setTimeout(resolve, 150));
  assert.throws(() => process.kill(pid, 0), /ESRCH/);
  await fs.rm(directory, { recursive: true, force: true });
});

test("actual Swift worker cancellation leaves no running pkgutil child", { skip: !process.env.PACKAGER_TEST_ORIGINAL }, async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "Packager-native-cancel-"));
  const job = runBackend(path.resolve("../.build/backend/Packager"), { operation: "inspect", source: process.env.PACKAGER_TEST_ORIGINAL, workspace: directory, language: "en" }, () => {});
  const rejection = assert.rejects(job.promise, /cancelled/);
  let child;
  for (let index = 0; index < 30 && !child; index++) {
    const { stdout } = await execute("/bin/ps", ["-axo", "pid=,ppid=,pgid=,comm="]);
    child = stdout.split("\n").map((line) => line.trim().split(/\s+/)).find((row) => Number(row[1]) === job.pid && row[3]?.includes("pkgutil"));
    if (!child) await new Promise((resolve) => setTimeout(resolve, 10));
  }
  assert.ok(child, "Expected to observe a real pkgutil child");
  job.cancel();
  await rejection;
  await new Promise((resolve) => setTimeout(resolve, 200));
  assert.throws(() => process.kill(Number(child[0]), 0), /ESRCH/);
  await fs.rm(directory, { recursive: true, force: true });
});

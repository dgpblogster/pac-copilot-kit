/**
 * Stdio smoke test: starts the built server, performs the MCP handshake,
 * lists tools, and exercises explain-failure (the one verb that needs no
 * environment). Exits non-zero on any mismatch.
 */
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const serverPath = path.resolve(here, "..", "dist", "index.js");

const EXPECTED_TOOLS = [
  "plan-deployment",
  "run-pipeline",
  "backup-solution",
  "pull-agent",
  "add-knowledge-source",
  "wait-for-search",
  "explain-failure",
].sort();

const child = spawn(process.execPath, [serverPath], {
  stdio: ["pipe", "pipe", "pipe"],
});
child.stderr.on("data", (d) => process.stderr.write(`[server] ${d}`));

let buffer = "";
const pending = new Map();
let nextId = 1;

child.stdout.on("data", (d) => {
  buffer += d.toString();
  let idx;
  while ((idx = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, idx).trim();
    buffer = buffer.slice(idx + 1);
    if (!line) continue;
    const msg = JSON.parse(line);
    if (msg.id !== undefined && pending.has(msg.id)) {
      pending.get(msg.id)(msg);
      pending.delete(msg.id);
    }
  }
});

function request(method, params) {
  const id = nextId++;
  const p = new Promise((resolve, reject) => {
    pending.set(id, resolve);
    setTimeout(() => reject(new Error(`timeout waiting for ${method}`)), 60000);
  });
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  return p;
}

function notify(method, params) {
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method, params }) + "\n");
}

function fail(msg) {
  console.error(`SMOKE FAIL: ${msg}`);
  child.kill();
  process.exit(1);
}

try {
  const init = await request("initialize", {
    protocolVersion: "2024-11-05",
    capabilities: {},
    clientInfo: { name: "smoke", version: "0.0.0" },
  });
  if (!init.result?.serverInfo?.name?.includes("pac-copilot-kit")) fail("initialize: unexpected serverInfo");
  notify("notifications/initialized", {});

  const list = await request("tools/list", {});
  const names = (list.result?.tools ?? []).map((t) => t.name).sort();
  if (JSON.stringify(names) !== JSON.stringify(EXPECTED_TOOLS)) {
    fail(`tools/list mismatch. Got: ${names.join(", ")}`);
  }

  const noArg = await request("tools/call", { name: "explain-failure", arguments: {} });
  const noArgText = noArg.result?.content?.[0]?.text ?? "";
  if (!noArgText.includes("No failed tool call")) fail(`explain-failure (no args) unexpected: ${noArgText}`);

  const code16 = await request("tools/call", { name: "explain-failure", arguments: { exitCode: 16 } });
  const text16 = code16.result?.content?.[0]?.text ?? "";
  if (!text16.includes("ProfileMisaligned") || !text16.includes("preflight refusal")) {
    fail(`explain-failure(16) unexpected: ${text16}`);
  }

  const code20 = await request("tools/call", { name: "explain-failure", arguments: { exitCode: 20 } });
  if (!(code20.result?.content?.[0]?.text ?? "").includes("alternatives")) fail("explain-failure(20) unexpected");

  console.log(`SMOKE PASS: handshake, ${names.length} tools advertised, explain-failure reasoning locally.`);
  child.kill();
  process.exit(0);
} catch (err) {
  fail(err.message);
}

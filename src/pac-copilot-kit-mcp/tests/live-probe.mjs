/**
 * Live probe, run manually: exercises the full stack (MCP -> pwsh bridge ->
 * module -> guards -> typed exit code -> local reasoner) with no mutation.
 * plan-deployment is expected to be REFUSED by the profile-alignment guard
 * when the active pac profile points elsewhere, and explain-failure must then
 * explain that refusal unprompted. Requires PCK_DEFAULT_ENVIRONMENT_ID and a
 * workspace path in PCK_PROBE_WS.
 */
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const serverPath = path.resolve(here, "..", "dist", "index.js");
const ws = process.env.PCK_PROBE_WS;
if (!ws || !process.env.PCK_DEFAULT_ENVIRONMENT_ID) {
  console.error("Set PCK_PROBE_WS and PCK_DEFAULT_ENVIRONMENT_ID first.");
  process.exit(2);
}

const child = spawn(process.execPath, [serverPath], { stdio: ["pipe", "pipe", "pipe"] });
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

function request(method, params, timeoutMs = 180000) {
  const id = nextId++;
  const p = new Promise((resolve, reject) => {
    pending.set(id, resolve);
    setTimeout(() => reject(new Error(`timeout waiting for ${method}`)), timeoutMs);
  });
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  return p;
}

function fail(msg) {
  console.error(`LIVE PROBE FAIL: ${msg}`);
  child.kill();
  process.exit(1);
}

try {
  await request("initialize", { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "probe", version: "0" } });
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized", params: {} }) + "\n");

  const plan = await request("tools/call", {
    name: "plan-deployment",
    arguments: { solutionName: "PckPipelineProbe", sourcePath: ws, publisherPrefix: "wrk" },
  });
  const planText = plan.result?.content?.[0]?.text ?? "";
  console.log(`plan-deployment says:\n${planText}\n`);

  if (plan.result?.isError) {
    if (!planText.includes("16") || !planText.includes("ProfileMisaligned")) {
      fail(`expected a ProfileMisaligned refusal, got: ${planText}`);
    }
    const why = await request("tools/call", { name: "explain-failure", arguments: {} });
    const whyText = why.result?.content?.[0]?.text ?? "";
    console.log(`explain-failure says:\n${whyText}\n`);
    if (!whyText.includes("ProfileMisaligned") || !whyText.includes("pac auth")) {
      fail(`explain-failure did not explain the refusal: ${whyText}`);
    }
    console.log("LIVE PROBE PASS: the guard refused through the full stack, and explain-failure explained it unprompted.");
  } else {
    // Aligned profile: the plan itself must be clean whatif steps.
    if (!planText.includes("whatif")) fail(`expected a whatif plan, got: ${planText}`);
    console.log("LIVE PROBE PASS: aligned profile, clean plan.");
  }
  child.kill();
  process.exit(0);
} catch (err) {
  fail(err.message);
}

#!/usr/bin/env node
/**
 * pac-copilot-kit-mcp: local MCP server over stdio (design 8.1). A thin shim:
 * every user-facing behavior lives in the PacCopilotKit PowerShell module
 * (canon 2); this process is contract translation only.
 *
 * Startup preflight (design 8.2): pwsh, pac, and the module are verified once
 * before the server advertises tools. Any failure is a clear stderr message
 * and a non-zero exit, never a silent tool-not-found later.
 */
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { modulePath, runRaw } from "./pwsh.js";
import { registerPipelineTools } from "./tools/pipeline.js";
import { registerKnowledgeTools } from "./tools/knowledge.js";
import { registerLifecycleTools } from "./tools/lifecycle.js";
import { registerExplainTool } from "./tools/explain.js";

async function startupChecks(): Promise<void> {
  if (process.env.PCK_MCP_SKIP_STARTUP_CHECKS === "1") return;

  const pwsh = await runRaw("$PSVersionTable.PSVersion.ToString()");
  if (pwsh.exitCode !== 0) {
    throw new Error("PowerShell 7.4+ (pwsh) was not found on the PATH. Install it from https://aka.ms/powershell and retry.");
  }
  const [major, minor] = pwsh.stdout.split(".").map((n) => parseInt(n, 10));
  if (Number.isNaN(major) || major < 7 || (major === 7 && minor < 4)) {
    throw new Error(`PowerShell ${pwsh.stdout} is below the 7.4 floor.`);
  }

  const mod = await runRaw(
    `Import-Module '${modulePath().replace(/'/g, "''")}' -ErrorAction Stop; (Get-Module PacCopilotKit).Version.ToString()`,
  );
  if (mod.exitCode !== 0) {
    throw new Error(
      `The PacCopilotKit module could not be imported (looked for: ${modulePath()}). Set PCK_MODULE_PATH to the module psd1, or install the module. Underlying error: ${mod.stderr}`,
    );
  }

  const pac = await runRaw("if (Get-Command pac -CommandType Application -ErrorAction Ignore) { 'ok' } else { exit 13 }");
  if (pac.exitCode !== 0) {
    throw new Error("The pac CLI is not on the PATH. Install it from https://aka.ms/PowerPlatformCLI and retry.");
  }

  console.error(`pac-copilot-kit-mcp: preflight ok (pwsh ${pwsh.stdout}, module ${mod.stdout}).`);
}

async function main(): Promise<void> {
  await startupChecks();

  const server = new McpServer({ name: "pac-copilot-kit", version: "0.1.0" });
  registerPipelineTools(server);
  registerKnowledgeTools(server);
  registerLifecycleTools(server);
  registerExplainTool(server);

  await server.connect(new StdioServerTransport());
  console.error("pac-copilot-kit-mcp: serving 7 tools over stdio.");
}

main().catch((err: Error) => {
  console.error(`pac-copilot-kit-mcp: startup failed. ${err.message}`);
  process.exit(1);
});

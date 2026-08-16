/**
 * The bridge to the PacCopilotKit PowerShell module. One pwsh process per tool
 * call, no long-lived state (design 8.4), and injection-safe by construction:
 * tool arguments never touch the command line. They travel as JSON in an
 * environment variable and are splatted inside PowerShell, so no spelling of
 * an argument can rewrite the command.
 */
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

export interface PwshResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

/** Cmdlets the bridge will run. Nothing outside this list is ever executed. */
export const CMDLET_ALLOWLIST = [
  "Invoke-PckCopilotPipeline",
  "Export-PckSolutionBackup",
  "New-PckKnowledgeSource",
  "Wait-PckDataverseSearchReady",
  "Sync-PckCopilotAgent",
] as const;
export type AllowedCmdlet = (typeof CMDLET_ALLOWLIST)[number];

/**
 * Resolve the module to import: PCK_MODULE_PATH wins, then the repo-local
 * module when running from source, then the installed-module name for the
 * PowerShell Gallery future.
 */
export function modulePath(): string {
  if (process.env.PCK_MODULE_PATH) return process.env.PCK_MODULE_PATH;
  const here = path.dirname(fileURLToPath(import.meta.url));
  const repoLocal = path.resolve(here, "..", "..", "PacCopilotKit", "PacCopilotKit.psd1");
  if (existsSync(repoLocal)) return repoLocal;
  return "PacCopilotKit";
}

const bridgeScript = `
$ErrorActionPreference = 'Stop'
try {
    Import-Module $env:PCK_MCP_MODULE -ErrorAction Stop
    $params = @{}
    if ($env:PCK_MCP_ARGS) { $params = $env:PCK_MCP_ARGS | ConvertFrom-Json -AsHashtable }
    if ($env:PCK_MCP_CONNECT -eq '1') {
        $connect = @{}
        if ($env:PCK_MCP_ENV) { $connect.EnvironmentId = $env:PCK_MCP_ENV }
        Connect-PckPowerPlatform @connect | Out-Null
    }
    $whatIf = $env:PCK_MCP_WHATIF -eq '1'
    & $env:PCK_MCP_CMDLET @params -Json -WhatIf:$whatIf
    exit 0
}
catch {
    $code = 1
    if ($_.Exception.PSObject.Properties['ExitCode']) { $code = [int]$_.Exception.ExitCode }
    [Console]::Error.WriteLine($_.Exception.Message)
    exit $code
}
`;

export interface RunOptions {
  /** Run Connect-PckPowerPlatform before the cmdlet (most cmdlets need it). */
  connect?: boolean;
  /** Explicit environment id for the connect step. */
  environmentId?: string;
  /** Pass -WhatIf:$true, the plan-deployment surface. */
  whatIf?: boolean;
}

export function runCmdlet(
  cmdlet: AllowedCmdlet,
  args: Record<string, unknown>,
  options: RunOptions = {},
): Promise<PwshResult> {
  if (!CMDLET_ALLOWLIST.includes(cmdlet)) {
    return Promise.resolve({ exitCode: 1, stdout: "", stderr: `Cmdlet '${cmdlet}' is not allowlisted.` });
  }
  const env: NodeJS.ProcessEnv = {
    ...process.env,
    PCK_MCP_CMDLET: cmdlet,
    PCK_MCP_ARGS: JSON.stringify(args),
    PCK_MCP_MODULE: modulePath(),
    PCK_MCP_CONNECT: options.connect ? "1" : "0",
    PCK_MCP_WHATIF: options.whatIf ? "1" : "0",
  };
  if (options.environmentId) env.PCK_MCP_ENV = options.environmentId;

  return new Promise((resolve) => {
    const child = spawn("pwsh", ["-NoProfile", "-NoLogo", "-NonInteractive", "-Command", bridgeScript], {
      env,
      windowsHide: true,
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d: Buffer) => (stdout += d.toString()));
    child.stderr.on("data", (d: Buffer) => (stderr += d.toString()));
    child.on("close", (code) => resolve({ exitCode: code ?? 1, stdout: stdout.trim(), stderr: stderr.trim() }));
    child.on("error", (err) => resolve({ exitCode: 1, stdout: "", stderr: `Could not start pwsh: ${err.message}` }));
  });
}

/** Run a raw preflight command (startup checks only; no tool arguments involved). */
export function runRaw(command: string): Promise<PwshResult> {
  return new Promise((resolve) => {
    const child = spawn("pwsh", ["-NoProfile", "-NoLogo", "-NonInteractive", "-Command", command], {
      windowsHide: true,
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d: Buffer) => (stdout += d.toString()));
    child.stderr.on("data", (d: Buffer) => (stderr += d.toString()));
    child.on("close", (code) => resolve({ exitCode: code ?? 1, stdout: stdout.trim(), stderr: stderr.trim() }));
    child.on("error", (err) => resolve({ exitCode: 1, stdout: "", stderr: `Could not start pwsh: ${err.message}` }));
  });
}

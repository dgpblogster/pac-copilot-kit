/**
 * Shared plumbing for the tool handlers: run a cmdlet through the bridge,
 * convert the result to MCP content, and remember the last failure so
 * explain-failure can reason over it without another round trip.
 */
import { runCmdlet, type AllowedCmdlet, type RunOptions } from "../pwsh.js";
import { EXIT_CODES } from "../exitCodes.js";

export interface LastFailure {
  tool: string;
  exitCode: number;
  message: string;
}

let lastFailure: LastFailure | null = null;

export function getLastFailure(): LastFailure | null {
  return lastFailure;
}

export interface ToolContent {
  [key: string]: unknown;
  content: Array<{ [key: string]: unknown; type: "text"; text: string }>;
  isError?: boolean;
}

export async function invoke(
  tool: string,
  cmdlet: AllowedCmdlet,
  args: Record<string, unknown>,
  options: RunOptions = {},
): Promise<ToolContent> {
  // Drop undefined values so PowerShell splatting only sees real parameters.
  const cleaned: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(args)) {
    if (value !== undefined && value !== null) cleaned[key] = value;
  }

  const result = await runCmdlet(cmdlet, cleaned, options);

  if (result.exitCode !== 0) {
    lastFailure = { tool, exitCode: result.exitCode, message: result.stderr || result.stdout };
    const info = EXIT_CODES[result.exitCode];
    const label = info ? `${result.exitCode} (${info.name})` : `${result.exitCode}`;
    return {
      isError: true,
      content: [
        {
          type: "text",
          text: `Failed with exit code ${label}.\n${result.stderr || result.stdout}\n\nCall explain-failure for what this code means and what to do next.`,
        },
      ],
    };
  }

  return { content: [{ type: "text", text: result.stdout || "(no output)" }] };
}

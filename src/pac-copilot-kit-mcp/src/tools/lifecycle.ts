/**
 * backup-solution and pull-agent: the remaining lifecycle verbs (design 8.3).
 */
import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { invoke } from "./shared.js";

export function registerLifecycleTools(server: McpServer): void {
  server.registerTool(
    "backup-solution",
    {
      description:
        "Export a solution to a timestamp-suffixed zip on disk in one call. The export is a backup, explicitly not a source of truth: the repository defines the agent.",
      inputSchema: {
        solutionName: z.string().describe("Solution unique name."),
        path: z.string().describe("Directory for the zip. Absolute, or relative to PCK_WORKSPACE_ROOT."),
        managed: z.boolean().optional().describe("Export as managed. Default false."),
        environmentId: z.string().optional().describe("Target environment id (GUID). Falls back to PCK_DEFAULT_ENVIRONMENT_ID."),
      },
    },
    async (args) =>
      invoke(
        "backup-solution",
        "Export-PckSolutionBackup",
        {
          SolutionName: args.solutionName,
          Path: args.path,
          Managed: args.managed,
        },
        { connect: true, environmentId: args.environmentId },
      ),
  );

  server.registerTool(
    "pull-agent",
    {
      description:
        "Pull remote agent changes from Copilot Studio into a local workspace, with the environment pinned and the machine-global pac profile verified first, so the pull cannot silently read from the wrong environment. The workspace must already be connected to an agent (pac copilot init --environment, or clone).",
      inputSchema: {
        sourcePath: z.string().describe("The pac copilot workspace. Absolute, or relative to PCK_WORKSPACE_ROOT."),
        environmentId: z.string().optional().describe("Target environment id (GUID). Falls back to PCK_DEFAULT_ENVIRONMENT_ID."),
      },
    },
    async (args) =>
      invoke(
        "pull-agent",
        "Sync-PckCopilotAgent",
        {
          SourcePath: args.sourcePath,
          EnvironmentId: args.environmentId,
        },
      ),
  );
}

/**
 * plan-deployment and run-pipeline: the same guarded loop, dry-run and real.
 * plan-deployment wraps Invoke-PckCopilotPipeline -WhatIf (design 8.3).
 */
import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { invoke } from "./shared.js";

const pipelineShape = {
  solutionName: z.string().describe("Solution unique name (letters, digits, underscores)."),
  sourcePath: z.string().describe("The pac copilot workspace. Absolute path, or relative to PCK_WORKSPACE_ROOT."),
  publisherPrefix: z.string().describe("Publisher customization prefix, 2 to 8 alphanumerics."),
  environmentId: z.string().optional().describe("Target environment id (GUID). Falls back to PCK_DEFAULT_ENVIRONMENT_ID."),
};

function toParams(args: { solutionName: string; sourcePath: string; publisherPrefix: string; environmentId?: string }) {
  return {
    SolutionName: args.solutionName,
    SourcePath: args.sourcePath,
    PublisherPrefix: args.publisherPrefix,
    EnvironmentId: args.environmentId,
  };
}

export function registerPipelineTools(server: McpServer): void {
  server.registerTool(
    "plan-deployment",
    {
      description:
        "Dry-run the deployment: connect, verify the pac floor and profile alignment, lint the workspace offline, and report the pack and import that a real run would perform. Nothing is mutated. Prefer offering this plan before run-pipeline.",
      inputSchema: pipelineShape,
    },
    async (args) => invoke("plan-deployment", "Invoke-PckCopilotPipeline", toParams(args), { whatIf: true }),
  );

  server.registerTool(
    "run-pipeline",
    {
      description:
        "The paved road: preflight, offline lint, pac copilot pack, pac solution import with publish, against the pinned environment. Forward from source; the repository defines the agent. Stops at the first failure with a typed exit code.",
      inputSchema: pipelineShape,
    },
    async (args) => invoke("run-pipeline", "Invoke-PckCopilotPipeline", toParams(args)),
  );
}

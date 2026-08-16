/**
 * explain-failure: the one verb with no cmdlet behind it (design 8.3). Turns
 * the guardrail funnel's typed exit codes into agent-consumable prose, locally,
 * without another Dataverse round trip.
 */
import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { explain } from "../exitCodes.js";
import { getLastFailure } from "./shared.js";

export function registerExplainTool(server: McpServer): void {
  server.registerTool(
    "explain-failure",
    {
      description:
        "Explain what a kit failure means and what to do next, from the typed exit code. With no arguments, explains the most recent failed tool call in this session. Costs nothing: no environment round trip.",
      inputSchema: {
        exitCode: z.number().optional().describe("An exit code to explain. Omit to use the last failure in this session."),
        message: z.string().optional().describe("The error message that came with it, for context."),
      },
    },
    async (args) => {
      if (args.exitCode !== undefined) {
        return { content: [{ type: "text" as const, text: explain(args.exitCode, args.message) }] };
      }
      const last = getLastFailure();
      if (!last) {
        return {
          content: [
            {
              type: "text" as const,
              text: "No failed tool call has happened in this session, and no exitCode argument was given. Nothing to explain.",
            },
          ],
        };
      }
      return {
        content: [{ type: "text" as const, text: `Explaining the last failure, from tool '${last.tool}'.\n${explain(last.exitCode, last.message)}` }],
      };
    },
  );
}

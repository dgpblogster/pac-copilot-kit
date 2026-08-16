/**
 * add-knowledge-source and wait-for-search: pillar A over MCP. The seventh
 * verb (add-knowledge-source) exists precisely because this capability has no
 * pac path at all (design 12.10).
 */
import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { invoke } from "./shared.js";

export function registerKnowledgeTools(server: McpServer): void {
  server.registerTool(
    "add-knowledge-source",
    {
      description:
        "Wire a Dataverse knowledge source into a Copilot Studio agent: the one thing pac cannot do. Preflights the harness (standard only), the end-user auth mode (Integrated only), and the solution, creates the records inside the solution, rolls back on mid-chain failure, and reports the preconditions it cannot solve (org search flag, find columns). A refusal here means the source would display but never be queried; do not work around it.",
      inputSchema: {
        botName: z.string().optional().describe("Agent display name or schema name; must match exactly one agent. Pass this or botId."),
        botId: z.string().optional().describe("Agent id (GUID). Pass this or botName."),
        table: z.array(z.string()).describe("Logical names of the Dataverse tables to ground on."),
        solutionName: z.string().describe("Solution unique name the records land in."),
        displayName: z.string().optional().describe("Friendly name makers see in the Knowledge tab."),
        searchName: z.string().optional().describe("Machine-style table search name. Defaults to '<first table>_search'."),
        componentName: z.string().optional().describe("Tail of the component schema name. Defaults to the first table's logical name."),
        environmentId: z.string().optional().describe("Target environment id (GUID). Falls back to PCK_DEFAULT_ENVIRONMENT_ID."),
      },
    },
    async (args) =>
      invoke(
        "add-knowledge-source",
        "New-PckKnowledgeSource",
        {
          BotName: args.botName,
          BotId: args.botId,
          Table: args.table,
          SolutionName: args.solutionName,
          DisplayName: args.displayName,
          SearchName: args.searchName,
          ComponentName: args.componentName,
        },
        { connect: true, environmentId: args.environmentId },
      ),
  );

  server.registerTool(
    "wait-for-search",
    {
      description:
        "Block until seeded rows are actually searchable, by polling the search query endpoint. Never trusts the status endpoint, which reports zero indexed tables while queries succeed. Initial index provisioning genuinely takes hours on a fresh environment: long waits are real waits, so do not kill this early and conclude failure.",
      inputSchema: {
        table: z.array(z.string()).describe("Logical names of the tables to probe."),
        searchText: z.string().describe("A term the seeded content actually contains. An empty table matches nothing."),
        timeoutMinutes: z.number().optional().describe("How long to keep polling. The cmdlet default is 150 minutes, sized for real provisioning."),
        intervalSeconds: z.number().optional().describe("Seconds between probes. Default 60."),
        environmentId: z.string().optional().describe("Target environment id (GUID). Falls back to PCK_DEFAULT_ENVIRONMENT_ID."),
      },
    },
    async (args) =>
      invoke(
        "wait-for-search",
        "Wait-PckDataverseSearchReady",
        {
          Table: args.table,
          SearchText: args.searchText,
          TimeoutMinutes: args.timeoutMinutes,
          IntervalSeconds: args.intervalSeconds,
        },
        { connect: true, environmentId: args.environmentId },
      ),
  );
}

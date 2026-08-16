# pac-copilot-kit-mcp

A local MCP server (stdio) that gives AI agents a guarded Microsoft Copilot Studio lifecycle: deploy an agent from source, wire Dataverse knowledge sources (the step `pac` cannot do), wait for real search readiness, pull, and back up, with every operation preflighted and every refusal typed and explainable.

This is the thin shim over the `PacCopilotKit` PowerShell module, which is the engine and must be installed for the server to start. Seven verbs: `plan-deployment`, `run-pipeline`, `add-knowledge-source`, `wait-for-search`, `pull-agent`, `backup-solution`, and `explain-failure`, which turns any typed refusal into what-happened-and-what-to-do prose without an environment round trip.

## Quick start

```jsonc
// Claude Code (.mcp.json) or similar for your MCP client
{
  "mcpServers": {
    "pac-copilot-kit": {
      "command": "npx",
      "args": ["-y", "pac-copilot-kit-mcp"],
      "env": { "PCK_DEFAULT_ENVIRONMENT_ID": "<your environment id>" }
    }
  }
}
```

Requirements: PowerShell 7.4+ (`pwsh`), the `PacCopilotKit` module (PowerShell Gallery), the `pac` CLI 2.10.1+, Node 20+. The server verifies all of it at startup and fails loudly with the fix named, rather than surfacing a mysterious tool error later.

Full documentation, client configs for VS Code and Codex CLI, environment variable reference, and troubleshooting: https://github.com/dgpblogster/pac-copilot-kit

MIT license. By Mariano Gomez Bent, The Workbench Blog.

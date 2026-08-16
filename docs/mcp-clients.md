# MCP clients: installing and using pac-copilot-kit-mcp

The MCP server is the kit's second door. The PowerShell module is the engine and the source of truth; `pac-copilot-kit-mcp` exposes that same engine to AI agents as seven task-shaped verbs over stdio. Every guardrail, every typed exit code, and every refusal message is the module's; the server adds contract translation and nothing else.

## Prerequisites

| Requirement | Why |
|---|---|
| PowerShell 7.4+ (`pwsh`) | The engine runs in it; the server verifies the floor at startup |
| `pac` CLI 2.10.1+ | The pipeline and pull verbs drive it |
| Node 20+ | The server itself |
| The `PacCopilotKit` module | The server refuses to start without it |
| A Web API token source | A signed-in Azure CLI (`az login`), `PCK_ACCESS_TOKEN`, `Az.Accounts`, or the three `PCK_SPN_*` variables in CI |

## Install

```powershell
Install-Module PacCopilotKit     # the engine; the server refuses to start without it
```

The server itself needs no install step: every client config launches it with `npx -y pac-copilot-kit-mcp`, which fetches and runs the published package.

Contributors working from a clone build it instead (`cd src/pac-copilot-kit-mcp; npm install; npm run build; npm run smoke`) and point their client at `node <clone>/src/pac-copilot-kit-mcp/dist/index.js`; the repo-local module is picked up automatically, or set `PCK_MODULE_PATH`.

## Wire up your client

Copy the matching sample from [samples/mcp-config](../samples/mcp-config) and set your environment id.

**Claude Code**: `.mcp.json` at the root of the project where you work on the agent. **VS Code (GitHub Copilot)**: `.vscode/mcp.json` in the workspace. **Codex CLI**: merge into `~/.codex/config.toml`.

All three carry the same two essentials: the launcher (`npx -y pac-copilot-kit-mcp`) and `PCK_DEFAULT_ENVIRONMENT_ID` in the `env` block. Everything else is optional.

## Environment variables the server understands

| Variable | Purpose |
|---|---|
| `PCK_DEFAULT_ENVIRONMENT_ID` | The pinned environment. Tools also accept an explicit `environmentId` argument, which wins. |
| `PCK_WORKSPACE_ROOT` | Base for relative paths in tool arguments. Without it, relative paths are refused (exit 17). |
| `PCK_MODULE_PATH` | Override the module location. Defaults to the repo-local module when running from a clone, then the installed module. |
| `PCK_ACCESS_TOKEN` | Explicit Web API bearer token; wins over every other dev source. |
| `PCK_SPN_TENANT`, `PCK_SPN_APP_ID`, `PCK_SPN_SECRET` | The complete set switches every cmdlet to CI (service principal) mode. |

## The seven verbs

| Verb | What it does | Wraps |
|---|---|---|
| `plan-deployment` | Dry run: preflight, profile alignment, offline lint, and a report of what the real run would do. Nothing mutates. | `Invoke-PckCopilotPipeline -WhatIf` |
| `run-pipeline` | Validate, pack, import, publish, against the pinned environment. | `Invoke-PckCopilotPipeline` |
| `add-knowledge-source` | Wire a Dataverse knowledge source into an agent: the thing `pac` cannot do. Preflights harness, auth mode, and solution; rolls back on mid-chain failure. | `New-PckKnowledgeSource` |
| `wait-for-search` | Poll until seeded rows are actually searchable. Never trusts the status endpoint. | `Wait-PckDataverseSearchReady` |
| `pull-agent` | Pull remote agent changes into the local workspace, profile-verified first. | `Sync-PckCopilotAgent` |
| `backup-solution` | One-call export to a timestamped zip. A backup, not a source of truth. | `Export-PckSolutionBackup` |
| `explain-failure` | Turn a typed exit code into what-happened-and-what-to-do prose, locally. With no arguments, explains the session's last failure. | Nothing; it reasons over the exit-code registry |

In practice, nobody calls verbs by name. You ask your agent for the outcome ("plan a deployment of this workspace to the sandbox", "add the case resolutions table as knowledge on the support agent") and the verb descriptions do the routing. The verbs return the same JSON the cmdlets emit with `-Json`.

## When something is refused

Refusals arrive with a typed exit code: 10 through 19 are preflight checks (fix the named condition; retrying unchanged is pointless), 20 is a known-broken platform route with working alternatives named in the message, 1 is an ordinary failure. The failure text tells the agent to call `explain-failure`, which expands the code into meaning and next steps without touching the environment.

One rule matters more than the rest, for humans and agents alike: a refusal encodes a documented platform failure that is silent when hit raw. An agent that works around a harness or auth-mode refusal by calling the Web API directly gets a knowledge source that displays in the portal and is never queried, with no error anywhere. The refusal is the feature.

## Troubleshooting startup

The server verifies its world before advertising tools, so startup failures are specific:

- **"pwsh was not found"**: install PowerShell 7.4+ and make sure `pwsh` (not `powershell`) resolves.
- **"The PacCopilotKit module could not be imported"**: the message includes the path it tried; set `PCK_MODULE_PATH` to the `.psd1`, or run from a full clone so the repo-local default resolves.
- **"The pac CLI is not on the PATH"**: install it from https://aka.ms/PowerPlatformCLI.

If the server starts but a tool call fails immediately with exit 10 or 11, the environment id or the token source is missing from the `env` block; both are listed in the table above.

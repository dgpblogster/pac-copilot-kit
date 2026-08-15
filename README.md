# pac-copilot-kit

A paved-road toolkit for the Microsoft Copilot Studio agent lifecycle, built on the Power Platform CLI (`pac`) and the Dataverse Web API.

> **Status: pre-release.** The design is settled and recorded in [docs/pac-copilot-kit-design.md](docs/pac-copilot-kit-design.md). Code is being scaffolded. Nothing here is installable yet.

## Why this exists

Two reasons, and every feature traces to one of them.

**Pillar A, capability. Do what `pac` cannot.** Copilot Studio's Dataverse knowledge sources have no code path. `pac copilot pack` rejects a Dataverse source definition placed in the workspace `knowledge/` folder, while website and SharePoint sources pack fine. The maker portal is the only documented route. This kit creates them through the Dataverse Web API instead, in-solution and repeatably, and owns the whole grounding chain around them rather than the record creates alone.

**Pillar B, paved road. Make the published ALM prescription executable.** Microsoft's Copilot Studio ALM guidance is sound and has not wavered: solutions, a custom publisher and prefix, environment variables for what changes between environments, source control, at least three environments. What is missing is the road. There is no agent task in Power Platform Build Tools, no agent-aware GitHub Action, and no reference pipeline that runs `pac copilot pack` followed by `pac solution import`, even though pack is documented as safe to run in a build pipeline. This kit is that missing primitive, installable in an ordinary script step.

Stated precisely: Copilot Studio ALM is **prescribed but not automatable**. This kit does not invent an ALM story. It makes the published one executable.

## What it is not

Not a `pac` replacement. Not an authoring tool for topic YAML. Not a hosted service. Not an eval harness. Not coupled to any one product or tenant. Full non-goals are in the design doc.

It also does not close the gap in `pac`; it works around it. If a future `pac` release grows a real code path for Dataverse knowledge sources, this kit's job there shrinks to guards.

## Shape

Two components, one engine.

- **`PacCopilotKit`**, a PowerShell module. The engine and the source of truth. No interactive prompts, explicit environment id on every call, solution-aware by default, structured output, non-zero exit codes.
- **`pac-copilot-kit-mcp`**, a local MCP server over stdio. A thin shim that shells to the module, so the same guarded lifecycle is available from Claude Code, GitHub Copilot in VS Code, and ChatGPT Codex CLI.

Everything user-facing lives in the module. The MCP layer is contract translation only.

## The loop, end to end

The kit does not replace `pac`; it fills in around it. `pac` owns authoring, packing, and the solution lifecycle. The kit owns environment discipline, preflight, the knowledge wiring `pac` cannot do, readiness, and backup. One full pass from empty folder to grounded agent:

```powershell
# ── 0. Tooling floor, once per machine ─────────────────────────────────────────
pac --version                        # 2.10.1 or later
$PSVersionTable.PSVersion            # 7.4 or later

# ── 1. Author locally (pac owns this) ──────────────────────────────────────────
pac copilot init                     # scaffold; creates nothing in Dataverse
# edit agent.mcs.yml, settings.mcs.yml, topics/*.mcs.yml
# schema-check every .mcs.yml offline before anything is packed; a Power Fx
# string containing ": " parses wrong and surfaces as runtime behavior, not
# as an error

# ── 2. Pin the environment, once per shell ─────────────────────────────────────
# The kit never trusts the pac auth profile default org; the id is always
# explicit. pac gets its own auth for its own commands.
$env:PCK_DEFAULT_ENVIRONMENT_ID = '00000000-0000-0000-0000-000000000000'
pac auth create --environment $env:PCK_DEFAULT_ENVIRONMENT_ID

# ── 3. Connect and preflight (kit) ─────────────────────────────────────────────
# Token comes from the signed-in Azure CLI (az login), PCK_ACCESS_TOKEN, or
# Az.Accounts; never from pac state. In CI, set PCK_SPN_TENANT, PCK_SPN_APP_ID,
# and PCK_SPN_SECRET and the same two lines work unchanged.
Import-Module PacCopilotKit
Connect-PckPowerPlatform             # discovery, WhoAmI verification, cached context

# Confirm the agent is the standard harness BEFORE wiring knowledge. The newer
# experience displays knowledge sources it never queries, with no error anywhere.
Get-PckAgentInfo -Name 'WorkbenchSupportAssistant*'
# BotId      : ...
# SchemaName : wrk_WorkbenchSupportAssistant
# Template   : default-2.1.0
# Harness    : Standard                       <- proceed only on this

# ── 4. Pack and import (pac owns this) ─────────────────────────────────────────
pac copilot pack --publisher-prefix wrk --solution-name WorkbenchSupportAssistant
pac solution import --path .\WorkbenchSupportAssistant.zip --publish-changes

# ── 5. Wire the Dataverse knowledge source (kit; the step pac cannot do) ───────
# Planned, v0.1 in progress. Creates the table (search-enabled at create time),
# the table search config, the knowledge component, and the association, every
# call inside the solution, then polls the search query endpoint (never /status)
# until seeded rows are actually searchable.
New-PckKnowledgeSource -SolutionName WorkbenchSupportAssistant `
    -TableSchemaName wrk_caseresolution -BotName WorkbenchSupportAssistant
Wait-PckDataverseSearchReady -Table wrk_caseresolution

# ── 6. Backup and commit (kit + git) ───────────────────────────────────────────
# Planned, v0.1 in progress. The export is a backup; the repository is the agent.
Export-PckSolutionBackup -SolutionName WorkbenchSupportAssistant -Path .\backups
git add . ; git commit -m "Milestone: agent deployed and grounded"
```

Or, once `Invoke-PckCopilotPipeline` lands, steps 3 through 5 collapse into one call that runs the same sequence with every guard in front of it:

```powershell
Invoke-PckCopilotPipeline -SolutionName WorkbenchSupportAssistant -SourcePath .\agent -Json
```

**Shipped today:** `Connect-PckPowerPlatform`, `Get-PckAgentInfo`, the Web API funnel with its guards, and the token chain. **Planned for v0.1:** `New-PckKnowledgeSource`, `Wait-PckDataverseSearchReady`, `Enable-PckDataverseSearch`, `Invoke-PckCopilotPipeline`, `Export-PckSolutionBackup`, and the MCP server. The division of labor above does not change as those land; only the amount of it that is automated does.

| Step | Owner | Why |
|---|---|---|
| Author topics and settings as YAML | `pac copilot init` + editor | Supported, documented, works |
| Validate YAML offline | your schema check, before pack | The import will not catch what parses wrong |
| Pack and import the solution | `pac copilot pack` + `pac solution import` | Supported, documented, works |
| Pin the environment, verify identity | kit | The pac profile is machine-global and drifts |
| Gate on harness and auth mode | kit | The failure modes are silent |
| Create Dataverse knowledge sources | kit | No `pac` path exists at all |
| Wait for real search readiness | kit | The status endpoint lies; only queries tell the truth |
| Back up the solution | kit | One call, timestamped, explicitly not the source of truth |

## Requirements

- PowerShell 7.4 or later
- Power Platform CLI 2.10.1 or later
- Node 20 LTS, for the MCP server only

## Documentation

- [Design](docs/pac-copilot-kit-design.md), the full architecture, guard funnel, and decision log
- `docs/war-stories.md`, the publishable inventory of `pac` and Dataverse gotchas the guards encode *(planned)*
- `docs/quickstart.md`, `docs/ci-recipes.md`, `docs/mcp-clients.md` *(planned)*

## A note on supportability

Part of what this kit does relies on undocumented Dataverse record shapes, discovered by inspecting what the Copilot Studio maker portal writes. Those shapes are not supported by Microsoft and can change in any release. The kit verifies rather than assumes, and the affected surface is called out explicitly in the design doc and the war-stories reference. Use it for development and ALM automation with that in mind.

## License

MIT. See [LICENSE](LICENSE).

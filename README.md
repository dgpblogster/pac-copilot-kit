# pac-copilot-kit

A paved-road toolkit for the Microsoft Copilot Studio agent lifecycle, built on the Power Platform CLI (`pac`) and the Dataverse Web API.

> **Status: pre-release.** The design is settled and recorded in [docs/pac-copilot-kit-design.md](docs/pac-copilot-kit-design.md). The PowerShell module works from source today (`Import-Module ./src/PacCopilotKit/PacCopilotKit.psd1`) and its headline path has been proven against a live environment. The PowerShell Gallery publish and the MCP server are still ahead, so nothing is `Install-Module`-able just yet.

## Why this kit exists

This kit was born inside a real project: a support agent grounded on Dataverse knowledge articles and a custom table of curated case resolutions, treated as code from day one, deployed from source, and rebuilt from scratch more times than I care to admit. Along the way, two problems kept coming back, and every feature here traces to one of them.

**First, there is a hole in the tooling.** Copilot Studio's Dataverse knowledge sources, the one source type that lives in the same platform as the agent itself, cannot be created by `pac` at all. Website sources pack fine from YAML, SharePoint sources pack fine, and a Dataverse source definition gets rejected outright, which leaves the maker portal as the only documented route. Now, clicking a portal is not a deployment strategy. As it turns out, every knowledge source you click together materializes as a handful of ordinary Dataverse rows, and anything that is ordinary rows can be created with the Web API: inside your solution, from a pipeline, repeatably. That is pillar A, and it is the reason to install the kit.

**Second, the ALM story is prescribed but not automatable.** Microsoft's ALM guidance for Copilot Studio agents is genuinely good, and I follow it: solutions, a custom publisher and prefix, environment variables for anything that changes between environments, source control. But go looking for the pipeline that runs it and you will not find one. There is no agent task in Power Platform Build Tools, no agent-aware GitHub Action, and no reference sample anywhere that runs `pac copilot pack` followed by `pac solution import`, even though pack is documented as safe for build pipelines. The CLI was designed for CI, documented for CI, and the CI tooling has not caught up with it. This kit is that missing piece, installable in an ordinary script step. That is pillar B, and it is the reason you keep the kit around.

## What this kit is not

It is not a `pac` replacement; everything falls back to `pac` primitives, and the kit adds discipline and guardrails rather than a reimplementation. It is not an authoring tool for topic YAML, not a hosted service, not an eval harness, and not coupled to any one product or tenant. The full non-goals list lives in the design doc, precisely so scope creep gets caught early.

It also does not close the gap in `pac`; it works around it. If a future `pac` release learns to create Dataverse knowledge sources natively, this kit's job there shrinks to guardrails, and I will be genuinely happy about it!

**NOTE:** creating a knowledge source and getting the agent to actually ground on it are two different chains, and it pays to keep them straight. The creation chain is fully automated here. The grounding chain has preconditions of its own: the org-level search flag, the end-user authentication mode, the agent's runtime, and the find columns on each table's Quick Find view. The kit checks every one of them, automates the ones that can be automated, and tells you plainly about the one that cannot (see [docs/war-stories.md](docs/war-stories.md), story 1).

## The loop, end to end

Here is one full pass from empty folder to grounded agent, `pac` and kit interleaved. Nothing exotic, and that is rather the point:

```powershell
# ── 0. Tooling floor, once per machine ─────────────────────────────────────────
pac --version                        # 2.10.1 or later
$PSVersionTable.PSVersion            # 7.4 or later

# ── 1. Author locally (pac owns this) ──────────────────────────────────────────
pac copilot init                     # scaffold; creates nothing in Dataverse
# edit agent.mcs.yml, settings.mcs.yml, topics/*.mcs.yml

# ── 2. Pin the environment, once per shell ─────────────────────────────────────
# The kit never trusts the pac auth profile default org; the id is always
# explicit. pac gets its own auth for its own commands.
$env:PCK_DEFAULT_ENVIRONMENT_ID = '00000000-0000-0000-0000-000000000000'
pac auth create --environment $env:PCK_DEFAULT_ENVIRONMENT_ID

# ── 3. Connect and preflight (kit) ─────────────────────────────────────────────
Import-Module PacCopilotKit
Connect-PckPowerPlatform             # discovery, WhoAmI verification, cached context
Get-PckAgentInfo -Name 'WorkbenchSupportAssistant*'
# Harness              : Standard    <- proceed only on this
# AuthenticationModeName : Integrated  <- and this

# ── 4. Deploy: dry-run first, then the real thing (kit wrapping pac) ───────────
Invoke-PckCopilotPipeline -SolutionName WorkbenchSupportAssistant `
    -SourcePath .\agent -PublisherPrefix wrk -WhatIf   # plan: preflight and lint only
Invoke-PckCopilotPipeline -SolutionName WorkbenchSupportAssistant `
    -SourcePath .\agent -PublisherPrefix wrk -Json     # validate, pack, import, publish

# ── 5. Wire the Dataverse knowledge source (kit; the step pac cannot do) ───────
New-PckKnowledgeSource -BotName 'WorkbenchSupportAssistant' `
    -Table wrk_caseresolution -SolutionName WorkbenchSupportAssistant `
    -DisplayName 'Curated Case Resolutions'
Enable-PckDataverseSearch                      # once per environment; hours-scale tail
Wait-PckDataverseSearchReady -Table wrk_caseresolution -SearchText 'scanner'

# ── 6. Backup and commit (kit + git) ───────────────────────────────────────────
Export-PckSolutionBackup -SolutionName WorkbenchSupportAssistant -Path .\backups
git add . ; git commit -m "Milestone: agent deployed and grounded"
```

A few things to note here. The kit's authentication is deliberately separate from `pac`'s: the Web API side takes its token from your signed-in Azure CLI, from `PCK_ACCESS_TOKEN`, or from `Az.Accounts`, and it never reads `pac` auth state, because `pac` profiles are machine-global and I have personally watched another workspace re-point mine mid-project. The pipeline verifies the active `pac` profile actually targets your pinned environment before it lets `pac` touch anything, and refuses loudly if it does not. And in CI, those same commands work unchanged: set `PCK_SPN_TENANT`, `PCK_SPN_APP_ID`, and `PCK_SPN_SECRET`, and the kit switches to service principal auth, creates a temporary `pac` profile for the run, and deletes it on the way out, success or failure.

The export in step 6 is a backup, not the source of truth. The repository defines the agent; an environment is a place you put it.

## Who does what

| Step | Owner | Why |
|---|---|---|
| Author topics and settings as YAML | `pac copilot init` + your editor | Supported, documented, works |
| Validate YAML offline | kit (inside the pipeline) | The import will not catch what parses wrong |
| Pack and import the solution | `pac`, driven by the kit | Supported, documented, works |
| Pin the environment, verify identity | kit | The `pac` profile is machine-global and drifts |
| Gate on harness and auth mode | kit | The failure modes are silent |
| Create Dataverse knowledge sources | kit | No `pac` path exists at all |
| Wait for real search readiness | kit | The status endpoint lies; only queries tell the truth |
| Back up the solution | kit | One call, timestamped, explicitly not the source of truth |

## Installing the MCP server

The kit has two doors into the same engine. Humans get the PowerShell cmdlets; AI agents get `pac-copilot-kit-mcp`, a local MCP server that exposes the same guarded lifecycle as seven task-shaped verbs over stdio. Same guardrails, same typed refusals, same everything, because the server is a thin shim that shells to the module; nothing lives in it that the module does not enforce.

Until the npm package ships, you build it from the clone, as follows:

```powershell
# 1. The module first; the server refuses to start without it
git clone https://github.com/dgpblogster/pac-copilot-kit.git
Import-Module ./pac-copilot-kit/src/PacCopilotKit/PacCopilotKit.psd1
Get-Command -Module PacCopilotKit          # eight cmdlets means you are in business

# 2. Then the server (Node 20 or later)
cd pac-copilot-kit/src/pac-copilot-kit-mcp
npm install
npm run build
npm run smoke                              # handshake + seven tools advertised
```

Then wire it into your client with the matching config from [samples/mcp-config](samples/mcp-config): `.mcp.json` at the project root for Claude Code, `.vscode/mcp.json` for GitHub Copilot in VS Code, or `~/.codex/config.toml` for Codex CLI. Each sample points `node` at the built `dist/index.js`; set `PCK_DEFAULT_ENVIRONMENT_ID` in the `env` block and you are done. When the npm package publishes, the command line shrinks to `npx -y pac-copilot-kit-mcp` and nothing else changes.

A few things to note here. On startup the server verifies pwsh 7.4+, the module, and the `pac` CLI before advertising a single tool, so a broken prerequisite fails loudly at launch instead of surfacing as a mysterious tool error later. The seven verbs are `plan-deployment`, `run-pipeline`, `add-knowledge-source`, `wait-for-search`, `pull-agent`, `backup-solution`, and `explain-failure`; the first is the dry run, and the last turns any typed refusal into plain what-happened-and-what-to-do prose without another environment round trip. In practice you just ask your agent for the outcome ("plan a deployment of the agent workspace", "wire the case resolutions table into the agent as knowledge") and it picks the verb; the guardrails do the rest. The full walkthrough, including every environment variable and what each client looks like when it works, lives in [docs/mcp-clients.md](docs/mcp-clients.md).

**NOTE:** Microsoft's newer `pac` CLI line ships an MCP server of its own (`pac-mcp`), and it is a different animal: it exposes `pac` commands as tools and rides the active `pac` auth profile. Useful, but it inherits exactly the two problems this kit exists for: it cannot create Dataverse knowledge sources, and it trusts the machine-global profile that drifts. Run both if you like; they do not overlap.

## If you are an AI agent working with this kit

This section is for you, not for your human. The kit was designed to be driven by agents as much as by people, and these are the rules that make that work.

1. **Install from source for now.** Clone the repo, then `Import-Module ./src/PacCopilotKit/PacCopilotKit.psd1`. Verify with `Get-Command -Module PacCopilotKit`. If your host speaks MCP, build the shim (`cd src/pac-copilot-kit-mcp; npm install; npm run build`) and wire it up with a config from [samples/mcp-config](samples/mcp-config); it serves seven task-shaped verbs over stdio, and its `explain-failure` verb turns any typed refusal into what-happened-and-what-to-do prose. The PowerShell Gallery and npm publishes are still ahead.
2. **Check the floor before anything else:** PowerShell 7.4+, `pac` CLI 2.10.1+, and one token source for the Web API side: a signed-in Azure CLI, a `PCK_ACCESS_TOKEN` variable, the `Az.Accounts` module, or the three `PCK_SPN_*` variables in CI. The kit tells you exactly which one it wanted if none is available.
3. **The environment id is always explicit.** Set `PCK_DEFAULT_ENVIRONMENT_ID` or pass `-EnvironmentId` on every connect. Do not attempt to infer the environment from the `pac` auth profile; the kit refuses to, and so should you.
4. **Ask for `-Json` and parse stdout only.** Every public cmdlet emits one well-formed JSON object with `-Json`. Warnings and human commentary travel separately; never scrape them.
5. **Read the exit code before deciding what to do next,** as follows: codes 10 through 19 are preflight refusals, meaning the environment or the inputs are misconfigured; the message names the specific problem, so fix that and only that, and do not retry the same call unchanged. Code 20 means you asked for a route the platform is known to break; the error names the working alternatives, so switch to one of them. Code 1 is an ordinary operational failure.
6. **A refusal is information, not an obstacle.** Every guardrail in this kit encodes a documented platform failure, and most of those failures are silent when you hit them raw. If the kit refuses because the agent is the wrong harness or the wrong authentication mode, a knowledge source created anyway would display in the portal and never be queried, with no error anywhere. Do not work around a refusal by calling the Web API directly. The refusal is the feature.
7. **Long waits are real waits.** `Wait-PckDataverseSearchReady` polls for up to 150 minutes by default because initial index provisioning genuinely takes hours on a fresh environment. Do not kill it early and conclude failure, and do not shorten the timeout below reality.
8. **Dry-run deployments first.** `Invoke-PckCopilotPipeline -WhatIf` runs every read-only check and reports what the real run would do. Prefer offering your human that plan before the real thing.

## Requirements

- PowerShell 7.4 or later
- Power Platform CLI 2.10.1 or later
- Node 20 LTS, for the MCP server only, once it ships

## Documentation

- [Design](docs/pac-copilot-kit-design.md): the full architecture, guardrail funnel, and decision log
- [War stories](docs/war-stories.md): the `pac` and Dataverse gotchas the guardrails encode, one honest entry per guardrail
- [MCP clients](docs/mcp-clients.md): installing the server, wiring each client, the seven verbs, and troubleshooting
- [CI recipes](ci/README.md): GitHub Actions and Azure DevOps pipelines, and how to read a typed failure in a log
- `docs/quickstart.md` *(planned)*

**NOTE:** part of what this kit does relies on undocumented Dataverse record shapes, discovered by inspecting what the Copilot Studio maker portal writes. Those shapes are not supported by Microsoft and can change in any release. The kit verifies rather than assumes, the affected surface is called out explicitly in the war stories, and the integration tests are built to detect the platform shifting underneath us. Use it for development and ALM automation with your eyes open.

## License

MIT. See [LICENSE](LICENSE).

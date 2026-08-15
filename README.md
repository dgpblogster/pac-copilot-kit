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

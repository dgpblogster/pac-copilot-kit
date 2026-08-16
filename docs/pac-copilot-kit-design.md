# pac-copilot-kit: Design

Working design for a paved-road toolkit around Microsoft Power Platform CLI (`pac`) with a focus on the **Copilot Studio agent lifecycle**. Consolidates every decision reached in the design conversation on 2026-08-14, then revised the same day after reconciliation against the two source articles (see §0). Open questions and non-decisions are called out explicitly.

**Owner:** Mariano Gomez Bent
**Public home:** https://github.com/dgpblogster/pac-copilot-kit *(created; private until the two source articles publish, then public)*
**License:** MIT
**Status:** v0.1 code-complete as of 2026-08-16. All §12 questions closed. Every v0.1 component (§12.9 scope) is built, tested, and live-proven; remaining before release: `ci/` recipes and the Gallery and npm publishes. Implementation-status markers below distinguish shipped surface from designed-but-unbuilt surface.

---

## 0. Revision note (2026-08-14)

The first pass of this document was written from the design conversation alone. It was then reconciled against the two private source articles that record what the POC actually proved: one on adding Dataverse knowledge sources with the Web API, one on real ALM for Copilot Studio agents. Those drafts are the authority on platform behavior; this document is not.

Three statements in the first pass were wrong or incomplete and are corrected below: the `savedquery` guard behavior (§6.2), the botcomponent attachment relationship (§6.3), and the Web API token source (§5, now open question §12.8). Several guards the articles prove necessary were missing entirely and are added (§6.1, §6.2). The purpose and scope are restated around two pillars (§1), which reopens the v0.1 scope signed off earlier the same day (§12.1, §12.9).

---

## 1. Purpose

The kit exists for two reasons. Every feature traces to one of them, and anything that traces to neither is scope creep.

**Pillar A, capability. Do what `pac` cannot.** Copilot Studio's Dataverse knowledge sources have no code path. `pac copilot pack` rejects a Dataverse source definition placed in the workspace `knowledge/` folder, while website and SharePoint sources pack fine. The maker portal is the only documented route. The kit creates them through the Dataverse Web API instead, in-solution and repeatably, and owns the full grounding chain that surrounds them rather than the four creates alone.

**Pillar B, paved road. Make the published ALM prescription executable.** Microsoft's guidance is sound and has not wavered: solutions, custom publisher and prefix, environment variables for what changes between environments, source control, at least three environments. What is missing is the road. There is no agent task in Power Platform Build Tools, no agent-aware GitHub Action, and no Microsoft reference pipeline that runs `pac copilot pack` followed by `pac solution import`, even though pack is documented as safe to run in a build pipeline. The kit is that missing primitive, installable in an ordinary script step.

Pillar A is why someone installs the kit. Pillar B is why they keep it.

State the problem precisely, because the weaker version invites an argument that is easy to lose: Copilot Studio ALM is **prescribed but not automatable**. It is not absent. The kit does not invent an ALM story, it makes the published one executable, and that claim survives Microsoft shipping a first-party agent task later.

Delivery targets both a shell and an AI pair (Claude Code, GitHub Copilot in VS Code, ChatGPT Codex), and a CI pipeline with SPN-based auth, from one call site.

Explicit rationale for building this and not something else:

- The source Copilot Studio POC (private, not part of this repo) has already surfaced the specific gotchas: profile drift, `pac org select` crash on 2.10.1, `pac copilot` lifecycle sharp edges, solution-header hygiene on API-created components, the harness split, and the grounding preconditions. Tooling here converts hard-won knowledge into a reusable engine.
- The queued blog articles (#3 "Real ALM for Copilot Studio agents", #5 "pac + Dataverse war stories", #11 "Verifying technical content before you publish it") all become executable rebuild kits when the toolkit exists.
- The vendored Copilot Studio skills used by that POC cover authoring (topics, actions, knowledge, adaptive cards) and eval. They do **not** cover the transport layer to a pinned environment, and they are trust-but-verify. The kit sits *underneath* those skills, not next to them.

## 2. Positioning

| It is | It is not |
|---|---|
| A capability layer for the one component type `pac` cannot create (pillar A) | A replacement for `pac` |
| The missing CI primitive for the published ALM prescription (pillar B) | An ALM story of its own invention |
| A CI-friendly PowerShell module + local MCP server | A hosted SaaS or a cloud service |
| The transport / environment discipline layer | An authoring tool for topic YAML |
| The rebuild-kit engine for blog articles #3, #5, #11 | A tool coupled to any one product or tenant |
| Solution-aware by default | An unstructured `pac` passthrough |

Two boundaries that follow from pillar A and are worth stating before anyone widens them:

- **The kit works around the `pac` gap, it does not close it.** `pac copilot pack` still rejects Dataverse knowledge YAML. Nothing upstream changed. If a future `pac` release grows a real code path, the kit's job here shrinks to guards.
- **Creating a knowledge source and grounding on one are different chains.** The creation chain is fully solvable through the Web API. The grounding chain has preconditions of its own (§6.1, §6.2), and one of them, find columns on the Quick Find view, has no Web API route at all (§6.2).

## 3. Naming

Three names, one identity:

| Artifact | Name |
|---|---|
| GitHub repo | `pac-copilot-kit` |
| PowerShell module | `PacCopilotKit` (import name; PS conventions require dot-friendly / no dashes) |
| npm package (MCP server) | `pac-copilot-kit-mcp` |
| PowerShell Gallery entry | `PacCopilotKit` |
| Env var prefix | `PCK_…` |

Cmdlet noun prefix: `Pck` (short, matches PS Verb-Noun convention, avoids collision with any `Pac*` module Microsoft may ship).

## 4. Shape

Two components, one engine:

```
                    ┌────────────────────────────────┐
                    │  MCP server (Node, stdio)      │
                    │  pac-copilot-kit-mcp           │
                    │  small task-oriented verb set  │
                    └───────────────┬────────────────┘
                                    │ shells to pwsh -NoProfile -Command
                                    ▼
┌────────────────────────────────────────────────────────────┐
│  PowerShell module (the engine)                            │
│  PacCopilotKit                                             │
│  ├─ Public/  exported cmdlets (Verb-Pck<Noun>)             │
│  └─ Private/ Invoke-PckDataverseRequest, guards, helpers   │
└───────────────┬────────────────────────────────────────────┘
                │
                ▼
        pac CLI  +  Dataverse Web API
```

Rationale for the split: the PS module is the source of truth and testable in isolation with Pester. The MCP server is a thin translation layer (natural-language-friendly verbs → cmdlets). If the MCP protocol changes or a fourth client appears, only the shim moves; the engine is stable.

## 5. Design discipline (non-negotiable rules for the engine)

1. **No interactive prompts.** No `Read-Host`. No `pac org select` (also crashes on 2.10.1). Every input is a parameter or an env var.
2. **Two auth modes, one call site.**
   - *Dev mode:* select an existing `pac auth` profile by name, verify with `pac org who`, refuse if the org id does not match the requested environment id.
   - *CI mode:* create an auth profile inline from SPN env vars (`PCK_SPN_TENANT`, `PCK_SPN_APP_ID`, `PCK_SPN_SECRET`) for the run, clear it on exit.
   - Mode selection is implicit from whether the SPN env vars are populated. Callers do not pick.

   **Resolved (§12.8, 2026-08-15):** this rule governs `pac` invocations only. `Invoke-PckDataverseRequest` acquires its own token and never reads `pac` state: SPN client credentials in CI, and `PCK_ACCESS_TOKEN`, then `az`, then `Az.Accounts` in dev. No `pac` command emits a bearer token, so the alternative was never implementable. As built, dev mode verifies the **active** profile with `pac org who` (`Assert-PckProfileAligned`) rather than selecting one by name, and CI mode is implemented inside `Invoke-PckCopilotPipeline` as a temporary named profile deleted on exit, success or failure.
3. **Environment id is always explicit.** Every public cmdlet takes `-EnvironmentId` (GUID). Default resolution order: parameter → `PCK_DEFAULT_ENVIRONMENT_ID` env var → hard error. The `pac auth` profile's default org is never trusted (documented drift risk).
4. **Structured output.** Every public cmdlet accepts `-Json` and writes a single well-formed JSON object to stdout. Human-readable mode goes to stderr / host so pipelines can rely on stdout being clean.
5. **Non-zero exit codes on failure.** No swallowed errors. `$LASTEXITCODE` and `throw` both trigger a non-zero exit.
6. **One Web API funnel.** Every Dataverse Web API call routes through `Invoke-PckDataverseRequest` (see §6). No `Invoke-RestMethod` in public cmdlets.
7. **Working directory is explicit.** No implicit dependence on `$PWD` inside cmdlets. Every path parameter is either absolute or resolved against a `-WorkingDirectory` parameter.
8. **Idempotent where possible.** Import + publish are safe to re-run. Backup is timestamp-suffixed. Auth-mode toggles are idempotent.
9. **Forward from source, never round-trip.** The repository is the artifact. Every deployment packs YAML the repo owns and runs component scripts the repo owns. Nothing is inferred from whatever a solution in an environment happens to contain. `Export-PckSolutionBackup` produces a backup, explicitly not a source of truth.

   This rule is what makes the pipeline automatable at all, so it is worth spelling out. Microsoft documents a failure where components added to an agent's solution after the fact are omitted from the export, and lists topics, environment variables, tools, child agents, and knowledge sources among the casualties. The prescribed fix is a portal click: the agent's commands menu, then **Advanced**, then **Add required objects**, repeated before every export. It has no CLI equivalent, no pipeline step, and it fails silently when skipped. The solution imports cleanly and the agent simply answers as though a knowledge source it needs was never there.

   That click governs **export fidelity**. A forward deployment never asks an environment what belongs in the solution, so the click never gates it. This is the same argument that makes script-created knowledge sources immune to the documented disappearance, generalized to the whole pipeline. Any feature that promotes an exported zip to source of truth reintroduces a manual precondition and does not belong in the kit.

## 6. Guard funnel

Two categories of guard. Every public cmdlet uses both.

**Implementation status (2026-08-16).** Shipped as guard files: `Assert-PckPacVersion`, `Assert-PckProfileAligned`, `Assert-PckSolutionExists`, `Assert-PckAgentHarness`, `Assert-PckAgentAuthMode`, `Convert-PckSavedQueryFetchXmlError`. Shipped with a different shape than first sketched: the pwsh floor rides `#Requires -Version 7.4` plus the MCP startup preflight rather than a guard file; the SPN-completeness check lives inside `Get-PckAccessToken` (exit 11); the workspace-root rule lives in `Resolve-PckOutputPath` (exit 17); the search-enabled check is a reported warning in `New-PckKnowledgeSource` rather than a refusal, since creation is valid before enablement and readiness is `Wait-PckDataverseSearchReady`'s job. Not yet built: the metadata-PATCH promotion, the `contains()` refusal, the entity-set plural fallback wiring, `Get-PckFlowId`, and the `pac org fetch` reroute; their rows below are design targets.

### 6.1 Preflight guards (refuse to run)

Called at the top of every public cmdlet, in `Private/Guards/`:

| Guard | Refuses the call when |
|---|---|
| `Assert-PckPacVersion` | The pac banner version is missing, unreadable, or older than the tested floor (2.10.1). Banner shape verified live (war story 6). |
| `Assert-PckProfileAligned` | The **active** `pac auth` profile's `pac org who` output does not match `-EnvironmentId` (or the org URL host). Fixes the specific bug found in the POC where another workspace re-pointed the profile. Output shape verified live (war story 6). |
| `Assert-PckSolutionExists` | `-SolutionName` not present in the target environment, when the operation needs it (war story 5). |
| `Assert-PckAgentHarness` | Target agent is not standard harness. Read `GET /bots?$select=name,schemaname,template`: a `default-*` template proceeds, `cliagent-1.0.0` refuses. This is the highest-value guard in the table, because the failure it prevents is silent in both directions: a knowledge component created against the newer experience **displays in the Knowledge panel**, since the panel reads the same component table, while the runtime never queries it. The agent answers from general model knowledge and states it has no documents. No error anywhere. |
| `Assert-PckAgentAuthMode` | Agent's end-user authentication is not "Authenticate with Microsoft". Dataverse knowledge sources ride the end user's identity, so every other mode never searches them. Documented, and fatal to grounding. Storage shape verified live 2026-08-15: `bot.authenticationmode` picklist, 0 Unspecified, 1 None, 2 Integrated (the only mode that grounds), 3 Custom Entra ID, 4 Generic OAuth2 (war story 3). |

As built, the pipeline additionally guards the pac funnel itself: `Invoke-PckPacCommand` does not believe a zero exit code when the output carries an `Error:` line, because pac exits 0 on errors it prints (war story 7, observed three times live).

Preflight guards fail with a distinct exit code range (`10..19`) so CI can distinguish "environment misconfigured" from "operation failed".

### 6.2 Wrap-and-translate guards (attempt, catch a known signature, rewrite)

All inside `Invoke-PckDataverseRequest`. The public cmdlets never see these codes directly. Each guard corresponds to a war story from the private article inventory that `docs/war-stories.md` will publish in sanitized form:

| Symptom | Guard behavior |
|---|---|
| `savedquery` PATCH of `fetchxml` returns `0x80040216` | **Corrected twice; current as of 2026-08-15.** First correction (2026-08-14): the claimed `layoutxml`-first two-call translation was never proven and was withdrawn. Second correction (2026-08-15, third-org live verification): the failure is broad but not universal. Most Quick Find views fail (standard and elastic, custom and system, search-synced or not) while a minority accept the same call (`privilegecheckerrun`, virtual `aaduser`); the discriminator is unidentified. The guard is therefore a **response translator**, `Convert-PckSavedQueryFetchXmlError`: attempt the call, and when the `0x80040216` signature comes back on a savedquery fetchxml route, throw the war story (exit 20) naming solution surgery (§7 `Edit-PckSolutionXml`) and the portal path. Full verification log in war story 1. |
| Find columns are not the ones you configured | Not an error, a silent grounding failure, and the reason the row above matters. Dataverse search indexes the columns configured as **find columns on the table's Quick Find view**, and a fresh custom table's Quick Find view carries exactly one, the primary name. Every other column is invisible to search and therefore to the agent. The kit inspects find columns during preflight and refuses to report a source as grounded when the columns it searches are absent. |
| Metadata entity PATCH fails (metadata rejects PATCH entirely) | Auto-promote to full-document PUT with `MSCRM.MergeLabels: true` header and a follow-up `PublishXml` call. Omitted properties reset to their defaults, so the full document has to be read, modified, and returned whole. This is the **recovery** path, not the plan: see the `SyncToExternalSearchIndex` row below. |
| `SyncToExternalSearchIndex` needed on a table that already exists | The metadata PUT ceremony above is the only way to add it later, which is exactly why the kit sets it in the original `EntityDefinitions` create payload. Retrofit is supported and is never the happy path. |
| Memo column created without an explicit format | Set `Format: TextArea` on every `MemoAttributeMetadata` at create time. Plain multi-line text is what the knowledge indexer expects, and a correctly created column reads back with both `Format` and `FormatName` as `TextArea`. |
| `contains()` in `$filter` against metadata entities returns `0x8006088a` | Detect at request construction, refuse with a message pointing at the `startswith`/`eq` alternative. |
| Entity-set plural mismatch (e.g., `dvtablesearchs`) | Local override table shipped with the module; used before falling back to conventional pluralization. |
| Dataverse search status endpoint reports zero indexed tables while queries succeed | Never trust status. `Wait-PckDataverseSearchReady` probes with an actual `POST /api/search/v1.0/query` and polls that, not `/status`. Size the default timeout for **hours, not minutes**: initial index provisioning on a freshly provisioned environment took roughly two hours before seeded rows became searchable. |
| Solution-header omission on API-created components | Every mutating call sets `MSCRM.SolutionUniqueName` from the `-SolutionName` parameter. There is no path in the module to create a solution-orphaned component. |
| `InvokeFlowAction.flowId` confusion (workflow.resourceid vs workflowid) | Helper `Get-PckFlowId` resolves the correct identifier and returns both, with the resource id marked as the one to embed. Embedding the wrong one imports cleanly and fails only when a user triggers the action. |
| Flow created by the obvious tooling never appears in the solution | Create through the Dataverse `workflow` endpoint carrying the solution header. After any solution round-trip, verify the flow came back **activated**; the import round-trips everything else in the solution and activation state is worth checking rather than assuming. |
| `pac org fetch` StackOverflowException on non-aggregate `incident` queries | Detect the shape, route through Web API instead of `pac org fetch`. |
| Power Fx string in a `.mcs.yml` containing a colon followed by a space | Offline schema check of every `.mcs.yml` before pack, as the first step of the pipeline. The file parses wrong rather than failing, and surfaces as strange runtime behavior instead of an error, so the import will not catch it. Cheapest guard in the kit and the highest-value habit in the loop. |

The **single funnel** matters: retrofitting these guards later would require touching every cmdlet. Committing to it now means each war story is fixed in exactly one place.

### 6.3 Record shapes the kit encodes

These are undocumented shapes, discovered by inspecting what the maker portal writes, and reproduced twice: once in a production-grade Dynamics 365 CE org and once in a freshly provisioned vanilla environment. They can change in any release. The kit verifies rather than assumes, and `docs/war-stories.md` carries the same warning that the source article does.

A Dataverse knowledge source is four ordinary Dataverse records:

| Record | Role |
|---|---|
| `dvtablesearch` | The table search configuration, and the knowledge source's identity. Entity set is `dvtablesearchs`, which conventional pluralization does not produce (see the plural override table). `name` is a **machine-style identifier**, referenced verbatim by the component YAML. That single property is the entire create payload. |
| `dvtablesearchentity` | One child row per table being searched, bound to the parent through the `DVTableSearch` single-valued navigation property, naming the table in `entitylogicalname`. |
| `botcomponent` with `componenttype` 16 | The agent-side knowledge component. Its `data` column holds a `KnowledgeSourceConfiguration` YAML document whose `skillConfiguration` names the `dvtablesearch` from the first row. Its `name` is the friendly label makers see in the Knowledge tab, so it is deliberately distinct from the machine name. |
| `botcomponent_dvtablesearch` | The N:N association tying the component to the search configuration. This is the N:N that matters. |

Two attachment facts that are easy to get wrong, and one of which the first pass of this document got wrong:

- **The component attaches to the agent through the `parentbotid` lookup**, not through the `bot_botcomponent` N:N relationship. That relationship exists in the schema and stays empty for knowledge components; the parent lookup is what the platform actually reads. An implementation that populates `bot_botcomponent` produces a component the agent never sees.
- `schemaname` follows the convention `<botSchemaName>.knowledge.<componentName>`, where the bot schemaname must be **read** from `GET /bots`, never constructed. Agents created in the newer experience carry a random suffix in theirs.
- Deleting the `componenttype` 16 botcomponent **cascade-deletes the associated `dvtablesearch` and its `dvtablesearchentity` children** (observed live 2026-08-16, one org). Cleanup code should treat 404 on the children as already-done rather than as failure.

### 6.4 Guard-authoring rule

New guard = one file under `Private/Guards/`, one Pester test proving the untranslated call fails and the translated call succeeds, one line in the war-stories reference doc. No guards without all three.

For guards where no translated call exists (the `savedquery` case), the test proves the untranslated call fails and the guard refuses with the documented alternative rather than attempting it.

## 7. Public PS API surface

Task-oriented, not 1:1 with `pac` subcommands. Names signed off 2026-08-15 (§12.2). Every cmdlet is tagged with the pillar it serves; a cmdlet that serves neither is a scope question, not a naming question.

**Implementation status (2026-08-16).** Shipped and tested: `Connect-PckPowerPlatform`, `Get-PckAgentInfo`, `New-PckKnowledgeSource` (live-proven), `Enable-PckDataverseSearch`, `Wait-PckDataverseSearchReady`, `Export-PckSolutionBackup`, `Invoke-PckCopilotPipeline` (live-proven), `Sync-PckCopilotAgent`. Designed, not yet built: `New-PckCopilotComponent`, `Edit-PckSolutionXml`, `Test-PckSolutionCompleteness`, `Publish-PckCopilotAgent`, `Get-PckFlowId`, `Get-PckPostDeployChecklist`; these are post-v0.1 surface. The optional table-create half of `New-PckKnowledgeSource` is deferred pending a parameter-shape decision (decision log, 2026-08-16).

### 7.1 Pillar A, capability

| Cmdlet | Purpose |
|---|---|
| `New-PckKnowledgeSource` | The headline cmdlet. Owns the whole chain, not the four creates: preflight (harness, end-user auth mode, org search flag, solution exists), optional custom table create with `SyncToExternalSearchIndex` and `Format: TextArea` set at create time, then `dvtablesearch`, one `dvtablesearchentity` per table, the `componenttype` 16 `botcomponent` with a read-not-guessed schemaname, and the `botcomponent_dvtablesearch` association. Solution header on every call, non-optional. Reports find columns as a precondition it cannot satisfy (§6.2) and hands off rather than claiming success. |
| `Enable-PckDataverseSearch` | Set `isexternalsearchindexenabled` on the organization record. Separate cmdlet because it is an org-wide, once-per-environment act with a multi-hour tail, not a step inside a deployment. |
| `Wait-PckDataverseSearchReady` | Poll `POST /api/search/v1.0/query` (never `/status`) until seeded rows become searchable. Default timeout sized in hours. |
| `Get-PckAgentInfo` | Read `template`, `schemaname`, and end-user auth mode for a bot. Backs the harness and auth-mode guards, and returns the schemaname the component create needs. |
| `New-PckCopilotComponent` | Lower-level solution-aware Web API create for botcomponent types beyond knowledge sources. Kept as the general primitive under `New-PckKnowledgeSource`. |

### 7.2 Pillar B, paved road

| Cmdlet | Purpose |
|---|---|
| `Connect-PckPowerPlatform` | Resolve dev-or-CI auth, verify reachability via WhoAmI, cache the resolved context for the session. Token source per §12.8 as resolved: never `pac` state. |
| `Invoke-PckCopilotPipeline` | The paved road: preflight, offline YAML validate, pack, import, publish, against a pinned environment, in one call. Forward from source per §5 rule 9. |
| `Edit-PckSolutionXml` | Solution surgery: export, edit `customizations.xml`, repack, import. The automatable route for find columns and anything else the Web API refuses. **Refuses to touch agent components**, since editing those inside the solution is documented to break export and import. Ordinary Dataverse metadata (tables, columns, views) only. That distinction is the whole safety rule, so it is enforced rather than documented. |
| `Test-PckSolutionCompleteness` | Enumerate the agent's botcomponents, knowledge sources, and environment variable definitions, diff against solution membership, and report what is missing. The programmatic answer to the add-required-objects click for anyone who does export as an artifact, and a useful assertion even on the forward path. |
| `Publish-PckCopilotAgent` | Publish only (draft to live), separate from import for iterate loops. |
| `Sync-PckCopilotAgent` | `pac copilot pull` from the target environment into a local workspace, with profile guard. |
| `Export-PckSolutionBackup` | One call `POST /ExportSolution`, decode base64 zip, write to disk with timestamp suffix. A backup, explicitly not the source of truth (§5 rule 9). |
| `Get-PckFlowId` | Resolve `workflow.resourceid` for a flow by display name or workflowid. |
| `Get-PckPostDeployChecklist` | Emit the structured list of things the solution does not carry and a human must do per environment: reconfigure user authentication, publish before sharing, redeploy channels, re-share, Application Insights settings, Direct Line and web channel security, and repoint environment variable values. Not automation, and deliberately not silence. |

### 7.3 Deferred

| Cmdlet | Purpose |
|---|---|
| `Test-PckCopilotAgent` | Runs a Pester or eval CSV against a draft agent using the coatsy `run-eval` skill's underlying API. Deferred to v0.2 unless promoted. |

## 8. MCP server: verb set and transport

### 8.1 Transport

- **Protocol:** MCP over stdio.
- **Launcher:** `npx -y pac-copilot-kit-mcp` in every client config.
- **HTTP/SSE:** deferred. Codex CLI is stdio-only, so stdio is the lowest common denominator that keeps all three clients on one server binary.
- **Statelessness:** each client spawns its own instance; every tool call is independent. The server never caches auth or tokens across calls.

### 8.2 Startup preflight

Before advertising tools, the server verifies once:

- `pwsh -v` present (PowerShell 7.4+).
- `pac --version` present and >= tested floor.
- `PacCopilotKit` module importable.

Any failure returns a clear error in the MCP `initialize` response and exits non-zero. No silent tool-not-found later.

### 8.3 Verb set (small, task-shaped, not cmdlet-mirrored)

The MCP surface is deliberately narrower than the cmdlet surface. AI agents pick better from seven well-labeled verbs than thirty look-alike ones. *(Amended 2026-08-15: `add-knowledge-source` added as the seventh verb per §12.10, so pillar A has a labeled verb rather than reaching AI clients only through `run-pipeline`.)*

| MCP tool | Wraps | What the agent asks for |
|---|---|---|
| `plan-deployment` | `Invoke-PckCopilotPipeline -WhatIf` | "What would happen if I deployed this now?" Returns preflight results, diff summary, refuses with reasons if guards would trip. |
| `run-pipeline` | `Invoke-PckCopilotPipeline` | Full deploy loop against the pinned environment. |
| `backup-solution` | `Export-PckSolutionBackup` | One-call solution export to disk. |
| `pull-agent` | `Sync-PckCopilotAgent` | Pull the live agent YAML into the workspace, guard-checked. |
| `add-knowledge-source` | `New-PckKnowledgeSource` | Wire a Dataverse knowledge source into the agent: preflight, create the four records in-solution, verify. The pillar A verb. |
| `wait-for-search` | `Wait-PckDataverseSearchReady` | Block until knowledge grounding is live after seeding. |
| `explain-failure` | Local reasoner over the last cmdlet's structured error output | Turn a war-story exit code into a plain-English "here is what happened and how to fix it" reply, without another Dataverse round-trip. |

`explain-failure` is the differentiator. It turns the guard funnel's structured errors into agent-consumable prose, and it is the one MCP tool with no PS cmdlet on the other side.

The gap flagged on 2026-08-14 (no pillar A verb) closed on 2026-08-15 with `add-knowledge-source`; see §12.10.

### 8.4 Server ↔ engine bridge

Shell-out, one pwsh process per tool call, no long-lived subprocess. As built (2026-08-16), with two properties the first sketch did not spell out:

- **Injection-safe by construction.** Tool arguments never touch a command line. They travel as JSON in environment variables and are splatted inside a fixed bridge script; the cmdlet name comes from a hard allowlist. No spelling of an argument can rewrite the command.
- **Typed exit codes end to end.** The bridge converts a thrown `PckError` into the child process exit code, so the `PckExitCode` registry crosses the process boundary intact. The server labels the failure with its registry name for the client and remembers it for `explain-failure`.

The server passes `-Json`, returns stdout as the tool result, and runs `Connect-PckPowerPlatform` inside the child for the cmdlets that need a session. Stderr becomes the failure detail.

## 9. Client configuration recipes

All three configs launch the same server binary via `npx` once the npm package publishes; until then, `samples/mcp-config/` carries working from-source variants (`node <clone>/src/pac-copilot-kit-mcp/dist/index.js`). Only file location and syntax differ per client.

### VS Code (`.vscode/mcp.json`, project scope)

```jsonc
{
  "inputs": [
    { "id": "spn-secret", "type": "promptString", "password": true,
      "description": "SPN client secret (CI mode only, leave blank for dev)" }
  ],
  "servers": {
    "pac-copilot-kit": {
      "command": "npx",
      "args": ["-y", "pac-copilot-kit-mcp"],
      "env": {
        "PCK_DEFAULT_ENVIRONMENT_ID": "00000000-0000-0000-0000-000000000000",
        "PCK_WORKSPACE_ROOT": "${workspaceFolder}",
        "PCK_SPN_SECRET": "${input:spn-secret}"
      }
    }
  }
}
```

### Claude Code (`.mcp.json`, project scope)

```jsonc
{
  "mcpServers": {
    "pac-copilot-kit": {
      "command": "npx",
      "args": ["-y", "pac-copilot-kit-mcp"],
      "env": { "PCK_DEFAULT_ENVIRONMENT_ID": "00000000-0000-0000-0000-000000000000" }
    }
  }
}
```

### ChatGPT Codex CLI (`~/.codex/config.toml`)

```toml
[mcp_servers.pac-copilot-kit]
command = "npx"
args = ["-y", "pac-copilot-kit-mcp"]
env = { PCK_DEFAULT_ENVIRONMENT_ID = "00000000-0000-0000-0000-000000000000" }
```

## 10. CI integration

The kit composes with Microsoft's existing pipeline tooling, it does not replace it.

### 10.1 GitHub Actions

```yaml
- uses: microsoft/powerplatform-actions/actions-install@v1
- uses: microsoft/powerplatform-actions/who-am-i@v1
  with:
    environment-url: ${{ vars.PPE_URL }}
    app-id:          ${{ vars.SPN_APP_ID }}
    client-secret:   ${{ secrets.SPN_SECRET }}
    tenant-id:       ${{ vars.SPN_TENANT }}
- shell: pwsh
  env:
    PCK_SPN_TENANT: ${{ vars.SPN_TENANT }}
    PCK_SPN_APP_ID: ${{ vars.SPN_APP_ID }}
    PCK_SPN_SECRET: ${{ secrets.SPN_SECRET }}
    PCK_DEFAULT_ENVIRONMENT_ID: ${{ vars.PPE_ID }}
  run: |
    Install-Module PacCopilotKit -Scope CurrentUser -Force
    Invoke-PckCopilotPipeline -SolutionName WorkbenchSupportAssistant `
      -SourcePath ./agent -Json
```

### 10.2 Azure DevOps (Power Platform Build Tools)

```yaml
- task: PowerPlatformToolInstaller@2
- task: PowerPlatformWhoAmI@2
  inputs:
    authenticationType: PowerPlatformSPN
    PowerPlatformSPN: 'WorkbenchSandbox-SPN'
- task: PowerShell@2
  env:
    PCK_SPN_TENANT: $(SpnTenant)
    PCK_SPN_APP_ID: $(SpnAppId)
    PCK_SPN_SECRET: $(SpnSecret)
    PCK_DEFAULT_ENVIRONMENT_ID: $(EnvironmentId)
  inputs:
    targetType: inline
    script: |
      Install-Module PacCopilotKit -Scope CurrentUser -Force
      Invoke-PckCopilotPipeline -SolutionName WorkbenchSupportAssistant `
        -SourcePath ./agent -PublisherPrefix wrk -Json
```

*(As built, `Invoke-PckCopilotPipeline` also requires `-PublisherPrefix`, shown above; the `ci/` runnable examples are the next deliverable and will be the tested versions of these sketches.)*

The Microsoft tasks handle generic solution lifecycle (import, pack, publish, who-am-i, export) where they exist. The kit fills the `pac copilot` gap and the solution-aware Web API creates, and can also replace the Microsoft tasks entirely if a pipeline wants a single-vendor path.

### 10.3 What is genuinely not automatable

Worth listing so the CI story is honest, and so the list is visibly shorter than its reputation:

| Item | Blocks a pipeline? |
|---|---|
| Non-solution-aware settings (authentication, channels, sharing, Application Insights) | No. Once per environment at bootstrap, not once per deploy. `Get-PckPostDeployChecklist` emits them rather than pretending. |
| Find columns on the Quick Find view | No. `Edit-PckSolutionXml`, or ship the edited `customizations.xml` in the repo. |
| Add required objects | No, on the forward path. See §5 rule 9. It gates export-as-artifact only. |
| Dataverse search index provisioning, roughly two hours | Only for ephemeral environments. Rules out spin-up, test, tear-down CI for a grounded agent. Worth knowing before anyone designs around per-PR environments. |
| A second environment to deploy into | Not a tooling problem. Dataverse knowledge reads only the agent's own environment, which collapses the prescribed three-environment model wherever the grounding data lives in exactly one place. |

Nothing on that list makes CI a dead end. The CLI was designed for CI and documented for CI; the first-party CI tooling has not caught up, which is the gap the kit occupies.

## 11. Repo layout

As built on 2026-08-16. Differences from the first sketch: response translators are `Convert-Pck*.ps1` rather than `Wrap-Pck*.ps1`; MCP tests live inside the package; `en-US/` waits for MAML help; comment-based help serves meanwhile.

```
pac-copilot-kit/
├── src/
│   ├── PacCopilotKit/                    # PowerShell module (engine)
│   │   ├── PacCopilotKit.psd1
│   │   ├── PacCopilotKit.psm1            # error types + loader
│   │   ├── Public/                       # one .ps1 per exported cmdlet (8 shipped)
│   │   └── Private/
│   │       ├── Guards/                   # Assert-Pck*.ps1 + Convert-Pck*.ps1
│   │       ├── Invoke-PckDataverseRequest.ps1   # Web API funnel
│   │       ├── Invoke-PckPacCommand.ps1         # pac funnel
│   │       └── EntitySetPluralOverrides.psd1
│   └── pac-copilot-kit-mcp/              # MCP server (Node/TypeScript)
│       ├── package.json
│       ├── src/
│       │   ├── index.ts                  # stdio entrypoint + startup preflight
│       │   ├── exitCodes.ts              # the exit-code contract, mirrored
│       │   ├── pwsh.ts                   # injection-safe bridge
│       │   └── tools/                    # verb registrations
│       ├── tests/                        # smoke.mjs + live-probe.mjs
│       └── tsconfig.json
├── tests/
│   ├── PacCopilotKit.Tests/              # Pester tests
│   └── pac-copilot-kit-mcp.tests/        # Node tests
├── ci/
│   ├── github-actions/example.yml
│   └── azure-pipelines/example.yml
├── docs/
│   ├── pac-copilot-kit-design.md         # this file
│   ├── war-stories.md                    # 7 stories, one per guard plus inventory
│   ├── quickstart.md                     # planned
│   ├── ci-recipes.md                     # planned
│   └── mcp-clients.md                    # planned
├── samples/
│   └── mcp-config/                       # copy-paste configs for the three clients
├── ci/                                   # planned: runnable versions of the section 10 sketches
├── tests/
│   └── PacCopilotKit.Tests/              # Pester: unit suites + Integration-tagged live tests
├── LICENSE                               # MIT
├── README.md
├── SESSION-STATE.md                      # recovery brief (sanitized; ships)
└── CHANGELOG.md
```

## 12. Open questions

All closed as of 2026-08-15. Retained with their resolutions because the reasoning is the record.

1. ~~**v0.1 scope.**~~ **Signed off 2026-08-14, then reopened the same day. See §12.9.** Original: `Invoke-PckCopilotPipeline` + `Export-PckSolutionBackup` + war-stories guards in `Invoke-PckDataverseRequest` + MCP shim from day one. That set is entirely pillar B plus a backup helper; it omits pillar A, which §1 now identifies as the reason anyone installs the kit.
2. ~~**Public PS API sign-off.**~~ **Signed off 2026-08-15** as proposed in §7. The `Pck` prefix was re-examined against a `Pac` prefix and kept: `Pac` invites collision with any future first-party module and reads as Microsoft's own, which a kit built partly on unsupported record shapes must not. Aliases in the `Pac` spelling were considered and declined for the same reason.
3. ~~**MCP verb set sign-off.**~~ **Signed off 2026-08-14.** §8.3 verbs locked (`plan-deployment`, `run-pipeline`, `backup-solution`, `pull-agent`, `wait-for-search`, `explain-failure`).
4. ~~**PowerShell floor.**~~ **Signed off 2026-08-15:** 7.4 and later. Windows PowerShell 5.1 is out.
5. ~~**Node floor for the MCP server.**~~ **Signed off 2026-08-15:** Node 20 LTS.
6. ~~**PowerShell Gallery publish path.**~~ **Signed off 2026-08-15:** manual for v0.1.
7. ~~**Sanitization pass on war-stories.**~~ **Signed off 2026-08-15:** this repo owns the sanitized `docs/war-stories.md`; the blog references it.
8. ~~**Web API token source.**~~ **Signed off 2026-08-15.** The funnel acquires its own token and never depends on `pac` state. Two facts settled it rather than preference:

   - **No `pac` command emits a bearer token.** The full `pac auth` surface is `clear`, `create`, `delete`, `list`, `name`, `select`, `update`, `who`. Reusing the profile's token is not implementable through supported surface.
   - **The VS Code extension is not an alternative.** Its Auth Panel creates and selects the same machine-global `pac auth` profiles, so it inherits the drift canon 4 exists to prevent, and it hands out no token either. There is therefore **one code path for every developer**, with no editor-conditional behavior.

   Resolved shape:

   | Mode | Token acquisition |
   |---|---|
   | CI | SPN client credentials, direct POST to the Entra token endpoint with scope `{org}/.default`. One `Invoke-RestMethod`. **No extra dependency at all.** |
   | Dev | First match wins: `PCK_ACCESS_TOKEN` if set, then `az account get-access-token --resource <org>` if `az` is on the path, then `Get-AzAccessToken` from `Az.Accounts` if that module is present, then a hard error naming all three. |

   The chain makes `az` an accepted path rather than a prerequisite. `Connect-PckPowerPlatform` still governs `pac` invocations; this decision covers the Web API funnel only, and the two remain deliberately independent.
9. ~~**v0.1 rescope.**~~ **Signed off 2026-08-15: v0.1 grows to cover pillar A.** Scope is `New-PckKnowledgeSource` + `Wait-PckDataverseSearchReady` + `Enable-PckDataverseSearch` + `Get-PckAgentInfo` + `Invoke-PckCopilotPipeline` + `Export-PckSolutionBackup` + the guards in `Invoke-PckDataverseRequest` + the MCP shim. Rationale: shipping pillar B alone produces a competent tool with no reason to exist, since `pac` in a script step already does most of pillar B for anyone willing to write the script.
10. ~~**MCP verb for pillar A.**~~ **Signed off 2026-08-15:** `add-knowledge-source` added as the seventh verb. Canon 11 amended from six verbs to seven. Rationale: the capability nobody else has is the one an AI pair most needs a labeled verb for.

## 13. Non-goals

Written out so scope creep gets caught early.

- **Not** a Copilot Studio YAML authoring tool. The coatsy skills already cover that surface.
- **Not** a general Power Platform ALM tool. Focus is Copilot Studio agents plus the Dataverse artifacts they depend on. If a feature would apply equally to a canvas app, it does not belong here.
- **Not** an eval harness. `Test-PckCopilotAgent` may exist later but v0.1 does not include it.
- **Not** a hosted service. Local process, local auth profile, local SPN.
- **Not** a `pac` replacement. Everything falls back to `pac` primitives; the kit is discipline and guards, not a reimplementation.

---

## Decision log

| Date | Decision | Source |
|---|---|---|
| 2026-08-14 | Build tooling around Copilot Studio ALM first | User agreed with proposed wedge |
| 2026-08-14 | Ship both PS module and thin MCP server | User picked "both" from shape options |
| 2026-08-14 | Must also work with Power Platform Build Tools + GitHub Actions | User requirement |
| 2026-08-14 | Public / shareable / open source | User picked audience option |
| 2026-08-14 | Repo name `pac-copilot-kit`; module `PacCopilotKit`; npm `pac-copilot-kit-mcp` | User preferred over `Mit.*` prefix |
| 2026-08-14 | MCP server runs locally, stdio, `npx` launch | User requirement: reach Claude Code / Codex / Copilot |
| 2026-08-14 | Include native VS Code MCP config in samples | User confirmation |
| 2026-08-14 | Public home https://github.com/dgpblogster/pac-copilot-kit | User provided GitHub handle |
| 2026-08-14 | Design captured here; v0.1 scope pending | This document |
| 2026-08-14 | Guard funnel design (§6) signed off | User |
| 2026-08-14 | MCP verb set (§8.3) signed off | User |
| 2026-08-14 | v0.1 scope signed off: pipeline + backup + guards + MCP shim | User |
| 2026-08-14 | Design doc lives in `docs/` until repo creation, then moves to repo root | User |
| 2026-08-14 | Purpose restated as two pillars: capability (Dataverse knowledge sources) and paved road (executable ALM). Pillar A is the reason to install, pillar B the reason to keep | User, in the reconciliation conversation |
| 2026-08-14 | Claim fixed as "prescribed but not automatable" rather than "no ALM story". The stronger claim is defensible and survives Microsoft shipping a first-party agent task | Reconciliation against post-09 |
| 2026-08-14 | Forward-from-source added as design rule §5.9. Makes add-required-objects a non-gate for the pipeline | Reconciliation against post-09 |
| 2026-08-14 | `savedquery` guard corrected: no working Web API route exists, guard refuses instead of translating. Prior two-call claim withdrawn as unproven | Reconciliation against post-08 |
| 2026-08-14 | Knowledge component attaches via `parentbotid`, not the `bot_botcomponent` N:N. Prior wording corrected | Reconciliation against post-08 |
| 2026-08-14 | Harness guard added and treated as the highest-value preflight, given the silent non-grounding failure on `cliagent-1.0.0` | Reconciliation against post-08 |
| 2026-08-14 | v0.1 scope reopened (§12.9) and Web API token source raised as a new blocking question (§12.8) | This revision |
| 2026-08-15 | §12.8 closed: the Web API funnel acquires its own token and never depends on `pac` state. No `pac` command emits a token, and the VS Code extension is a GUI over the same machine-global profiles, so there is one code path for every developer | User, after verification against the `pac auth` reference |
| 2026-08-15 | §12.9 closed: v0.1 grows to include pillar A | User |
| 2026-08-15 | `SESSION-STATE.md` sanitized and kept tracked, rather than gitignored | User |
| 2026-08-15 | First live run (owner's tenant, Workbench environment): auth chain, discovery, WhoAmI, and harness classification all passed first try. Both harnesses present live; classified correctly | Live integration run |
| 2026-08-15 | War story 1 narrowed by live evidence and the guard redesigned from construction-refusal to attempt-and-translate (`Convert-PckSavedQueryFetchXmlError`). Sync flag, custom/system, and TableType ruled out as discriminators; discriminator unknown | Third-org verification pass |
| 2026-08-15 | `bot.authenticationmode` shape verified live; auth-mode fields added to `Get-PckAgentInfo` and `Assert-PckAgentAuthMode` guard shipped (exit 18, war story 3) | Live verification, canon 16 |
| 2026-08-16 | `New-PckKnowledgeSource` shipped and live-proven end to end: created, independently verified, and removed a real knowledge source on a live standard-harness agent. Pillar A is real | Live integration round trip |
| 2026-08-16 | The table-create half of `New-PckKnowledgeSource` (§7.1) deferred pending a parameter-shape decision; the cmdlet targets existing tables meanwhile | Implementation judgment, flagged in SESSION-STATE |
| 2026-08-16 | Observed: botcomponent delete cascades to the associated dvtablesearch records (§6.3 note); solution-existence preflight shipped as `Assert-PckSolutionExists` (exit 19, war story 5) | Live integration round trip |
| 2026-08-16 | Preflight exit codes consolidated to free slots in the full 10..19 range: SPN-incomplete folded into TokenUnavailable (11), invalid URL folded into EnvironmentInvalid (12); PacUnavailable takes 13, ProfileMisaligned takes 16. Pre-release, so no compatibility impact | Implementation need |
| 2026-08-16 | `Invoke-PckCopilotPipeline` shipped with the pac layer: single pac funnel with sensitive-argument redaction, version and profile-alignment guards built against live-verified output shapes, offline workspace lint, temporary CI profile lifecycle, and -WhatIf as the plan-deployment surface. War story 6 | This build |
| 2026-08-16 | Lint correction from red-first testing: YAML-level quoting is the only protection for Power Fx values containing colon-space; Power Fx's own quotes are invisible to YAML. The lint flags any non-YAML-quoted `=` value containing ': ' | Adversarial pass |
| 2026-08-16 | Live pipeline run passed end to end: drift guard refused the real misaligned profile (exit 16), then with an aligned profile the full loop ran clean (init workspace, lint over 15 Microsoft-authored files with zero false positives, pack to the predicted zip path, import and publish). Probe agent and solution removed afterward; environment left as found | Live run, owner participating |
| 2026-08-16 | War story 7 discovered and guarded the same day: pac exits 0 on errors it prints, three observed instances. The pac funnel no longer believes a zero exit code when the output carries an Error: line | Live run |
| 2026-08-16 | Noted for the MCP build: pac 2.10.1 ships a `pac copilot mcp` subcommand ("information about local MCP server"). Prior-art check required before building `pac-copilot-kit-mcp` (trust-but-verify) | Live run discovery |
| 2026-08-16 | Prior-art check done. Microsoft's `pac-mcp` (CLI 1.44+ dotnet-tool line) exposes pac commands as MCP tools and uses the active pac auth profile, so it inherits both the capability gap (no Dataverse knowledge sources) and the drift risk the kit guards against. `pac-copilot-kit-mcp` is the complement, not a duplicate: it exposes the guarded lifecycle. Positioning recorded here so it is not re-derived | Web verification against learn/agent-academy/pp-mcp |
| 2026-08-16 | `pac-copilot-kit-mcp` shipped: Node/TypeScript, stdio, seven verbs, startup preflight per §8.2, injection-safe bridge (tool arguments travel as JSON in environment variables, never on a command line; cmdlets from a fixed allowlist), typed exit codes surfaced to the client, `explain-failure` reasoning locally with a memory of the session's last failure. Proven by a stdio smoke test and a live full-stack probe in which the drift guard refused through MCP and `explain-failure` explained it unprompted | This build |
| 2026-08-16 | `Sync-PckCopilotAgent` shipped as the thin guarded wrapper over `pac copilot pull` (argument shape verified live: `--project-dir` only), completing the cmdlet behind the `pull-agent` verb | This build |
| 2026-08-16 | Spec body trued up to the code-complete state: status header, §5.2 resolution note, §6 and §7 implementation-status markers (shipped versus designed-not-built, and the guards that shipped in a different shape than sketched), §8.4 bridge as built, §10 sketch corrected for `-PublisherPrefix`, §11 layout as built, §12 header. The decision log alone is not the spec | Owner asked whether the spec was current; audit said no |
| 2026-08-15 | Repo created public, then flipped private the same day: the design doc condenses two unpublished articles, and the repo should not front-run their debut. Public again when both publish. Canon 13 discipline unchanged while private | User |
| 2026-08-15 | All remaining §12 items closed: §7 names as proposed with the `Pck` prefix kept after a `Pac`-prefix challenge, PowerShell 7.4+, Node 20 LTS, manual Gallery publish for v0.1, war-stories owned here, seventh MCP verb `add-knowledge-source` added (canon 11 amended) | User ("let's build") |
| 2026-08-15 | `Test-PckCopilotAgent` stays deferred to v0.2. It sits on the eval-harness non-goal boundary and its proposed dependency is unverified. The v0.2 candidate shape is a deployment smoke test (one grounded question with citations), which serves pillar B, rather than eval CSVs | User |

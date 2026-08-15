# pac-copilot-kit — Project Memory

Paved-road toolkit around Microsoft Power Platform CLI (`pac`) for the Copilot Studio agent lifecycle. Ships a PowerShell module (`PacCopilotKit`) and a local MCP server (`pac-copilot-kit-mcp`) that shells to it, so agent authors get the same guarded lifecycle in a shell, in CI, and from Claude Code / GitHub Copilot / ChatGPT Codex.

## How memory works in this repo

Four files, four jobs. Do not conflate them.

| File | Role | Update when |
|---|---|---|
| `CLAUDE.md` (this file) | **Canons** — settled decisions. Stable; changes rarely. | A canon is added, amended, or overturned |
| `docs/pac-copilot-kit-design.md` | **Design** — full architecture, guard funnel, MCP verb set, repo layout, open questions, and the **decision log** with rationale (§bottom) | A design decision is made or revised, or a §12 open question closes |
| `SESSION-STATE.md` | **Recovery brief** — everything a fresh AI session needs to resume without the prior chat: what is settled, what is open, what the next action is, owner style rules | End of every working session, before any large or risky operation, and after any change to the open-questions ledger |
| `CHANGELOG.md` | **Asset changes** — Keep a Changelog format, tracks what was added/changed/removed in code, configs, docs, samples. Not a narrative, not a decision log. | Every commit that changes a shipped asset |

**Session protocol (for any AI pair):**
1. On session start, read this file first, then `SESSION-STATE.md`, then skim `docs/pac-copilot-kit-design.md`. That is sufficient to resume without the prior chat.
2. Design decisions land in the design doc's decision log the same turn they are made. Promote to a canon below only if durable and cross-cutting.
3. Asset changes (files added/edited/removed) land in `CHANGELOG.md` under `[Unreleased]` the same turn.
4. Volatile state (in-progress task, current blocker, next action) lives only in `SESSION-STATE.md`. Never store it in this file or the changelog.

## Project facts

| Fact | Value |
|---|---|
| Name | `pac-copilot-kit` |
| PS module | `PacCopilotKit` (cmdlet noun prefix `Pck`; env var prefix `PCK_`) |
| MCP server (npm) | `pac-copilot-kit-mcp` |
| Local workspace | `C:\AL\pac-copilot-kit` *(renamed; not yet a git repository, see canon 12)* |
| Public home | https://github.com/dgpblogster/pac-copilot-kit *(created; private until the two source articles publish, then public)* |
| License | MIT |
| Owner | Mariano Gomez Bent |
| Status | all §12 design questions closed 2026-08-15; v0.1 build in progress |

## Canons (settled decisions — do not re-litigate without owner say-so)

1. **The kit has two pillars and nothing else.** *(amended 2026-08-14)* **Pillar A, capability:** create Dataverse knowledge sources in-solution and repeatably, which `pac` cannot do at all. **Pillar B, paved road:** make Microsoft's published Copilot Studio ALM prescription executable, in a shell and in CI. A is why someone installs the kit, B is why they keep it. It remains the transport and environment discipline layer, and it is not a `pac` replacement, not a YAML authoring tool, not a hosted service, not an eval harness. Full non-goals in the design doc §13. Any proposed feature tracing to neither pillar belongs elsewhere.
2. **Two components, one engine.** The PowerShell module is the source of truth. The MCP server is a thin stdio shim that shells to `pwsh -NoProfile -Command …` per tool call. Every user-facing behavior lives in the module; the MCP layer is contract translation only.
3. **No interactive prompts in the engine, ever.** No `Read-Host`, no `pac org select`, no implicit `$PWD` dependence. Every input is a parameter or an env var. This is what makes dev and CI mode share one call site.
4. **Environment id is always explicit.** Resolution order: `-EnvironmentId` parameter → `PCK_DEFAULT_ENVIRONMENT_ID` env var → hard error. The `pac auth` profile's default org is never trusted (documented drift risk from the source POC).
5. **One Web API funnel.** Every Dataverse Web API call routes through `Invoke-PckDataverseRequest`. No `Invoke-RestMethod` in public cmdlets. All wrap-and-translate guards for the pac war stories live in that one helper.
6. **Guard-authoring contract.** New guard = one file under `Private/Guards/`, one Pester test proving the untranslated call fails and the translated call succeeds, one line in `docs/war-stories.md`. No guards merge without all three.
7. **Solution-aware by default.** Every mutating Dataverse call sets `MSCRM.SolutionUniqueName` from the `-SolutionName` parameter. There is no path in the module to create a solution-orphaned component.
8. **Structured output + non-zero exits.** Every public cmdlet accepts `-Json` and writes one well-formed object to stdout; human output goes to stderr / host. Failures produce non-zero exit codes so CI can trust them.
9. **Distinct exit code range for preflight vs operational failure.** `10..19` = preflight guard tripped (environment misconfigured). Everything else = operation failed. Keeps CI diagnostics unambiguous.
10. **MCP over stdio only in v0.1.** Codex CLI is stdio-only; stdio is the lowest common denominator that keeps all three clients on one server binary. HTTP/SSE deferred; add it later as a second transport behind a flag, same tool handlers.
11. **MCP surface is task-shaped, not cmdlet-mirrored.** *(amended 2026-08-15)* Seven verbs in §8.3 of the design doc, locked: the original six plus `add-knowledge-source`, so pillar A has a labeled verb. AI agents pick better from seven well-labeled verbs than thirty look-alike ones.
12. ~~**Folder rename to `pac-copilot-kit` is deferred to repo creation**~~ *(superseded 2026-08-14)*. The rename happened ahead of `git init` rather than with it. The workspace is `C:\AL\pac-copilot-kit` and is **not yet a git repository**. The pairing this canon required is moot; what remains is `git init` plus the GitHub remote.
13. **Public / open source from day one.** MIT license. No POC-tenant details, no customer names, no environment ids, no bot ids in shipped code, samples, or docs. This applies to `SESSION-STATE.md` and the design doc too, since both ship. The `docs/war-stories.md` file is the sanitized version; the source blog drafts are the private working copy and are not pathed in any tracked file.
14. **The claim is "prescribed but not automatable," never "there is no ALM story"** (added 2026-08-14). Microsoft's Copilot Studio ALM guidance exists, is sound, and has not wavered. What is missing is the road: no agent task in Power Platform Build Tools, no agent-aware GitHub Action, no reference pipeline, a portal click in the middle, and a component type with no code path. The precise claim is defensible and survives Microsoft shipping a first-party agent task later. The overstated one loses the argument the moment somebody links the golden-rules page.
15. **Forward from source, never round-trip** (added 2026-08-14). The repository is the artifact. Deployments pack YAML the repo owns and run component scripts the repo owns; nothing is inferred from what a solution in an environment happens to contain. This is what makes the pipeline automatable, because the add-required-objects portal click governs export fidelity and therefore never gates a forward deployment. `Export-PckSolutionBackup` produces a backup, explicitly not a source of truth. Any feature that promotes an exported zip to source of truth reintroduces a manual precondition and does not belong in the kit.
16. **The design doc is not the primary source for platform behavior** (added 2026-08-14). Two private blog drafts, the Dataverse knowledge article and the agent ALM article, record what the POC actually proved. They are not pathed here (canon 13); on the owner's machine they are in local memory, otherwise ask. The first design pass was written from conversation alone and got three platform claims wrong. Reconcile against the articles before encoding any claim about `pac`, Dataverse, or Copilot Studio behavior as a guard.

## Key files

- [SESSION-STATE.md](SESSION-STATE.md) — start here after this file. Recovery brief for the next session.
- [docs/pac-copilot-kit-design.md](docs/pac-copilot-kit-design.md) — full design; §12 tracks open questions; decision log at §bottom.
- [CHANGELOG.md](CHANGELOG.md) — asset changes only.
- (planned) `README.md` — public entrypoint, written at repo creation.
- (planned) `docs/war-stories.md` — publishable pac + Dataverse gotchas inventory, sanitized from the blog draft.

## Conventions

- Design decisions land in the design doc's decision log (bottom of file), in reverse-chronological order, dated absolute.
- Canons are numbered and stable. Amend by editing in place with a `(amended YYYY-MM-DD)` marker; do not renumber.
- Cmdlets are `Verb-Pck<Noun>`; env vars are `PCK_<UPPER_SNAKE>`; MCP verbs are `kebab-case` and phrased as tasks, not APIs.
- PowerShell floor: 7.4+. Node floor for MCP server: 20 LTS. (Both signed off 2026-08-15.)
- No em dashes in shipped docs and samples (owner style rule inherited from the source project).

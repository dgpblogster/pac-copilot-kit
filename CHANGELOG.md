# Changelog

All notable changes to project assets (code, configs, docs, samples). Not a running narrative — the "why" for design decisions lives in [docs/pac-copilot-kit-design.md](docs/pac-copilot-kit-design.md)'s decision log; in-flight status lives in [SESSION-STATE.md](SESSION-STATE.md).

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

Nothing yet.

## [0.1.0] - 2026-08-16

First release. `PacCopilotKit` 0.1.0 on the PowerShell Gallery; `pac-copilot-kit-mcp` 0.1.0 on npm, both under The Workbench Blog. Everything below this line shipped in it.

### Changed (war story 7 root cause, 2026-08-16)
- War story 7 upgraded from symptom to root cause: `pac.launcher.exe` (v1.0.7, dated September 2019) discards exit codes; the versioned `pac.exe` underneath returns them honestly. A/B verified live; upstream issues #912 and #1027 linked; dotnet-tool install documented as the launcher-free path. `docs/war-stories.md`, `README.md` (launcher NOTE, "How it earned its scars" section with the open discriminator challenge, agent-section trust note), and `ci/README.md` updated. No code change: the funnel guardrail already covered both flavors.

### Added (CI recipes, 2026-08-16)
- `ci/github-actions/deploy-agent.yml` and `ci/azure-pipelines/deploy-agent.yml`: plan-then-deploy pipelines using the kit's CI mode (temporary pac profile, no who-am-i step). Syntax-validated; end-to-end run recorded after the Gallery publish, per `ci/README.md`.
- `ci/README.md`: variable wiring, why the recipes are short, reading typed failures in a log, and the pre-release from-source install variant.

### Changed (terminology and MCP docs, 2026-08-16)
- "Guard" renamed to "guardrail" across all docs, error messages, and the `Private/Guardrails/` folder, with the two tiers named preflight checks and error translators; internal registries renamed to match (`PckRequestConstructionChecks`, `PckErrorTranslators`). Verb uses of "guard" kept; no public cmdlet names affected. Full suite re-run green (109 unit), MCP server rebuilt and smoke-tested.
- README gains "Installing the MCP server" (build from clone, client wiring, the pac-mcp distinction); `docs/mcp-clients.md` added with the full walkthrough: prerequisites, environment variables, the seven verbs, refusal semantics, and startup troubleshooting.

### Added
- `src/PacCopilotKit/` module skeleton: `PacCopilotKit.psd1` (0.1.0, PowerShell 7.4 floor), `PacCopilotKit.psm1` with the `PckError` / `PckPreflightError` types and the exit-code registry.
- Web API funnel `Invoke-PckDataverseRequest` (canon 5): construction-guardrail dispatch, solution-header enforcement with explicit `-NoSolution` opt-out (canon 7), Retry-After honoring retry on 429/503, error translation, created-EntityId extraction.
- Token acquisition per design §12.8: `Get-PckAccessToken` (SPN client credentials in CI; `PCK_ACCESS_TOKEN`, then `az`, then `Az.Accounts` in dev), `Get-PckJwtExpiry`, `Get-PckAuthHeaders`.
- Environment resolution: `Resolve-PckEnvironmentId` (canon 4), `Resolve-PckOrgUrl` via global discovery.
- Public cmdlets: `Connect-PckPowerPlatform`, `Get-PckAgentInfo`.
- Guardrails: `Assert-PckSavedQueryFetchXmlRoute` (war story 1, refuses with exit 20), `Assert-PckAgentHarness` (war story 2, refuses with exit 14).
- `Private/EntitySetPluralOverrides.psd1` with the `dvtablesearchs` entry.
- `docs/war-stories.md` with stories 1 and 2, satisfying canon 6 for both shipped guardrails.
- `tests/PacCopilotKit.Tests/`: 31 unit tests (all passing) plus 3 live-environment integration tests tagged `Integration`, including the story 1 proof that the raw savedquery PATCH still fails with `0x80040216`.
- `tests/PacCopilotKit.Tests/PckAdversarial.Tests.ps1`: 13 adversarial tests written red-first against the walking skeleton; 7 landed as real defects, fixed below. Suite total 44 unit tests, all passing.

### Added (MCP server, 2026-08-16)
- `src/pac-copilot-kit-mcp/`: the v0.1 MCP server. Node/TypeScript, stdio, seven verbs (`plan-deployment`, `run-pipeline`, `backup-solution`, `pull-agent`, `add-knowledge-source`, `wait-for-search`, `explain-failure`) shelling to the module per canon 2. Startup preflight per design 8.2 (pwsh floor, module import, pac presence) fails the launch loudly instead of a silent tool-not-found later.
- Injection-safe bridge: tool arguments travel as JSON in environment variables and are splatted inside PowerShell, never concatenated onto a command line; cmdlets come from a fixed allowlist.
- Typed failures: a non-zero cmdlet exit code (the PckError codes) becomes the child process exit code, is surfaced to the MCP client with its registry name, and is remembered so `explain-failure` can explain the session's last failure unprompted, locally, with no environment round trip.
- `Sync-PckCopilotAgent`: thin guarded wrapper over `pac copilot pull` (argument shape verified live), completing the cmdlet behind `pull-agent`. 3 unit tests.
- `tests/smoke.mjs` (handshake, seven tools advertised, local reasoning) and `tests/live-probe.mjs` (full-stack proof: the drift guardrail refused through MCP with exit 16 and `explain-failure` explained it). Both passing.
- `samples/mcp-config/`: copy-paste configs for Claude Code, VS Code, and Codex CLI, with the npx swap noted for after the npm publish.
- Design decision log: positioning against Microsoft's `pac-mcp` recorded. Theirs exposes pac commands and rides the active pac profile; ours exposes the guarded lifecycle. Complement, not duplicate.

### Added (live pipeline run, 2026-08-16)
- `Invoke-PckCopilotPipeline` live-proven end to end: the drift guardrail refused a genuinely misaligned profile with exit 16, and with an aligned profile the full loop ran clean against a real environment (lint over 15 Microsoft-authored scaffold files with zero false positives, pack to the predicted zip path, import and publish). Probe artifacts removed; environment left as found.
- War story 7: pac exits 0 on errors it prints, observed three times live. `Invoke-PckPacCommand` no longer believes a zero exit code when the output carries an `Error:` line, with the same sensitive redaction; two red-first tests pin it. Suite: 106 unit + 4 live.

### Changed (README rewrite, 2026-08-16)
- `README.md` reauthored in the owner's voice per the private voice profile: narrative why-this-exists, the loop with commentary, and honest boundaries, replacing the spec-sheet register.
- New README section "If you are an AI agent working with this kit": install-from-source steps, floor checks, the explicit-environment rule, the `-Json` contract, the exit-code decision table, the refusals-are-information rule, real-wait guidance, and dry-run-first.

### Added (pillar B pipeline, 2026-08-16)
- `Invoke-PckCopilotPipeline`: connect, pac floor, pac auth (implicit CI/dev mode; temporary CI profile deleted on exit even on failure), offline workspace lint, `pac copilot pack`, `pac solution import --publish-changes`. `-WhatIf` runs the read-only steps and reports the rest, which is the surface the MCP `plan-deployment` verb will wrap.
- `Invoke-PckPacCommand`: the single pac funnel, mirroring the Web API funnel. `-Sensitive` withholds arguments **and** output from errors and logging, because pac may echo argument context.
- `Assert-PckPacVersion` (exit 13) and `Assert-PckProfileAligned` (exit 16), both built against pac output shapes verified live on 2026-08-16. War story 6.
- `Test-PckAgentWorkspace`: offline lint with named checks (workspace shape, tab indentation, Power Fx colon-space).
- 25 new unit tests including adversarial cases: secret never leaks through a failing sensitive command, hostile solution names and prefixes refused before pac sees them, drifted profile blocks pack and import, WhatIf runs nothing mutating, CI profile deleted on failure. Suite: 104 unit + 4 live.

### Changed (2026-08-16)
- Preflight exit codes consolidated: SPN-incomplete now 11 (was 13), invalid environment URL now 12 (was 16); 13 is `PacUnavailable`, 16 is `ProfileMisaligned`. Pre-release, no released consumers.
- Workspace lint rule corrected during the red-first pass: Power Fx's own quotes do not protect a YAML scalar, so any non-YAML-quoted `=` value containing ': ' is flagged.
- `README.md` loop example updated to shipped reality: knowledge-source step and backup step no longer marked planned, pipeline collapse shown with `-WhatIf` first, CI note added.

### Added (pillar A live-proven, 2026-08-16)
- `New-PckKnowledgeSource`: the headline cmdlet. Full preflight (harness, auth mode, solution existence, table existence, duplicate search name), the four-record create chain inside the solution, best-effort rollback on mid-chain failure, and honest warnings for the two preconditions it cannot solve (org search flag; find columns). Live-proven end to end: created, independently verified, and removed a real knowledge source on a live agent.
- `Assert-PckSolutionExists` preflight check (exit 19). War story 5.
- `Get-PckQuickFindColumns` private helper: reads the find columns Dataverse search actually indexes, using the war story 4 filter.
- Design §6.3 note: botcomponent delete cascades to the associated dvtablesearch records (observed live).
- 14 new unit tests plus a live end-to-end integration round trip. Suite: 79 unit + 4 live, all passing.

### Added (first live run, 2026-08-15)
- `Get-PckAgentInfo` now returns `AuthenticationMode` and `AuthenticationModeName`; `bot.authenticationmode` picklist verified live (0 Unspecified, 1 None, 2 Integrated, 3 Custom Entra ID, 4 Generic OAuth2).
- `Assert-PckAgentAuthMode` preflight check (exit 18): only Integrated grounds on Dataverse knowledge. War story 3.
- Response-translator tier in the funnel (`$script:PckErrorTranslators`); first translator `Convert-PckSavedQueryFetchXmlError`.
- War story 4: `savedquery.returnedtypecode` filters only as a quoted logical name. Inventory, no guardrail yet.
- Live integration results: auth chain, discovery, WhoAmI, and harness classification passed first try against a real tenant with both harnesses present.

### Changed (war story 1 correction, 2026-08-15)
- Savedquery fetchxml guardrail redesigned from construction-refusal to attempt-and-translate after third-org live verification showed the failure is broad but not universal (minority of views accept the call; discriminator unidentified after ruling out sync flag, custom/system, and TableType). `Assert-PckSavedQueryFetchXmlRoute` removed; `Convert-PckSavedQueryFetchXmlError` added. Unit, adversarial, and integration suites reworked to assert the translation contract; the integration test now skips loudly if the story ever stops reproducing.

### Changed (README)
- `README.md` gains an end-to-end loop example interleaving `pac` and kit commands, with a pac/kit division-of-labor table and an explicit shipped-today versus planned-for-v0.1 line.

### Fixed
- Savedquery guardrail (war story 1) was bypassable by respelling the request: absolute URL, leading-slash path, raw JSON string body, and a query string on the single-property route all slipped past. The funnel now normalizes the path and parses string bodies before guardrail dispatch, and the guardrail's suffix match tolerates query strings.
- `Get-PckAgentInfo -Json` returned null on an empty result set instead of `[]`, breaking canon 8's one-well-formed-object contract.
- `Connect-PckPowerPlatform` accepted a plain-http `-EnvironmentUrl`, which would have sent bearer tokens over http. Refused with new preflight exit code 16.
- `LICENSE` (MIT), `README.md` public entrypoint, `.gitignore`.
- Repository initialized with git. First commit.
- Design §12.8 closed: Web API funnel acquires its own token, independent of `pac`. CI uses SPN client credentials with no extra dependency; dev resolves `PCK_ACCESS_TOKEN`, then `az`, then `Az.Accounts`.
- Design §12.9 closed: v0.1 grows to include pillar A.
- `CLAUDE.md` — canons file, session protocol, project facts, conventions.
- `docs/pac-copilot-kit-design.md` — full architecture design with signed-off guardrail funnel, MCP verb set, v0.1 scope, and open questions ledger.
- `SESSION-STATE.md` — recovery brief for resuming after folder rename.
- `CHANGELOG.md` — this file.
- `docs/pac-copilot-kit-design.md` §0 revision note, §6.3 record shapes, §7.1–§7.3 pillar-tagged cmdlet surface, §10.3 what is genuinely not automatable.
- New preflight checks in design §6.1: `Assert-PckAgentHarness`, `Assert-PckAgentAuthMode`, `Assert-PckDataverseSearchEnabled`.
- New error translators in design §6.2: find columns, `SyncToExternalSearchIndex` at create time, memo `Format: TextArea`, flow-not-in-solution, Power Fx colon-space YAML parse.
- New proposed cmdlets in design §7: `New-PckKnowledgeSource`, `Enable-PckDataverseSearch`, `Get-PckAgentInfo`, `Edit-PckSolutionXml`, `Test-PckSolutionCompleteness`, `Get-PckPostDeployChecklist`.
- New design rule §5.9, forward from source, never round-trip.
- New open questions §12.8 (Web API token source), §12.9 (v0.1 rescope), §12.10 (MCP verb for pillar A).

### Changed
- `docs/pac-copilot-kit-design.md` §1 and §2 restated around two pillars: capability (Dataverse knowledge sources) and paved road (executable ALM).
- Design §12.1 v0.1 scope marked reopened.
- Design §8.3 annotated with the pillar A verb gap.
- Workspace path references corrected to the current folder.
- Private working-area paths removed from all tracked files per canon 13.
- Sample environment ids in design §9 replaced with an all-zero placeholder; solution and SPN names in §10 desourced to `WorkbenchSupportAssistant` / `WorkbenchSandbox-SPN`; POC product name and paths removed from design §1 and §2. All per canon 13.
- Em dashes removed from the design doc per the owner style rule.

### Fixed
- Design §6.2 `savedquery` guardrail: no working Web API route exists. The prior claim of a `layoutxml`-first two-call translation is withdrawn as unproven; the guardrail now refuses and names solution surgery or the portal path.
- Design §6.3: knowledge components attach via the `parentbotid` lookup, not the `bot_botcomponent` N:N relationship. Prior "N:N intersect" wording corrected.
- Design §5: noted that the Web API token source was never specified and conflicts with the POC's proven `pac`-independent approach. Raised as §12.8.
- `CLAUDE.md` canon 1 amended to the two-pillar definition; canon 12 superseded (rename already happened, `git init` still pending); canon 13 extended to cover `SESSION-STATE.md` and the design doc; canons 14, 15, and 16 added.
- `SESSION-STATE.md` reframed around the two pillars, open-questions ledger grown to eight, stale rename statements corrected, and the sandbox name and environment id removed per canon 13.

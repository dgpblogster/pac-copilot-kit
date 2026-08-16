# Changelog

All notable changes to project assets (code, configs, docs, samples). Not a running narrative — the "why" for design decisions lives in [docs/pac-copilot-kit-design.md](docs/pac-copilot-kit-design.md)'s decision log; in-flight status lives in [SESSION-STATE.md](SESSION-STATE.md).

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- `src/PacCopilotKit/` module skeleton: `PacCopilotKit.psd1` (0.1.0, PowerShell 7.4 floor), `PacCopilotKit.psm1` with the `PckError` / `PckPreflightError` types and the exit-code registry.
- Web API funnel `Invoke-PckDataverseRequest` (canon 5): construction-guard dispatch, solution-header enforcement with explicit `-NoSolution` opt-out (canon 7), Retry-After honoring retry on 429/503, error translation, created-EntityId extraction.
- Token acquisition per design §12.8: `Get-PckAccessToken` (SPN client credentials in CI; `PCK_ACCESS_TOKEN`, then `az`, then `Az.Accounts` in dev), `Get-PckJwtExpiry`, `Get-PckAuthHeaders`.
- Environment resolution: `Resolve-PckEnvironmentId` (canon 4), `Resolve-PckOrgUrl` via global discovery.
- Public cmdlets: `Connect-PckPowerPlatform`, `Get-PckAgentInfo`.
- Guards: `Assert-PckSavedQueryFetchXmlRoute` (war story 1, refuses with exit 20), `Assert-PckAgentHarness` (war story 2, refuses with exit 14).
- `Private/EntitySetPluralOverrides.psd1` with the `dvtablesearchs` entry.
- `docs/war-stories.md` with stories 1 and 2, satisfying canon 6 for both shipped guards.
- `tests/PacCopilotKit.Tests/`: 31 unit tests (all passing) plus 3 live-environment integration tests tagged `Integration`, including the story 1 proof that the raw savedquery PATCH still fails with `0x80040216`.
- `tests/PacCopilotKit.Tests/PckAdversarial.Tests.ps1`: 13 adversarial tests written red-first against the walking skeleton; 7 landed as real defects, fixed below. Suite total 44 unit tests, all passing.

### Added (pillar A live-proven, 2026-08-16)
- `New-PckKnowledgeSource`: the headline cmdlet. Full preflight (harness, auth mode, solution existence, table existence, duplicate search name), the four-record create chain inside the solution, best-effort rollback on mid-chain failure, and honest warnings for the two preconditions it cannot solve (org search flag; find columns). Live-proven end to end: created, independently verified, and removed a real knowledge source on a live agent.
- `Assert-PckSolutionExists` preflight guard (exit 19). War story 5.
- `Get-PckQuickFindColumns` private helper: reads the find columns Dataverse search actually indexes, using the war story 4 filter.
- Design §6.3 note: botcomponent delete cascades to the associated dvtablesearch records (observed live).
- 14 new unit tests plus a live end-to-end integration round trip. Suite: 79 unit + 4 live, all passing.

### Added (first live run, 2026-08-15)
- `Get-PckAgentInfo` now returns `AuthenticationMode` and `AuthenticationModeName`; `bot.authenticationmode` picklist verified live (0 Unspecified, 1 None, 2 Integrated, 3 Custom Entra ID, 4 Generic OAuth2).
- `Assert-PckAgentAuthMode` preflight guard (exit 18): only Integrated grounds on Dataverse knowledge. War story 3.
- Response-translator tier in the funnel (`$script:PckResponseTranslators`); first translator `Convert-PckSavedQueryFetchXmlError`.
- War story 4: `savedquery.returnedtypecode` filters only as a quoted logical name. Inventory, no guard yet.
- Live integration results: auth chain, discovery, WhoAmI, and harness classification passed first try against a real tenant with both harnesses present.

### Changed (war story 1 correction, 2026-08-15)
- Savedquery fetchxml guard redesigned from construction-refusal to attempt-and-translate after third-org live verification showed the failure is broad but not universal (minority of views accept the call; discriminator unidentified after ruling out sync flag, custom/system, and TableType). `Assert-PckSavedQueryFetchXmlRoute` removed; `Convert-PckSavedQueryFetchXmlError` added. Unit, adversarial, and integration suites reworked to assert the translation contract; the integration test now skips loudly if the story ever stops reproducing.

### Changed (README)
- `README.md` gains an end-to-end loop example interleaving `pac` and kit commands, with a pac/kit division-of-labor table and an explicit shipped-today versus planned-for-v0.1 line.

### Fixed
- Savedquery guard (war story 1) was bypassable by respelling the request: absolute URL, leading-slash path, raw JSON string body, and a query string on the single-property route all slipped past. The funnel now normalizes the path and parses string bodies before guard dispatch, and the guard's suffix match tolerates query strings.
- `Get-PckAgentInfo -Json` returned null on an empty result set instead of `[]`, breaking canon 8's one-well-formed-object contract.
- `Connect-PckPowerPlatform` accepted a plain-http `-EnvironmentUrl`, which would have sent bearer tokens over http. Refused with new preflight exit code 16.
- `LICENSE` (MIT), `README.md` public entrypoint, `.gitignore`.
- Repository initialized with git. First commit.
- Design §12.8 closed: Web API funnel acquires its own token, independent of `pac`. CI uses SPN client credentials with no extra dependency; dev resolves `PCK_ACCESS_TOKEN`, then `az`, then `Az.Accounts`.
- Design §12.9 closed: v0.1 grows to include pillar A.
- `CLAUDE.md` — canons file, session protocol, project facts, conventions.
- `docs/pac-copilot-kit-design.md` — full architecture design with signed-off guard funnel, MCP verb set, v0.1 scope, and open questions ledger.
- `SESSION-STATE.md` — recovery brief for resuming after folder rename.
- `CHANGELOG.md` — this file.
- `docs/pac-copilot-kit-design.md` §0 revision note, §6.3 record shapes, §7.1–§7.3 pillar-tagged cmdlet surface, §10.3 what is genuinely not automatable.
- New preflight guards in design §6.1: `Assert-PckAgentHarness`, `Assert-PckAgentAuthMode`, `Assert-PckDataverseSearchEnabled`.
- New wrap-and-translate guards in design §6.2: find columns, `SyncToExternalSearchIndex` at create time, memo `Format: TextArea`, flow-not-in-solution, Power Fx colon-space YAML parse.
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
- Design §6.2 `savedquery` guard: no working Web API route exists. The prior claim of a `layoutxml`-first two-call translation is withdrawn as unproven; the guard now refuses and names solution surgery or the portal path.
- Design §6.3: knowledge components attach via the `parentbotid` lookup, not the `bot_botcomponent` N:N relationship. Prior "N:N intersect" wording corrected.
- Design §5: noted that the Web API token source was never specified and conflicts with the POC's proven `pac`-independent approach. Raised as §12.8.
- `CLAUDE.md` canon 1 amended to the two-pillar definition; canon 12 superseded (rename already happened, `git init` still pending); canon 13 extended to cover `SESSION-STATE.md` and the design doc; canons 14, 15, and 16 added.
- `SESSION-STATE.md` reframed around the two pillars, open-questions ledger grown to eight, stale rename statements corrected, and the sandbox name and environment id removed per canon 13.

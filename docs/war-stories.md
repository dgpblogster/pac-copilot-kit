# War stories

The `pac` and Dataverse Web API gotchas this kit's guards encode. Each entry exists because the failure was hit in a real project, reproduced, and worked around; the guard converts that afternoon into an error message.

The guard-authoring contract (CLAUDE.md canon 6): every guard ships as one file under `Private/Guards/`, one Pester test, and one entry here. No entry, no guard. Entries are numbered and stable; guards reference them by number.

Some entries describe undocumented platform behavior, discovered by inspecting what the maker portal writes. Those shapes can change in any release. If a guard's integration test starts failing in the direction of "the broken thing now works," this file is where the re-verification gets recorded.

---

## Story 1: savedquery fetchxml updates fail with 0x80040216 on most views

**Symptom.** Updating a saved query's `fetchxml` column returns `0x80040216`: record PATCH and single-property PUT alike. `layoutxml` on the very same record updates fine. Whatever message the maker portal sends when you edit find columns, the Web API `savedquery` update path is not it.

**Reproduced, with a correction.** First reproduced in two orgs (one production-grade Dynamics 365 CE, one freshly provisioned vanilla) where every attempted route failed. A third-org verification pass on 2026-08-15 narrowed the claim: the failure reproduces on most Quick Find views, and a minority accept the very same call.

Verification log, 2026-08-15, one org, same identity, same-value PATCH per view:

| View's table | Kind | TableType | Search-synced | Result |
|---|---|---|---|---|
| a custom grounding table | custom | Standard | yes | `0x80040216` |
| `adx_externalidentity`, `adx_invitation`, `adx_inviteredemption` | custom | Standard | no | `0x80040216` |
| `applicationuser` | custom | Standard | no | `0x80040216` |
| `appnotification` | custom | Elastic | no | `0x80040216` |
| `privilegecheckerrun` | system | Standard | no | succeeded |
| `aaduser` | custom | Virtual | no | succeeded |

Custom versus system, `SyncToExternalSearchIndex`, and `TableType` were each tested as the discriminator and ruled out. **The discriminator is not yet identified.** Treat any success as a bonus and plan for the failure.

**Why it matters.** Dataverse search indexes the columns configured as find columns on a table's Quick Find view, and a fresh custom table's Quick Find view carries exactly one, the primary name. Every other column is invisible to search, and therefore to a Copilot Studio agent grounding on the table, until the view's `fetchxml` changes. This is the difference between "source attached" and "agent grounded."

**What works.**
- Solution surgery: export the solution, edit the savedquery block in `customizations.xml`, re-zip, import. Automates cleanly.
- The maker portal: Tables, your table, Views, open the Quick Find view, Edit find table columns, Save and publish.

**Guard.** `Convert-PckSavedQueryFetchXmlError`, a response translator in the Web API funnel. Because a minority of views accept the call, refusing at construction would block working requests; the funnel attempts the call and, when the `0x80040216` signature comes back on a savedquery fetchxml route, throws the war story (exit code 20) with both working alternatives instead of an opaque code. This replaced an earlier construction-refusal guard the same day the third-org evidence landed, which is exactly the correction loop this file exists for.

**Tests.** Unit: the translator enriches record PATCH and single-property PUT failures in every spelling (absolute URL, leading slash, raw JSON string body, query-string suffix), leaves the same code on unrelated entities untranslated, and lets successful fetchxml and layoutxml updates through. Integration (tagged, live environment): probes several custom-table Quick Finds with same-value PATCHes and asserts the translation contract on the first real failure; if every probed view accepts the call, the test skips loudly saying this story needs re-verification (canon 16).

## Story 2: the newer agent experience displays knowledge sources it never queries

**Symptom.** A Dataverse knowledge component created via the Web API against an agent built in the newer Copilot Studio experience (template `cliagent-1.0.0`) appears in the agent's Knowledge panel, exactly as if it were wired correctly. The runtime never queries it. The agent answers from general model knowledge and states it has no documents. No error surfaces anywhere: not at create time, not in the panel, not at runtime.

**Why.** The Knowledge panel reads the same `botcomponent` table regardless of harness, but Dataverse knowledge is a standard-harness feature. The newer experience does not offer Dataverse in its Add knowledge dialog, and its runtime does not consume `componenttype` 16 components.

**Detection.** `GET /api/data/v9.2/bots?$select=name,schemaname,template`. A `template` of `default-*` is the standard harness; `cliagent-*` is the newer experience.

**What works.** Build standard-harness agents: turn the New experience toggle off on the Copilot Studio homepage, or pick Other ways to build.

**Guard.** `Assert-PckAgentHarness`, a preflight guard (exit code 14). Standard passes; the newer experience is refused with the failure mode spelled out; unrecognized templates are refused too, because the failure this guard prevents is silent and unrecognized is unsafe. `Get-PckAgentInfo` exposes the same classification as data.

**Tests.** Unit: classification of `default-*`, `cliagent-*`, and unknown templates; refusal messages and exit codes. Integration (tagged): classifies every agent in the live environment.

## Story 3: only Integrated end-user authentication grounds on Dataverse knowledge

**Symptom.** Dataverse knowledge sources attached to an agent whose end-user authentication is anything other than "Authenticate with Microsoft" display normally and are never searched. Documented by Microsoft, silent at runtime, and easy to miss because the attachment itself succeeds.

**Storage shape, verified live 2026-08-15.** `bot.authenticationmode` is a picklist: 0 Unspecified, 1 None, 2 Integrated ("Authenticate with Microsoft"), 3 Custom Entra ID, 4 Generic OAuth2. Only 2 grounds.

**Guard.** `Assert-PckAgentAuthMode`, a preflight guard (exit code 18). Mode 2 passes; every other verified mode is refused with the failure mode spelled out; unparseable values are refused rather than passed, because the failure this guard prevents is silent. `Get-PckAgentInfo` exposes both the raw value and its label.

**Tests.** Unit: pass on 2, refusal on 0, 1, 3, 4, unparseable values, and objects with no mode property. Integration: the mode is read live for every agent via `Get-PckAgentInfo`.

## Story 4: savedquery.returnedtypecode filters only as a quoted logical name

**Symptom.** `savedquery.returnedtypecode` serializes in responses as the entity's logical name (a string), but it is an EntityName attribute stored as an integer, and the two spellings a reasonable person would try both fail:

- `startswith(returnedtypecode,'wrk_')` fails with `0x80040203`, expected type Int32.
- `returnedtypecode eq 10635` (the object type code, unquoted) fails with `0x80060888`, incompatible Edm.String and Edm.Int32.
- `returnedtypecode eq '10635'` (quoted) fails with `0x80041102`, entity not found in the metadata cache.

**What works.** `returnedtypecode eq 'wrk_caseresolution'`: the logical name, quoted. Discovered 2026-08-15 while building the story 1 verification pass.

**Guard.** None yet. Recorded as inventory; a guard becomes worthwhile when the kit grows a helper that filters saved queries by table.

## Story 5: a wrong solution name fails mid-chain, after records already exist

**Symptom.** Every mutating call in a multi-record create carries `MSCRM.SolutionUniqueName` (canon 7). Name a solution that does not exist, or use the display name instead of the unique name, and the failure surfaces on the first create, after preflight passed and with the caller none the wiser about which of the two names was wanted. In a chain of creates the blast radius grows with every record that succeeded before the failure.

**What works.** Check first. Solution unique names are case-sensitive, distinct from display names, and listable with `pac solution list`.

**Guard.** `Assert-PckSolutionExists`, a preflight guard (exit code 19). It validates the name shape before using it in a filter, then confirms existence in the connected environment before any create runs. `New-PckKnowledgeSource` refuses on it before creating anything, and pairs it with best-effort rollback for failures the preflight cannot predict.

**Tests.** Unit: pass on existing, exit 19 with the `pac solution list` hint on missing, hostile names refused before any network call. Integration: exercised implicitly by the live end-to-end knowledge source round trip.

## Story 6: the machine-global pac profile, and the floor that crashes

**Symptom, part one.** pac auth profiles are stored per machine, not per project. A different workspace on the same laptop selects or re-points the active profile, and every subsequent pac command in your project quietly runs against the wrong environment. A deployment lands somewhere you did not aim it, and nothing errors. This is the founding war story of canon 4: the environment id is always explicit, and the profile is never trusted.

**Symptom, part two.** The obvious in-band fix, pac org select, crashes on pac CLI 2.10.1. The version that motivated the guard is also the tested floor, so the kit assumes no selection command and verifies alignment instead.

**Verified live 2026-08-16.** The pac help banner prints the version as `Version: 2.10.1+g52c3983`, and pac org who prints `Environment ID:` and `Org URL:` lines; both parsers are built against those observed shapes. The verification machine itself was a live specimen: its active profile pointed at a different org than the environment the session was working against.

**Guards.** Two, plus a rule. `Assert-PckPacVersion` (exit 13) refuses a missing, unreadable, or below-floor pac. `Assert-PckProfileAligned` (exit 16) runs pac org who and refuses unless the Environment ID line matches the pinned environment id, or the Org URL host matches the pinned org URL; a target id appearing anywhere else in the output does not count. The rule: in CI mode the profile question is removed entirely, because the pipeline creates a temporary profile from the SPN variables and deletes it on exit, success or failure.

**Tests.** Unit: floor pass and refusal, unreadable banner refusal, alignment by id, alignment by org URL, drift refusal naming both environments, no-profile refusal, and the adversarial case where the target id appears on the wrong line. The pac runner itself is tested against a real failing executable, including the sensitive-arguments case: a command carrying a client secret fails without the secret, the arguments, or the echoed output appearing in the error.

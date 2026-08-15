# War stories

The `pac` and Dataverse Web API gotchas this kit's guards encode. Each entry exists because the failure was hit in a real project, reproduced, and worked around; the guard converts that afternoon into an error message.

The guard-authoring contract (CLAUDE.md canon 6): every guard ships as one file under `Private/Guards/`, one Pester test, and one entry here. No entry, no guard. Entries are numbered and stable; guards reference them by number.

Some entries describe undocumented platform behavior, discovered by inspecting what the maker portal writes. Those shapes can change in any release. If a guard's integration test starts failing in the direction of "the broken thing now works," this file is where the re-verification gets recorded.

---

## Story 1: savedquery fetchxml cannot be updated through the Web API

**Symptom.** Updating a saved query's `fetchxml` column returns `0x80040216` on every route: record PATCH and single-property PUT alike. `layoutxml` on the very same record updates fine. Whatever message the maker portal sends when you edit find columns, the Web API `savedquery` update path is not it.

**Reproduced.** Two separate orgs: one production-grade Dynamics 365 CE org, one freshly provisioned vanilla environment.

**Why it matters.** Dataverse search indexes the columns configured as find columns on a table's Quick Find view, and a fresh custom table's Quick Find view carries exactly one, the primary name. Every other column is invisible to search, and therefore to a Copilot Studio agent grounding on the table, until the view's `fetchxml` changes. This is the difference between "source attached" and "agent grounded."

**What works.**
- Solution surgery: export the solution, edit the savedquery block in `customizations.xml`, re-zip, import. Automates cleanly.
- The maker portal: Tables, your table, Views, open the Quick Find view, Edit find table columns, Save and publish.

**Guard.** `Assert-PckSavedQueryFetchXmlRoute`, a request-construction guard in the Web API funnel. It refuses the call before any network traffic (exit code 20) and names both working alternatives. There is no translated call: attempting the documented-to-fail route on the caller's behalf would just spend their API quota on a known outcome.

**Tests.** Unit: the guard refuses record PATCH and single-property PUT carrying `fetchxml`, allows `layoutxml` on the same record, and ignores unrelated entities. Integration (tagged, live environment): proves the raw untranslated PATCH still fails with `0x80040216`, writing the existing value back so even an unexpected success would alter nothing. If that test ever reports the PATCH succeeding, the platform changed and this story needs re-verification.

## Story 2: the newer agent experience displays knowledge sources it never queries

**Symptom.** A Dataverse knowledge component created via the Web API against an agent built in the newer Copilot Studio experience (template `cliagent-1.0.0`) appears in the agent's Knowledge panel, exactly as if it were wired correctly. The runtime never queries it. The agent answers from general model knowledge and states it has no documents. No error surfaces anywhere: not at create time, not in the panel, not at runtime.

**Why.** The Knowledge panel reads the same `botcomponent` table regardless of harness, but Dataverse knowledge is a standard-harness feature. The newer experience does not offer Dataverse in its Add knowledge dialog, and its runtime does not consume `componenttype` 16 components.

**Detection.** `GET /api/data/v9.2/bots?$select=name,schemaname,template`. A `template` of `default-*` is the standard harness; `cliagent-*` is the newer experience.

**What works.** Build standard-harness agents: turn the New experience toggle off on the Copilot Studio homepage, or pick Other ways to build.

**Guard.** `Assert-PckAgentHarness`, a preflight guard (exit code 14). Standard passes; the newer experience is refused with the failure mode spelled out; unrecognized templates are refused too, because the failure this guard prevents is silent and unrecognized is unsafe. `Get-PckAgentInfo` exposes the same classification as data.

**Tests.** Unit: classification of `default-*`, `cliagent-*`, and unknown templates; refusal messages and exit codes. Integration (tagged): classifies every agent in the live environment.

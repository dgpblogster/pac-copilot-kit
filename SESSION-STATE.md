# Session State — Recovery Brief

> **What this file is:** a self-contained brief that lets a fresh AI pair session pick up exactly where we left off, without the prior chat history. Read this **after** [CLAUDE.md](CLAUDE.md) and [docs/pac-copilot-kit-design.md](docs/pac-copilot-kit-design.md); together those three files are the full context.
>
> **Governed by** the session protocol in CLAUDE.md. Not a changelog — asset changes live in [CHANGELOG.md](CHANGELOG.md), and design decision rationale lives in the design doc's decision log.

**Last updated:** 2026-08-14, second revision (design reconciled against the two source articles; scaffolding paused pending sign-off on §12.2, §12.4 through §12.10).

---

## 1. What this project is (one paragraph, in case CLAUDE.md wasn't read)

`pac-copilot-kit` is a paved-road toolkit around Power Platform CLI + Dataverse Web API for the Copilot Studio agent lifecycle. Two components: `PacCopilotKit` PowerShell module (the engine, source of truth) and `pac-copilot-kit-mcp` local stdio MCP server (thin shim that shells to the module). Cross-client: Claude Code, GitHub Copilot in VS Code, ChatGPT Codex CLI, and CI (Power Platform Build Tools + GitHub Actions). Public, MIT-licensed, `https://github.com/dgpblogster/pac-copilot-kit` when the repo lands. Owner: Mariano Gomez Bent.

## 2. How this project came to be (context the AI won't have from files)

The owner ran a grounded Copilot Studio support agent POC (private, not part of this repo) and is publishing a blog series about it. The POC surfaced a set of `pac` and Dataverse Web API sharp edges: profile drift, `pac org select` crashing on 2.10.1, the `MSCRM.SolutionUniqueName` header being required on API-created components, savedquery `fetchxml` PATCH failing with `0x80040216`, metadata entities rejecting PATCH, the standard vs newer harness split causing silent non-grounding, and the grounding preconditions around Dataverse search. This kit converts those war stories into a reusable engine.

The owner considered three tooling wedges: **ALM (this)**, a curation pipeline, and an eval harness. ALM won because (a) it is the sharpest pain in the POC, (b) it doubles as the executable rebuild kit for blog articles #3, #5, and #11, (c) vendored third-party Copilot Studio skills already cover the authoring layer but are trust-but-verify, so this kit sits *underneath* them. This paragraph is the rationale; design doc §1 has the full case.

**Private working areas are deliberately not pathed in this file** (canon 13: this file ships publicly). A fresh session working on the owner's machine will find them in local memory or can ask.

## 3. Conversation status (what's settled, what's still open)

### Settled and captured elsewhere (do not re-litigate)

Every one of these is a canon in CLAUDE.md and/or a signed-off decision in the design doc's decision log. Listed here as an at-a-glance index for the resuming session, not as the record of truth.

- **Positioning:** transport / environment discipline layer, not a `pac` replacement, not authoring, not eval. (CLAUDE canon 1; design §2, §13.)
- **Shape:** PS module + thin stdio MCP shim, one engine. (CLAUDE canon 2; design §4.)
- **Naming:** repo `pac-copilot-kit`, module `PacCopilotKit`, npm `pac-copilot-kit-mcp`, cmdlet prefix `Pck`, env prefix `PCK_`. (Design §3.)
- **MCP transport:** stdio only in v0.1, launched via `npx -y pac-copilot-kit-mcp` in every client config. HTTP/SSE deferred. (CLAUDE canon 10; design §8.1.)
- **Guard funnel:** two tiers — preflight in `Private/Assert-*.ps1`, wrap-and-translate in single `Invoke-PckDataverseRequest`. New guard = file + Pester test + war-stories doc line. (CLAUDE canons 5, 6, 9; design §6.)
- **MCP verb set (locked, six):** `plan-deployment`, `run-pipeline`, `backup-solution`, `pull-agent`, `wait-for-search`, `explain-failure`. (CLAUDE canon 11; design §8.3.)
- **v0.1 scope:** `Invoke-PckCopilotPipeline` + `Export-PckSolutionBackup` + war-stories guards + MCP shim from day one. (Design §12.1.)
- **Solution-aware writes always.** (CLAUDE canon 7; design §5, §6.2.)
- **No interactive prompts in the engine. Two auth modes (dev / CI) share one call site.** (CLAUDE canon 3; design §5.)
- **Folder rename and `git init`: both done** (2026-08-15). Canon 12 paired them; the rename ran ahead and `git init` followed on 2026-08-15 with `LICENSE`, `README.md`, and `.gitignore` in the first commit on `main`. Canon 12 is superseded. **No GitHub remote yet**, so pushing to `dgpblogster/pac-copilot-kit` is still an open action and needs the owner to create the repo.
- **Public / MIT / no POC-specific details in shipped code, samples, or docs.** (CLAUDE canon 13.)

### Reframed on 2026-08-14 (second revision)

The design was reconciled against the two private source articles, the Dataverse knowledge article and the agent ALM article (see §6). That pass changed the shape of the project, so read design doc §0 before anything else.

- **The kit now has two pillars.** A, capability: create Dataverse knowledge sources, which `pac` cannot do at all. B, paved road: make the published ALM prescription executable. A is why anyone installs it, B is why they keep it.
- **The claim to make is "prescribed but not automatable", never "no ALM story."** Microsoft's guidance exists and is sound; the road does not. The weaker claim loses an argument the moment someone links the golden-rules page.
- **Three statements in the first design pass were wrong** and are corrected: the `savedquery` guard (no Web API route works at all), the botcomponent attachment relationship (`parentbotid`, not the `bot_botcomponent` N:N), and the Web API token source (never specified, and the obvious answer conflicts with what the POC proved).

### Closed on 2026-08-15 (the two structural ones)

- **§12.8, Web API token source: settled.** The funnel acquires its own token and never depends on `pac` state. This was settled by verification, not preference: no `pac` command emits a bearer token (the whole `pac auth` surface is `clear`, `create`, `delete`, `list`, `name`, `select`, `update`, `who`), and the VS Code extension's Auth Panel is a GUI over the same machine-global profiles, so it neither avoids the drift nor supplies a token. **One code path for every developer, no editor-conditional behavior.** CI uses SPN client credentials against the Entra token endpoint with scope `{org}/.default`, which needs no extra dependency at all. Dev resolves in order: `PCK_ACCESS_TOKEN`, then `az account get-access-token`, then `Get-AzAccessToken` from `Az.Accounts`, then a hard error naming all three. `az` is an accepted path, never a prerequisite.
- **§12.9, v0.1 scope: grows to include pillar A.** See design §12.9 for the cmdlet list.

### All §12 items are closed as of 2026-08-15

Nothing blocks code. The last batch: §7 cmdlet names as proposed with the `Pck` prefix kept after a `Pac`-prefix challenge, PowerShell 7.4+, Node 20 LTS, manual Gallery publish for v0.1, war-stories owned by this repo, and `add-knowledge-source` added as the seventh MCP verb (canon 11 amended). `Test-PckCopilotAgent` stays deferred to v0.2; its candidate shape there is a deployment smoke test (one grounded question with citations), not eval CSVs.

## 4. Next action

**Done 2026-08-15:** `git init` on `main`, first commit, with `LICENSE` (MIT), `README.md`, and `.gitignore`. Repo-local git identity set to the owner's GitHub noreply address so the real address stays out of public history. Repo created at `https://github.com/dgpblogster/pac-copilot-kit` and pushed; `main` tracks `origin/main`. **Visibility: private for now, deliberately.** The design doc condenses the findings of two still-unpublished blog articles (the Dataverse knowledge article and the agent ALM article), and a public repo would front-run their debut. **Flip to public when those two articles publish**; that is the trigger, not a date. Canon 13 discipline is unchanged meanwhile: commit as if public, leak-check before every push, so the flip needs no cleanup.

**Done 2026-08-15, walking skeleton:** `Connect-PckPowerPlatform`, `Invoke-PckDataverseRequest`, `Get-PckAgentInfo`, `Assert-PckAgentHarness`, `Assert-PckSavedQueryFetchXmlRoute`, token chain per §12.8, `docs/war-stories.md` stories 1 and 2. 31 unit tests passing; 3 integration tests tagged `Integration` await a live run.

1. **Run the integration tests against the sandbox.** `Invoke-Pester -Path tests -Tag Integration` with `PCK_DEFAULT_ENVIRONMENT_ID` set in the shell and an `az login` session. First live proof of the auth chain, discovery, WhoAmI, harness classification, and the story 1 refusal contract. Nothing mutates except the story 1 PATCH, which writes an existing value back and is documented to fail.
2. **Verify the bot `authenticationmode` storage shape** against the live environment (canon 16), then add the auth-mode field to `Get-PckAgentInfo` and write `Assert-PckAgentAuthMode`. Deliberately omitted from the skeleton because the shape is unverified.
3. **`New-PckKnowledgeSource`.** The headline pillar A cmdlet. The funnel, guards, and solution-header enforcement it needs all exist now.
4. **`Invoke-PckCopilotPipeline`**, then the MCP shim (`src/pac-copilot-kit-mcp/`), then `ci/` and `samples/` per design §11.

Integration testing needs a real environment. Its id goes in the owner's shell via `PCK_DEFAULT_ENVIRONMENT_ID` and is never checked in (canon 13).
4. Write the first Pester test for a war-story guard: the `savedquery` PATCH `0x80040216` case. Locks the guard-authoring contract (canon 6) with a real example before any second guard exists.

Do not scaffold code before step 1 is answered. The owner's pattern is ask-then-implement for structural decisions; "OK on scope" earlier in the session was not blanket approval to start writing PowerShell.

## 5. Owner style (durable, applies to every response)

- Impersonal voice. No emojis.
- **No em dashes** in shipped docs, samples, or code comments. Ordinary punctuation instead.
- Brief responses; ask-first for scope decisions; don't over-explain what was done after doing it.
- Skills / MCP servers / third-party AI tooling are trust-but-verify (see CLAUDE canon 10 in the source POC). Verify before building on their output.
- Owner has been running a large POC in parallel; they know Copilot Studio, `pac`, and Dataverse Web API deeply. Do not over-teach fundamentals.

## 6. Environment notes

- **Local test environment for guards + integration tests:** the sandbox shared with the source POC. Its name and environment id are deliberately **not recorded in this repo** (canon 13: this file ships publicly). Both live in the owner's shell only, the id via `PCK_DEFAULT_ENVIRONMENT_ID`. If a fresh session needs them, ask the owner.
- **`pac` CLI floor:** 2.10.1 or later. Note the `pac org select` crash on 2.10.1 that motivated canon 4.
- **Reference sources, private, not part of this repo and not pathed here** (canon 13): the source POC workspace, and the blog drafts. Two of those drafts are the record of what the POC actually proved and outrank this repo's design doc on any claim about platform behavior (canon 16): the Dataverse knowledge article and the agent ALM article. On the owner's machine both are in local memory; otherwise ask.

## 7. Recovery scenario (why this file exists in this shape)

The folder was renamed ahead of `git init` rather than with it. VS Code keys Copilot Chat history to the workspace folder URI, so the renamed folder gives the AI a fresh chat with no memory of the design conversation. That already happened once, before the repo existed to hold history. The three memory files (CLAUDE, this SESSION-STATE, and the design doc) are what makes recovery possible, and this revision exists because the first pass of the design doc was recoverable but partly wrong: it recorded the conversation faithfully and the POC lossily.

Two lessons worth keeping. First, if a fresh session reads the three files in order and cannot answer "what would we scaffold next", this file failed at its job; update it before starting scaffold work. Second, the design doc is not the primary source for anything the POC proved. The two private articles are (canon 16), and the design doc should be reconciled against them whenever it makes a claim about platform behavior.

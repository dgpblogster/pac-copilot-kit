/**
 * The exit-code contract, mirrored from the module's PckConstants.ps1. Codes
 * 10..19 are preflight refusals (canon 9): the environment or inputs are
 * misconfigured, the message names the specific problem, and retrying the
 * same call unchanged is pointless. 20 is a known-broken platform route with
 * working alternatives named in the message. 1 is an ordinary operational
 * failure.
 */
export interface ExitCodeInfo {
  name: string;
  meaning: string;
  guidance: string;
}

export const EXIT_CODES: Record<number, ExitCodeInfo> = {
  1: {
    name: "General",
    meaning: "An operational failure: the call was legitimate but did not succeed.",
    guidance: "Read the error text; this is not a guardrail refusal. Diagnose the named problem before retrying.",
  },
  10: {
    name: "EnvironmentNotSpecified",
    meaning: "No environment id was given and PCK_DEFAULT_ENVIRONMENT_ID is not set. The kit never infers the environment from the pac profile (canon 4).",
    guidance: "Provide environmentId in the tool arguments, or set PCK_DEFAULT_ENVIRONMENT_ID for the server process.",
  },
  11: {
    name: "TokenUnavailable",
    meaning: "No Web API token source is available, or the PCK_SPN_* set is incomplete.",
    guidance: "Provide one of: a signed-in Azure CLI (az login), PCK_ACCESS_TOKEN, the Az.Accounts module, or all three of PCK_SPN_TENANT, PCK_SPN_APP_ID, PCK_SPN_SECRET.",
  },
  12: {
    name: "EnvironmentInvalid",
    meaning: "The environment was not found in global discovery for this identity, or the environment URL is not https.",
    guidance: "Check the environment id, and check that the signed-in identity has access to that environment.",
  },
  13: {
    name: "PacUnavailable",
    meaning: "The pac CLI is missing, its version banner is unreadable, or it is below the tested floor (2.10.1).",
    guidance: "Install or update the pac CLI from https://aka.ms/PowerPlatformCLI.",
  },
  14: {
    name: "HarnessUnsupported",
    meaning: "The agent is not the standard harness. Knowledge components created against the newer experience display in the Knowledge panel but the runtime never queries them; there is no error anywhere (war story 2).",
    guidance: "Do not work around this. Use a standard-harness agent: turn the New experience toggle off in Copilot Studio, or pick Other ways to build.",
  },
  15: {
    name: "NotConnected",
    meaning: "No session context exists; Connect-PckPowerPlatform has not run in this process.",
    guidance: "The server connects automatically when a tool needs it; if this surfaces, check environmentId and the token source.",
  },
  16: {
    name: "ProfileMisaligned",
    meaning: "The active pac auth profile points at a different environment than the pinned one. pac commands would run against the wrong environment; pac profiles are machine-global and drift (war story 6, canon 4).",
    guidance: "Run: pac auth select (to an aligned profile), or pac auth create --environment <the pinned id>. Do not remove the pin to make the error go away.",
  },
  17: {
    name: "WorkspaceRootUnset",
    meaning: "A relative path was supplied and PCK_WORKSPACE_ROOT is not set. Nothing in the kit depends on the current directory.",
    guidance: "Pass absolute paths, or set PCK_WORKSPACE_ROOT.",
  },
  18: {
    name: "AgentAuthModeUnsupported",
    meaning: "The agent's end-user authentication is not Integrated ('Authenticate with Microsoft'). Dataverse knowledge sources ride the end user's identity and are never searched under any other mode (war story 3).",
    guidance: "Change the agent's authentication setting in Copilot Studio to Authenticate with Microsoft, then retry. Sources created anyway would display but never be queried.",
  },
  19: {
    name: "SolutionNotFound",
    meaning: "The named solution does not exist in the connected environment. Solution unique names are case-sensitive and distinct from display names (war story 5).",
    guidance: "Check with: pac solution list. Use the unique name, not the display name.",
  },
  20: {
    name: "KnownBrokenRoute",
    meaning: "The call hit a platform route that is known to fail (for example savedquery fetchxml updates, war story 1). The error message names the working alternatives.",
    guidance: "Switch to one of the named alternatives (solution surgery or the maker portal). Retrying the same route will not help.",
  },
};

export function explain(code: number, message?: string): string {
  const info = EXIT_CODES[code];
  const lines: string[] = [];
  if (info) {
    lines.push(`Exit code ${code} (${info.name}).`);
    lines.push(`What happened: ${info.meaning}`);
    lines.push(`What to do: ${info.guidance}`);
    if (code >= 10 && code <= 19) {
      lines.push("This is a preflight refusal: fix the named condition; do not retry the same call unchanged, and do not bypass the guardrail by calling the platform directly. The failures these guardrails prevent are silent when hit raw.");
    }
  } else {
    lines.push(`Exit code ${code} is not in the kit's registry; treat it as an operational failure.`);
  }
  if (message) {
    lines.push(`Original message: ${message}`);
  }
  return lines.join("\n");
}

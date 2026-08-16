# Shared constants. Named PckConstants so it sorts (and therefore loads) before the
# other Private files that reference these script-scope variables at call time.

# Exit code registry (canon 9): 10..19 preflight (environment misconfigured),
# 20 known-broken-route refusal, 1 generic operational failure.
$script:PckExitCode = @{
    General                  = 1
    EnvironmentNotSpecified  = 10
    TokenUnavailable         = 11   # includes an incomplete PCK_SPN_* set
    EnvironmentInvalid       = 12   # not found in discovery, or a non-https URL
    PacUnavailable           = 13   # pac missing, unreadable, or below the floor
    HarnessUnsupported       = 14
    NotConnected             = 15
    ProfileMisaligned        = 16   # active pac auth profile points elsewhere (canon 4)
    WorkspaceRootUnset       = 17
    AgentAuthModeUnsupported = 18
    SolutionNotFound         = 19
    KnownBrokenRoute         = 20
}

$script:PckApiVersion   = 'v9.2'
$script:PckDiscoveryUrl = 'https://globaldisco.crm.dynamics.com'

# Session state set by Connect-PckPowerPlatform, consumed by Invoke-PckDataverseRequest.
$script:PckContext = $null
$script:PckToken   = $null

# Request-construction guardrails the funnel runs before any network call (design 6.2).
# Each entry is a function under Private/Guardrails that throws to refuse the request.
# Empty since 2026-08-15: the savedquery guardrail moved to the translator tier after
# live verification showed the route succeeds on some system views.
$script:PckRequestConstructionChecks = @()

# Error translators the funnel consults when a request fails (design 6.2).
# Each is a function under Private/Guardrails receiving the normalized request plus
# the Dataverse error code and message; the first to return a non-null string
# supplies the enriched error, thrown with the KnownBrokenRoute exit code.
$script:PckErrorTranslators = @(
    'Convert-PckSavedQueryFetchXmlError'
)

# Shared constants. Named PckConstants so it sorts (and therefore loads) before the
# other Private files that reference these script-scope variables at call time.

# Exit code registry (canon 9): 10..19 preflight (environment misconfigured),
# 20 known-broken-route refusal, 1 generic operational failure.
$script:PckExitCode = @{
    General                 = 1
    EnvironmentNotSpecified = 10
    TokenUnavailable        = 11
    EnvironmentNotFound     = 12
    SpnIncomplete           = 13
    HarnessUnsupported      = 14
    NotConnected            = 15
    EnvironmentUrlInvalid   = 16
    WorkspaceRootUnset      = 17
    AgentAuthModeUnsupported = 18
    SolutionNotFound        = 19
    KnownBrokenRoute        = 20
}

$script:PckApiVersion   = 'v9.2'
$script:PckDiscoveryUrl = 'https://globaldisco.crm.dynamics.com'

# Session state set by Connect-PckPowerPlatform, consumed by Invoke-PckDataverseRequest.
$script:PckContext = $null
$script:PckToken   = $null

# Request-construction guards the funnel runs before any network call (design 6.2).
# Each entry is a function under Private/Guards that throws to refuse the request.
# Empty since 2026-08-15: the savedquery guard moved to the translator tier after
# live verification showed the route succeeds on some system views.
$script:PckRequestConstructionGuards = @()

# Response translators the funnel consults when a request fails (design 6.2).
# Each is a function under Private/Guards receiving the normalized request plus
# the Dataverse error code and message; the first to return a non-null string
# supplies the enriched error, thrown with the KnownBrokenRoute exit code.
$script:PckResponseTranslators = @(
    'Convert-PckSavedQueryFetchXmlError'
)

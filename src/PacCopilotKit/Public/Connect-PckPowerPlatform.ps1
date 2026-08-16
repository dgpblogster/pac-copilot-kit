function Connect-PckPowerPlatform {
    <#
    .SYNOPSIS
    Resolves auth and environment, verifies reachability, and caches the session
    context every other cmdlet uses.

    .DESCRIPTION
    Environment id resolution: -EnvironmentId, then PCK_DEFAULT_ENVIRONMENT_ID,
    then a hard error (canon 4). The pac auth profile is never consulted.

    Auth mode is implicit: a complete PCK_SPN_* set means CI, anything else means
    dev (design 5.2). Token acquisition follows design 12.8 and never depends on
    pac state.

    The org URL is resolved from the environment id through the global discovery
    service. -EnvironmentUrl skips discovery for callers whose token source cannot
    serve the discovery resource, such as an org-scoped PCK_ACCESS_TOKEN; the
    environment id is still required and recorded.

    Verification is a WhoAmI call through the funnel; a context that cannot answer
    WhoAmI is discarded rather than cached.

    .EXAMPLE
    Connect-PckPowerPlatform -EnvironmentId 00000000-0000-0000-0000-000000000000

    .EXAMPLE
    $env:PCK_DEFAULT_ENVIRONMENT_ID = '00000000-0000-0000-0000-000000000000'
    Connect-PckPowerPlatform -Json
    #>
    [CmdletBinding()]
    param(
        [string] $EnvironmentId,

        [string] $EnvironmentUrl,

        [switch] $Json
    )

    $EnvironmentId = Resolve-PckEnvironmentId -EnvironmentId $EnvironmentId

    $spnComplete = -not [string]::IsNullOrWhiteSpace($env:PCK_SPN_TENANT) -and
                   -not [string]::IsNullOrWhiteSpace($env:PCK_SPN_APP_ID) -and
                   -not [string]::IsNullOrWhiteSpace($env:PCK_SPN_SECRET)
    $authMode = $spnComplete ? 'CI' : 'Dev'

    if ([string]::IsNullOrWhiteSpace($EnvironmentUrl)) {
        $EnvironmentUrl = Resolve-PckOrgUrl -EnvironmentId $EnvironmentId
    }
    $EnvironmentUrl = $EnvironmentUrl.TrimEnd('/')
    if ($EnvironmentUrl -notmatch '(?i)^https://') {
        throw [PckPreflightError]::new(
            "Environment URL '$EnvironmentUrl' must be https. A bearer token is attached to every call, and it does not travel over plain http.",
            $script:PckExitCode.EnvironmentInvalid)
    }

    $script:PckToken = $null
    $script:PckContext = [pscustomobject]@{
        EnvironmentId  = $EnvironmentId
        EnvironmentUrl = $EnvironmentUrl
        AuthMode       = $authMode
        ConnectedAt    = Get-Date
        UserId         = $null
        OrganizationId = $null
    }

    try {
        $who = Invoke-PckDataverseRequest -Method Get -Path 'WhoAmI'
        $script:PckContext.UserId = $who.UserId
        $script:PckContext.OrganizationId = $who.OrganizationId
    }
    catch {
        $script:PckContext = $null
        $script:PckToken = $null
        throw
    }

    Write-Verbose "Connected to $EnvironmentUrl (environment $EnvironmentId, $authMode mode)."

    if ($Json) { $script:PckContext | ConvertTo-Json -Depth 4 } else { $script:PckContext }
}

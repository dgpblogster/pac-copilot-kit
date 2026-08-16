function Assert-PckAgentAuthMode {
    <#
    .SYNOPSIS
    Refuses agents whose end-user authentication mode cannot ground on
    Dataverse knowledge.

    .DESCRIPTION
    Dataverse knowledge sources ride the end user's identity: only Integrated
    authentication ("Authenticate with Microsoft", authenticationmode 2) ever
    searches them. Every other mode attaches sources that are never queried,
    and the documentation is explicit about it. Storage shape verified live on
    2026-08-15 (design 6.1; war story 3 in docs/war-stories.md).
    #>
    [CmdletBinding()]
    param(
        # An authenticationmode value, or any object with an AuthenticationMode
        # (or authenticationmode) property, such as a Get-PckAgentInfo result.
        [Parameter(Mandatory)]
        [object] $Agent
    )

    $mode = if ($Agent -is [int] -or $Agent -is [string]) {
        $Agent
    }
    else {
        $prop = $Agent.PSObject.Properties['AuthenticationMode'] ?? $Agent.PSObject.Properties['authenticationmode']
        if (-not $prop) {
            throw [PckError]::new(
                'Assert-PckAgentAuthMode needs an authenticationmode value or an object with an AuthenticationMode property.',
                $script:PckExitCode.General)
        }
        $prop.Value
    }

    $parsed = 0
    if (-not [int]::TryParse([string]$mode, [ref] $parsed)) {
        throw [PckPreflightError]::new(
            "Agent authentication mode '$mode' is not a recognized value. Refusing rather than risking silently unqueried knowledge.",
            $script:PckExitCode.AgentAuthModeUnsupported)
    }

    if ($parsed -eq 2) { return }

    $name = Get-PckAuthModeName -Value $parsed
    throw [PckPreflightError]::new(
        "Agent authentication mode check failed: mode is '$name' ($parsed), and Dataverse knowledge sources are only searched under Integrated authentication ('Authenticate with Microsoft', mode 2). Sources attached to this agent would display but never be queried. Change the agent's authentication setting in Copilot Studio, then re-run.",
        $script:PckExitCode.AgentAuthModeUnsupported)
}

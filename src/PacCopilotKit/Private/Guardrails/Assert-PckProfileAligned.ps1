function Assert-PckProfileAligned {
    <#
    .SYNOPSIS
    Refuses to run pac commands when the active pac auth profile points at a
    different environment than the one the caller pinned.

    .DESCRIPTION
    pac auth profiles are machine-global, and another workspace on the same
    machine can silently re-point the active one; the founding war story of
    canon 4 (war story 6). Every pac command that talks to an org runs against
    the active profile, so alignment is verified against pac org who before
    any of them. Output shape verified live on 2026-08-16: pac org who prints
    'Environment ID:' and 'Org URL:' lines.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $EnvironmentId,

        [string] $EnvironmentUrl
    )

    $output = ''
    try {
        $output = (Invoke-PckPacCommand -Arguments @('org', 'who')) -join "`n"
    }
    catch {
        throw [PckPreflightError]::new(
            "No active pac auth profile answered 'pac org who'. Create one aimed at the pinned environment: pac auth create --environment $EnvironmentId",
            $script:PckExitCode.ProfileMisaligned)
    }

    if ($output -match "(?im)^\s*Environment ID:\s*$([regex]::Escape($EnvironmentId))\s*$") { return }

    if (-not [string]::IsNullOrWhiteSpace($EnvironmentUrl)) {
        $targetHost = ([uri]$EnvironmentUrl).Host
        if ($output -match "(?im)^\s*Org URL:\s*https://$([regex]::Escape($targetHost))/?\s*$") { return }
    }

    $current = if ($output -match '(?im)^\s*Environment ID:\s*([0-9a-fA-F-]{36})') { $Matches[1] } else { 'unreadable' }
    throw [PckPreflightError]::new(
        "The active pac auth profile points at environment $current, not $EnvironmentId. pac commands would run against the wrong environment (canon 4). Fix: pac auth select, or pac auth create --environment $EnvironmentId",
        $script:PckExitCode.ProfileMisaligned)
}

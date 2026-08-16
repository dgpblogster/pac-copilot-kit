function Sync-PckCopilotAgent {
    <#
    .SYNOPSIS
    Pulls remote agent changes from Copilot Studio into a local workspace,
    with the environment pinned and the pac profile verified first.

    .DESCRIPTION
    A thin, guarded wrapper over pac copilot pull (argument shape verified live
    on 2026-08-16: the only parameter is --project-dir). The value added is the
    discipline in front of it: explicit environment id (canon 4), pac floor
    check (war story 6), and profile alignment, so the pull cannot silently
    read from the wrong environment. The workspace must already be connected
    to an agent, which pac copilot init --environment or pac copilot clone
    sets up.

    .EXAMPLE
    Sync-PckCopilotAgent -SourcePath C:\src\agent
    #>
    [CmdletBinding()]
    param(
        # The pac copilot workspace. Absolute, or relative to PCK_WORKSPACE_ROOT.
        [Parameter(Mandatory)]
        [string] $SourcePath,

        [string] $EnvironmentId,

        [switch] $Json
    )

    $src = Resolve-PckOutputPath -Path $SourcePath
    if (-not (Test-Path -LiteralPath $src -PathType Container)) {
        throw [PckError]::new("Source path '$src' does not exist.", $script:PckExitCode.General)
    }

    $resolvedEnv = Resolve-PckEnvironmentId -EnvironmentId $EnvironmentId
    if (-not $script:PckContext -or $script:PckContext.EnvironmentId -ne $resolvedEnv) {
        Connect-PckPowerPlatform -EnvironmentId $resolvedEnv | Out-Null
    }

    Assert-PckPacVersion
    Assert-PckProfileAligned -EnvironmentId $resolvedEnv -EnvironmentUrl $script:PckContext.EnvironmentUrl

    $output = Invoke-PckPacCommand -WorkingDirectory $src -Arguments @('copilot', 'pull', '--project-dir', $src)

    $result = [pscustomobject]@{
        SourcePath    = $src
        EnvironmentId = $resolvedEnv
        Succeeded     = $true
        PacOutput     = @($output | Select-Object -Last 20)
    }
    if ($Json) { ConvertTo-Json -InputObject $result -Depth 4 } else { $result }
}

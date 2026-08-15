function Export-PckSolutionBackup {
    <#
    .SYNOPSIS
    Exports a solution to a timestamp-suffixed zip on disk in one call.

    .DESCRIPTION
    POST /ExportSolution, decode the base64 payload, write the file. The result
    is a backup, explicitly not a source of truth (design rule 5.9): the
    repository defines the agent, and an export is what you reach for when
    something went wrong, not what you deploy from.

    Path discipline per design rule 5.7: -Path is used as given when absolute,
    resolved against PCK_WORKSPACE_ROOT when relative, and refused when relative
    with no root set. Nothing depends on the current directory.

    .EXAMPLE
    Export-PckSolutionBackup -SolutionName WorkbenchSupportAssistant -Path C:\backups

    .EXAMPLE
    Export-PckSolutionBackup -SolutionName WorkbenchSupportAssistant -Path backups -Managed -Json
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $SolutionName,

        [Parameter(Mandatory)]
        [string] $Path,

        [switch] $Managed,

        [switch] $Json
    )

    # The solution unique name becomes part of a filename; refuse anything that
    # could not be a solution unique name before it can traverse a path.
    if ($SolutionName -notmatch '^[A-Za-z0-9_]+$') {
        throw [PckError]::new(
            "Solution name '$SolutionName' is not a valid solution unique name (letters, digits, underscores).",
            $script:PckExitCode.General)
    }

    $directory = Resolve-PckOutputPath -Path $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $resp = Invoke-PckDataverseRequest -Method Post -Path 'ExportSolution' -Body @{
        SolutionName = $SolutionName
        Managed      = [bool]$Managed
    } -NoSolution

    if (-not ($resp -and $resp.PSObject.Properties['ExportSolutionFile']) -or
        [string]::IsNullOrWhiteSpace([string]$resp.ExportSolutionFile)) {
        throw [PckError]::new(
            "ExportSolution returned no file payload for '$SolutionName'.",
            $script:PckExitCode.General)
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $suffix = $Managed ? '-managed' : ''
    $file = Join-Path $directory "$SolutionName-$stamp$suffix.zip"
    [System.IO.File]::WriteAllBytes($file, [Convert]::FromBase64String($resp.ExportSolutionFile))

    $result = [pscustomobject]@{
        SolutionName = $SolutionName
        Managed      = [bool]$Managed
        Path         = $file
        Bytes        = (Get-Item -LiteralPath $file).Length
        Timestamp    = $stamp
    }
    if ($Json) { $result | ConvertTo-Json -Depth 4 } else { $result }
}

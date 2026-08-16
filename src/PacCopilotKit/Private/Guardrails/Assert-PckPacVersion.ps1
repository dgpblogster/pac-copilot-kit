function Assert-PckPacVersion {
    <#
    .SYNOPSIS
    Refuses to run when the pac CLI is missing, unreadable, or below the
    tested floor.

    .DESCRIPTION
    The floor is 2.10.1, the version the source project tested against (and
    the version whose pac org select crash motivated canon 4). Banner shape
    verified live on 2026-08-16: pac help prints 'Version: 2.10.1+g52c3983'
    on its second line (war story 6).
    #>
    [CmdletBinding()]
    param(
        [version] $Floor = [version]'2.10.1'
    )

    $banner = (Invoke-PckPacCommand -Arguments @('help') | Select-Object -First 5) -join "`n"

    if ($banner -notmatch 'Version:\s*v?(\d+\.\d+\.\d+)') {
        $head = $banner.Substring(0, [Math]::Min(120, $banner.Length))
        throw [PckPreflightError]::new(
            "Could not read the pac CLI version from its banner. Banner began: $head",
            $script:PckExitCode.PacUnavailable)
    }

    $found = [version]$Matches[1]
    if ($found -lt $Floor) {
        throw [PckPreflightError]::new(
            "pac CLI $found is below the tested floor $Floor. Update it (pac install latest, or reinstall from https://aka.ms/PowerPlatformCLI) and retry.",
            $script:PckExitCode.PacUnavailable)
    }
}

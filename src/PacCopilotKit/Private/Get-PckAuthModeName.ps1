function Get-PckAuthModeName {
    <#
    .SYNOPSIS
    Maps a bot.authenticationmode picklist value to its label. Values verified
    live against the option set metadata on 2026-08-15 (war story 3).
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value -or [string]$Value -eq '') { return 'Unknown' }
    switch ([int]$Value) {
        0 { return 'Unspecified' }
        1 { return 'None' }
        2 { return 'Integrated' }
        3 { return 'Custom Entra ID' }
        4 { return 'Generic OAuth2' }
        default { return "Unknown ($Value)" }
    }
}

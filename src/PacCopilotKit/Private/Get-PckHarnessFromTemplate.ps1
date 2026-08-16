function Get-PckHarnessFromTemplate {
    <#
    .SYNOPSIS
    Classifies a bot template value into a harness. default-* is the standard
    harness; cliagent-* is the newer agent experience; anything else is Unknown
    and treated as unsafe by the harness guardrail.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Template
    )

    if ($Template -like 'default-*') { return 'Standard' }
    if ($Template -like 'cliagent-*') { return 'NewExperience' }
    return 'Unknown'
}

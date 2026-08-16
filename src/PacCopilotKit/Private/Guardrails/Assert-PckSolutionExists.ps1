function Assert-PckSolutionExists {
    <#
    .SYNOPSIS
    Refuses when the named solution does not exist in the connected environment.

    .DESCRIPTION
    Every mutating call in the kit stamps MSCRM.SolutionUniqueName (canon 7), so
    a wrong solution name would otherwise surface mid-chain, after some records
    already exist. Preflighting existence turns that into a clear refusal before
    anything is created (design 6.1; war story 5 in docs/war-stories.md).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $SolutionName
    )

    # The name lands in an OData filter; refuse anything that could not be a
    # solution unique name before it can rewrite the query.
    if ($SolutionName -notmatch '^[A-Za-z0-9_]+$') {
        throw [PckPreflightError]::new(
            "Solution name '$SolutionName' is not a valid solution unique name (letters, digits, underscores).",
            $script:PckExitCode.SolutionNotFound)
    }

    $match = @((Invoke-PckDataverseRequest -Method Get `
        -Path "solutions?`$select=solutionid,uniquename&`$filter=uniquename eq '$SolutionName'").value)

    if ($match.Count -eq 0) {
        throw [PckPreflightError]::new(
            "Solution '$SolutionName' does not exist in the connected environment. Solution unique names are case-sensitive and distinct from display names; check with: pac solution list.",
            $script:PckExitCode.SolutionNotFound)
    }
}

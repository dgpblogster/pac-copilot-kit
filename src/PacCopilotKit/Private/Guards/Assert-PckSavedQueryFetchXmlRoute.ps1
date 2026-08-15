function Assert-PckSavedQueryFetchXmlRoute {
    <#
    .SYNOPSIS
    Refuses any Web API update of savedquery fetchxml. There is no working route.

    .DESCRIPTION
    Record PATCH and single-property PUT both fail with 0x80040216, reproduced in
    two separate orgs, while layoutxml on the very same record updates fine.
    Whatever message the maker portal sends, the savedquery update path is not it.
    This guard refuses at request construction rather than attempting a call that
    is documented to fail (design 6.2; war story 1 in docs/war-stories.md).
    #>
    [CmdletBinding()]
    param(
        [string] $Method,
        [string] $Path,
        [object] $Body
    )

    if ($Method -notin @('Patch', 'Put')) { return }
    if ($Path -notmatch '(?i)^savedqueries\(') { return }

    $touchesFetchXml = $Path -match '(?i)\)/fetchxml(\?|$)'
    if (-not $touchesFetchXml -and $null -ne $Body -and $Body -isnot [string]) {
        $props = if ($Body -is [System.Collections.IDictionary]) { @($Body.Keys) }
                 else { @($Body.PSObject.Properties.Name) }
        $touchesFetchXml = $props -contains 'fetchxml'
    }
    if (-not $touchesFetchXml) { return }

    throw [PckError]::new(
        'Refused: updating savedquery fetchxml through the Web API fails with 0x80040216 on every route (record PATCH and single-property PUT alike). Working alternatives: solution surgery (export the solution, edit the savedquery block in customizations.xml, import), or the maker portal (Tables, your table, Views, Quick Find, Edit find table columns, Save and publish). See docs/war-stories.md, story 1.',
        $script:PckExitCode.KnownBrokenRoute)
}

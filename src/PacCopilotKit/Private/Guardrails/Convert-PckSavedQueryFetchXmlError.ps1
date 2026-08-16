function Convert-PckSavedQueryFetchXmlError {
    <#
    .SYNOPSIS
    Translates 0x80040216 on a savedquery fetchxml update into the war story.

    .DESCRIPTION
    Error translator (design 6.2). Live verification on 2026-08-15 narrowed
    war story 1: the failure reproduces broadly (three orgs; system and custom
    tables; standard and elastic) while a minority of views accept the same
    call, and the discriminator is not yet identified. Sync flag, custom versus
    system, and TableType were all tested and ruled out. The route is therefore
    attempted rather than refused, and this translator enriches the known
    failure signature when it occurs. Returns the enriched message, or null
    when the failure is not this story.
    #>
    [CmdletBinding()]
    param(
        [string] $Method,
        [string] $Path,
        [object] $Body,
        [string] $Code,
        [string] $Message
    )

    if ($Code -ne '0x80040216') { return $null }
    if ($Method -notin @('Patch', 'Put')) { return $null }
    if ($Path -notmatch '(?i)^savedqueries\(') { return $null }

    $touchesFetchXml = $Path -match '(?i)\)/fetchxml(\?|$)'
    if (-not $touchesFetchXml -and $null -ne $Body -and $Body -isnot [string]) {
        $props = if ($Body -is [System.Collections.IDictionary]) { @($Body.Keys) }
                 else { @($Body.PSObject.Properties.Name) }
        $touchesFetchXml = $props -contains 'fetchxml'
    }
    if (-not $touchesFetchXml) { return $null }

    return 'Updating this savedquery fetchxml through the Web API failed with 0x80040216, the known signature of war story 1. The failure reproduces on most Quick Find views across orgs while a minority accept the same call; the discriminator is not yet identified, which is why the kit attempts the call rather than refusing. Working alternatives: solution surgery (export the solution, edit the savedquery block in customizations.xml, import), or the maker portal (Tables, your table, Views, Quick Find, Edit find table columns, Save and publish). See docs/war-stories.md, story 1.'
}

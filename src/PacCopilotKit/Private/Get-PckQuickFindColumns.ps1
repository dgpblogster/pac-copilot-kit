function Get-PckQuickFindColumns {
    <#
    .SYNOPSIS
    Reads the find columns from a table's Quick Find view, the columns Dataverse
    search actually indexes (war story 1).

    .DESCRIPTION
    Returns the view id, name, and find-column list, or null when the table has
    no Quick Find view. Uses the returnedtypecode quoted-logical-name filter
    (war story 4). Find columns are the conditions inside the view fetchxml's
    isquickfindfields filter.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9_]*$')]
        [string] $TableLogicalName
    )

    $view = @((Invoke-PckDataverseRequest -Method Get `
        -Path "savedqueries?`$select=savedqueryid,name,fetchxml&`$filter=querytype eq 4 and returnedtypecode eq '$TableLogicalName'").value) |
        Select-Object -First 1
    if (-not $view) { return $null }

    $columns = @()
    try {
        $fetch = [xml]$view.fetchxml
        $columns = @($fetch.SelectNodes("//filter[@isquickfindfields='1']/condition") |
            ForEach-Object { $_.GetAttribute('attribute') } |
            Where-Object { $_ })
    }
    catch {
        Write-Verbose "Quick Find fetchxml for '$TableLogicalName' did not parse: $($_.Exception.Message)"
    }

    return [pscustomobject]@{
        ViewId      = $view.savedqueryid
        ViewName    = $view.name
        FindColumns = $columns
    }
}

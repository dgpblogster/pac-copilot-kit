function New-PckKnowledgeSource {
    <#
    .SYNOPSIS
    Wires a Dataverse knowledge source into a Copilot Studio agent: the one
    thing pac cannot do at all.

    .DESCRIPTION
    Creates the four records that make a Dataverse knowledge source (design
    6.3), every call inside the solution: the dvtablesearch configuration, one
    dvtablesearchentity per table, the componenttype 16 botcomponent whose
    schemaname is built from the agent's read (never guessed) schemaname and
    whose parentbotid lookup attaches it to the agent, and the
    botcomponent_dvtablesearch association.

    Preflight refuses before anything is created: standard harness only (war
    story 2), Integrated end-user auth only (war story 3), solution must exist
    (war story 5), tables must exist, and the search configuration name must be
    unused. A mid-chain failure rolls back every record already created.

    Two things this cmdlet reports rather than solves, honestly: the org-level
    search flag (Enable-PckDataverseSearch) and the find columns on each
    table's Quick Find view, which no Web API route reliably updates (war
    story 1). Grounding is proven only by Wait-PckDataverseSearchReady.

    .EXAMPLE
    New-PckKnowledgeSource -BotName 'Workbench Support Assistant 2.0' `
        -Table wrk_caseresolution -SolutionName WorkbenchSupportAssistant `
        -DisplayName 'Curated Case Resolutions'
    #>
    [CmdletBinding()]
    param(
        [guid] $BotId,

        # Exact display name or schemaname; must match exactly one agent.
        [string] $BotName,

        [Parameter(Mandatory)]
        [string[]] $Table,

        [Parameter(Mandatory)]
        [string] $SolutionName,

        # Friendly name makers see in the Knowledge tab. Deliberately distinct
        # from the machine-style SearchName (design 6.3).
        [string] $DisplayName,

        # Machine-style dvtablesearch name, referenced verbatim by the component
        # YAML. Defaults to '<first table>_search'.
        [string] $SearchName,

        # Tail of the component schemaname '<botSchemaName>.knowledge.<this>'.
        # Defaults to the first table's logical name.
        [string] $ComponentName,

        [switch] $Json
    )

    if (-not $BotId -and [string]::IsNullOrWhiteSpace($BotName)) {
        throw [PckError]::new(
            'Pass -BotId or -BotName to identify the agent.',
            $script:PckExitCode.General)
    }

    if ([string]::IsNullOrWhiteSpace($SearchName)) { $SearchName = "$($Table[0])_search" }
    if ([string]::IsNullOrWhiteSpace($ComponentName)) { $ComponentName = $Table[0] }
    if ([string]::IsNullOrWhiteSpace($DisplayName)) { $DisplayName = "Knowledge: $($Table[0])" }

    # These values land in OData filters, schemanames, and YAML; refuse anything
    # that is not a machine name before it can rewrite a query.
    foreach ($value in (@($SearchName, $ComponentName) + $Table)) {
        if ($value -notmatch '^[A-Za-z][A-Za-z0-9_]*$') {
            throw [PckError]::new(
                "'$value' is not a valid machine name (letters, digits, underscores, starting with a letter).",
                $script:PckExitCode.General)
        }
    }

    # ── Preflight: refuse before anything exists ─────────────────────────────
    $agents = if ($BotId) { @(Get-PckAgentInfo -BotId $BotId) } else { @(Get-PckAgentInfo -Name $BotName) }
    if ($agents.Count -eq 0) {
        throw [PckError]::new(
            "No agent matches '$(if ($BotId) { $BotId } else { $BotName })' in the connected environment.",
            $script:PckExitCode.General)
    }
    if ($agents.Count -gt 1) {
        throw [PckError]::new(
            "'$BotName' matches $($agents.Count) agents ($(@($agents.Name) -join ', ')). Pass -BotId or an exact name.",
            $script:PckExitCode.General)
    }
    $agent = $agents[0]

    Assert-PckAgentHarness -Agent $agent
    Assert-PckAgentAuthMode -Agent $agent
    Assert-PckSolutionExists -SolutionName $SolutionName

    foreach ($t in $Table) {
        try {
            Invoke-PckDataverseRequest -Method Get -Path "EntityDefinitions(LogicalName='$t')?`$select=LogicalName" | Out-Null
        }
        catch {
            throw [PckError]::new(
                "Table '$t' does not exist in the connected environment.",
                $script:PckExitCode.General)
        }
    }

    $dup = @((Invoke-PckDataverseRequest -Method Get `
        -Path "dvtablesearchs?`$select=dvtablesearchid,name&`$filter=name eq '$SearchName'").value)
    if ($dup.Count -gt 0) {
        throw [PckError]::new(
            "A dvtablesearch named '$SearchName' already exists. Delete it or pass a different -SearchName; reusing one is not verified behavior.",
            $script:PckExitCode.General)
    }

    # ── Honest reporting: preconditions this cmdlet does not solve ───────────
    $warnings = [System.Collections.Generic.List[string]]::new()

    $org = @((Invoke-PckDataverseRequest -Method Get `
        -Path 'organizations?$select=organizationid,isexternalsearchindexenabled').value)[0]
    $searchEnabled = [bool]$org.isexternalsearchindexenabled
    if (-not $searchEnabled) {
        $warnings.Add('Dataverse search is disabled on this environment. Nothing grounds until Enable-PckDataverseSearch runs and index provisioning (hours on a fresh environment) completes.')
    }

    $findColumns = @{}
    foreach ($t in $Table) {
        $qf = Get-PckQuickFindColumns -TableLogicalName $t
        if (-not $qf) {
            $warnings.Add("Table '$t' has no Quick Find view, so Dataverse search has no find columns to index for it.")
            continue
        }
        $findColumns[$t] = @($qf.FindColumns)
        if (@($qf.FindColumns).Count -le 1) {
            $warnings.Add("Table '$t' Quick Find view searches only $(@($qf.FindColumns) -join ', '); other columns are invisible to the agent until find columns are added. No Web API route reliably updates this (war story 1): use solution surgery or the maker portal.")
        }
    }

    # ── Create, with best-effort rollback on mid-chain failure ───────────────
    $created = [System.Collections.Generic.List[string]]::new()
    try {
        $search = Invoke-PckDataverseRequest -Method Post -Path 'dvtablesearchs' `
            -Body @{ name = $SearchName } -SolutionName $SolutionName
        $created.Add("dvtablesearchs($($search.EntityId))")

        $entityIds = @(foreach ($t in $Table) {
            $row = Invoke-PckDataverseRequest -Method Post -Path 'dvtablesearchentities' -Body @{
                entitylogicalname          = $t
                'DVTableSearch@odata.bind' = "/dvtablesearchs($($search.EntityId))"
            } -SolutionName $SolutionName
            $created.Add("dvtablesearchentities($($row.EntityId))")
            $row.EntityId
        })

        $componentSchemaName = "$($agent.SchemaName).knowledge.$ComponentName"
        $component = Invoke-PckDataverseRequest -Method Post -Path 'botcomponents' -Body @{
            name                     = $DisplayName
            componenttype            = 16
            schemaname               = $componentSchemaName
            data                     = "kind: KnowledgeSourceConfiguration`nsource:`n  kind: DataverseStructuredSearchSource`n  skillConfiguration: $SearchName`n"
            'parentbotid@odata.bind' = "/bots($($agent.BotId))"
        } -SolutionName $SolutionName
        $created.Add("botcomponents($($component.EntityId))")

        Invoke-PckDataverseRequest -Method Post `
            -Path "botcomponents($($component.EntityId))/botcomponent_dvtablesearch/`$ref" `
            -Body @{ '@odata.id' = "$($script:PckContext.EnvironmentUrl)/api/data/$($script:PckApiVersion)/dvtablesearchs($($search.EntityId))" } `
            -SolutionName $SolutionName | Out-Null
    }
    catch {
        for ($i = $created.Count - 1; $i -ge 0; $i--) {
            try {
                Invoke-PckDataverseRequest -Method Delete -Path $created[$i] | Out-Null
            }
            catch {
                Write-Warning "Rollback of $($created[$i]) failed: $($_.Exception.Message). Clean it up manually."
            }
        }
        throw
    }

    foreach ($w in $warnings) { Write-Warning $w }

    $result = [pscustomobject]@{
        KnowledgeSourceId      = $component.EntityId
        DisplayName            = $DisplayName
        SchemaName             = $componentSchemaName
        DVTableSearchId        = $search.EntityId
        DVTableSearchEntityIds = $entityIds
        SearchName             = $SearchName
        Tables                 = @($Table)
        BotId                  = $agent.BotId
        BotName                = $agent.Name
        SolutionName           = $SolutionName
        SearchEnabled          = $searchEnabled
        FindColumns            = $findColumns
        Warnings               = @($warnings)
    }
    if ($Json) { $result | ConvertTo-Json -Depth 6 } else { $result }
}

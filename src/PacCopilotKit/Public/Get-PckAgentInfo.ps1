function Get-PckAgentInfo {
    <#
    .SYNOPSIS
    Reads harness and identity facts for Copilot Studio agents in the connected
    environment.

    .DESCRIPTION
    Returns one object per agent with BotId, Name, SchemaName, Template, and the
    derived Harness classification: Standard (default-*), NewExperience
    (cliagent-*), or Unknown. The SchemaName is the value component creates must
    read rather than construct (design 6.3), and the Harness is what
    Assert-PckAgentHarness gates on.

    The end-user authentication mode is deliberately absent until its storage
    shape is verified against a live environment (canon 16);
    Assert-PckAgentAuthMode waits on the same verification.

    .EXAMPLE
    Get-PckAgentInfo

    .EXAMPLE
    Get-PckAgentInfo -Name 'Support*' -Json
    #>
    [CmdletBinding()]
    param(
        [guid] $BotId,

        # Wildcard filter matched against both Name and SchemaName.
        [string] $Name,

        [switch] $Json
    )

    $select = '$select=botid,name,schemaname,template'

    $rows = if ($BotId) {
        @(Invoke-PckDataverseRequest -Method Get -Path "bots($BotId)?$select")
    }
    else {
        @((Invoke-PckDataverseRequest -Method Get -Path "bots?$select").value)
    }

    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $rows = @($rows | Where-Object { $_.name -like $Name -or $_.schemaname -like $Name })
    }

    $result = @(foreach ($row in $rows) {
        [pscustomobject]@{
            BotId      = $row.botid
            Name       = $row.name
            SchemaName = $row.schemaname
            Template   = $row.template
            Harness    = Get-PckHarnessFromTemplate -Template $row.template
        }
    })

    # -InputObject keeps the array shape: an empty result is '[]', never null or [null].
    if ($Json) { ConvertTo-Json -InputObject $result -Depth 4 } else { $result }
}

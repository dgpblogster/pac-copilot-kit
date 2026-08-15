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

    AuthenticationMode is the raw bot.authenticationmode picklist value and
    AuthenticationModeName its label; both verified live on 2026-08-15 (canon
    16; war story 3). Only Integrated (2, "Authenticate with Microsoft") can
    ground on Dataverse knowledge, which Assert-PckAgentAuthMode gates on.

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

    $select = '$select=botid,name,schemaname,template,authenticationmode'

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
            BotId                  = $row.botid
            Name                   = $row.name
            SchemaName             = $row.schemaname
            Template               = $row.template
            Harness                = Get-PckHarnessFromTemplate -Template $row.template
            AuthenticationMode     = $row.authenticationmode
            AuthenticationModeName = Get-PckAuthModeName -Value $row.authenticationmode
        }
    })

    # -InputObject keeps the array shape: an empty result is '[]', never null or [null].
    if ($Json) { ConvertTo-Json -InputObject $result -Depth 4 } else { $result }
}

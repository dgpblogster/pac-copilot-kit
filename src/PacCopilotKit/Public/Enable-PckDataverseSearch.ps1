function Enable-PckDataverseSearch {
    <#
    .SYNOPSIS
    Turns on Dataverse search for the connected environment by setting
    isexternalsearchindexenabled on the organization record.

    .DESCRIPTION
    Copilot Studio's Dataverse knowledge rides Dataverse search; with the org
    flag off, nothing grounds. This is an org-wide, once-per-environment act
    with a long tail: on a freshly provisioned environment, initial index
    provisioning took roughly two hours before seeded rows became searchable.
    Enabling is the start of that clock, not the end. Poll readiness with
    Wait-PckDataverseSearchReady, which queries rather than trusting /status.

    Idempotent (design rule 5.8): an already-enabled org is reported, not
    re-patched.

    .EXAMPLE
    Connect-PckPowerPlatform
    Enable-PckDataverseSearch -Json
    #>
    [CmdletBinding()]
    param(
        [switch] $Json
    )

    $org = @((Invoke-PckDataverseRequest -Method Get `
        -Path 'organizations?$select=organizationid,isexternalsearchindexenabled').value)[0]

    $alreadyEnabled = [bool]$org.isexternalsearchindexenabled
    if (-not $alreadyEnabled) {
        # Deliberately not solution content: this is an org setting, not a component.
        Invoke-PckDataverseRequest -Method Patch `
            -Path "organizations($($org.organizationid))" `
            -Body @{ isexternalsearchindexenabled = $true } `
            -NoSolution | Out-Null
        Write-Verbose 'Dataverse search enabled. Budget hours, not minutes, for initial index provisioning.'
    }
    else {
        Write-Verbose 'Dataverse search was already enabled; nothing to do.'
    }

    $result = [pscustomobject]@{
        OrganizationId = $org.organizationid
        AlreadyEnabled = $alreadyEnabled
        Enabled        = $true
    }
    if ($Json) { $result | ConvertTo-Json -Depth 4 } else { $result }
}

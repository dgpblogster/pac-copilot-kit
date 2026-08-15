function Resolve-PckOrgUrl {
    <#
    .SYNOPSIS
    Maps an environment id to its org URL through the global discovery service.

    .DESCRIPTION
    Fetches the instance list and filters client-side, which avoids OData filter
    quirks on the discovery endpoint. Requires a token source that can serve the
    discovery resource; a caller holding only an org-scoped PCK_ACCESS_TOKEN should
    pass -EnvironmentUrl to Connect-PckPowerPlatform instead.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $EnvironmentId
    )

    $token = Get-PckAccessToken -Resource $script:PckDiscoveryUrl
    $headers = @{
        Authorization = "Bearer $($token.AccessToken)"
        Accept        = 'application/json'
    }
    $resp = Invoke-RestMethod -Method Get `
        -Uri "$($script:PckDiscoveryUrl)/api/discovery/v2.0/Instances" `
        -Headers $headers

    $instances = if ($resp.PSObject.Properties['value']) { @($resp.value) } else { @() }
    $match = @($instances | Where-Object { $_.EnvironmentId -eq $EnvironmentId })

    if ($match.Count -eq 0) {
        throw [PckPreflightError]::new(
            "Environment '$EnvironmentId' was not found in the global discovery service for the current identity. Check the id, and check that this identity has access to the environment.",
            $script:PckExitCode.EnvironmentNotFound)
    }
    return ([string]$match[0].Url).TrimEnd('/')
}

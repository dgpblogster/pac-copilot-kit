function Get-PckAuthHeaders {
    <#
    .SYNOPSIS
    Returns the standard header set for a Dataverse Web API call, refreshing the
    cached token when it is within two minutes of expiry.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:PckToken -or $script:PckToken.ExpiresOn -lt (Get-Date).AddMinutes(2)) {
        $script:PckToken = Get-PckAccessToken -Resource $script:PckContext.EnvironmentUrl
    }
    return @{
        Authorization      = "Bearer $($script:PckToken.AccessToken)"
        Accept             = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
    }
}

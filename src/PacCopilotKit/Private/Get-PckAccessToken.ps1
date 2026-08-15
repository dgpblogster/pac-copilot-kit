function Get-PckAccessToken {
    <#
    .SYNOPSIS
    Acquires a bearer token for the given resource. Never reads pac auth state.

    .DESCRIPTION
    Implements the token-source decision in design 12.8. Mode selection is implicit:
    a complete PCK_SPN_* set means CI, anything else means dev.

    CI mode: client credentials against the Entra token endpoint. No dependency
    beyond HTTPS.

    Dev mode, first match wins:
      1. PCK_ACCESS_TOKEN (explicit, always wins)
      2. az account get-access-token, if the Azure CLI is on the path
      3. Get-AzAccessToken from Az.Accounts, if the module is present
      4. Hard error naming all three.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Resource
    )

    $Resource = $Resource.TrimEnd('/')

    $spn = @($env:PCK_SPN_TENANT, $env:PCK_SPN_APP_ID, $env:PCK_SPN_SECRET)
    $spnPresent = @($spn | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($spnPresent.Count -eq 3) {
        $body = @{
            grant_type    = 'client_credentials'
            client_id     = $env:PCK_SPN_APP_ID
            client_secret = $env:PCK_SPN_SECRET
            scope         = "$Resource/.default"
        }
        $resp = Invoke-RestMethod -Method Post `
            -Uri "https://login.microsoftonline.com/$($env:PCK_SPN_TENANT)/oauth2/v2.0/token" `
            -Body $body
        return @{
            AccessToken = $resp.access_token
            ExpiresOn   = (Get-Date).AddSeconds([int]$resp.expires_in)
        }
    }
    if ($spnPresent.Count -gt 0) {
        throw [PckPreflightError]::new(
            'CI mode is selected by the PCK_SPN_* variables, but the set is incomplete. All three of PCK_SPN_TENANT, PCK_SPN_APP_ID, and PCK_SPN_SECRET are required.',
            $script:PckExitCode.SpnIncomplete)
    }

    if (-not [string]::IsNullOrWhiteSpace($env:PCK_ACCESS_TOKEN)) {
        return @{
            AccessToken = $env:PCK_ACCESS_TOKEN
            ExpiresOn   = Get-PckJwtExpiry -Token $env:PCK_ACCESS_TOKEN
        }
    }

    if (Get-Command -Name az -CommandType Application -ErrorAction Ignore) {
        $raw = az account get-access-token --resource $Resource --output json 2>$null
        if ($LASTEXITCODE -eq 0 -and $raw) {
            $tok = ($raw -join "`n") | ConvertFrom-Json
            $expires = if ($tok.PSObject.Properties['expires_on'] -and $tok.expires_on) {
                [DateTimeOffset]::FromUnixTimeSeconds([long]$tok.expires_on).LocalDateTime
            }
            else {
                (Get-Date).AddMinutes(25)
            }
            return @{ AccessToken = $tok.accessToken; ExpiresOn = $expires }
        }
        Write-Verbose 'The Azure CLI is present but returned no token; falling through to Az.Accounts.'
    }

    if (Get-Module -ListAvailable -Name Az.Accounts) {
        Import-Module Az.Accounts -ErrorAction Stop
        $azTok = Get-AzAccessToken -ResourceUrl $Resource -ErrorAction Stop
        $plain = if ($azTok.Token -is [securestring]) {
            ConvertFrom-SecureString -SecureString $azTok.Token -AsPlainText
        }
        else {
            [string]$azTok.Token
        }
        return @{ AccessToken = $plain; ExpiresOn = $azTok.ExpiresOn.LocalDateTime }
    }

    throw [PckPreflightError]::new(
        'No token source available. Provide one of: PCK_ACCESS_TOKEN, a signed-in Azure CLI (az login), or the Az.Accounts module (Connect-AzAccount). CI mode uses PCK_SPN_TENANT, PCK_SPN_APP_ID, and PCK_SPN_SECRET instead.',
        $script:PckExitCode.TokenUnavailable)
}

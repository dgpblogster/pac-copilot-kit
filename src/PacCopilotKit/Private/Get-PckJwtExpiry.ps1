function Get-PckJwtExpiry {
    <#
    .SYNOPSIS
    Reads the exp claim from a JWT without validating it, for cache-expiry purposes
    only. Opaque or unparseable tokens get a short assumed lifetime rather than being
    trusted forever.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Token
    )

    try {
        $parts = $Token.Split('.')
        if ($parts.Count -ge 2) {
            $payload = $parts[1].Replace('-', '+').Replace('_', '/')
            switch ($payload.Length % 4) {
                2 { $payload += '==' }
                3 { $payload += '=' }
            }
            $claims = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
            if ($claims.PSObject.Properties['exp']) {
                return [DateTimeOffset]::FromUnixTimeSeconds([long]$claims.exp).LocalDateTime
            }
        }
    }
    catch {
        Write-Verbose "Token expiry could not be parsed: $($_.Exception.Message)"
    }
    return (Get-Date).AddMinutes(25)
}

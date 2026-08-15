function Invoke-PckDataverseRequest {
    <#
    .SYNOPSIS
    The single Dataverse Web API funnel (canon 5). Every Web API call in the module
    routes through here; no public cmdlet calls Invoke-RestMethod directly.

    .DESCRIPTION
    Responsibilities, in order:
      1. Refuse when not connected (Connect-PckPowerPlatform sets the context).
      2. Run request-construction guards, which refuse routes that are known to fail
         before any network call is made (design 6.2).
      3. Enforce solution-awareness (canon 7): Post, Patch, and Put require
         -SolutionName so the result lands inside a solution, unless the caller
         passes -NoSolution for operations that are deliberately not solution
         content, such as flipping isexternalsearchindexenabled on the organization.
      4. Send, honoring Retry-After on 429 and 503 up to -MaxRetries.
      5. Translate failures into PckError with the Dataverse error code in the
         message. Response-translation guards for known error signatures land here
         as they are authored.

    .OUTPUTS
    Parsed response body for 200-range responses with content. For 204 responses,
    an object with an EntityId property when OData-EntityId is present, otherwise
    null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Get', 'Post', 'Patch', 'Put', 'Delete')]
        [string] $Method,

        # Relative to /api/data/v9.2/ ('bots?$select=...'), or an absolute URL.
        [Parameter(Mandatory)]
        [string] $Path,

        [object] $Body,

        [string] $SolutionName,

        [switch] $NoSolution,

        [hashtable] $Headers = @{},

        [int] $MaxRetries = 3
    )

    if (-not $script:PckContext) {
        throw [PckPreflightError]::new(
            'Not connected. Call Connect-PckPowerPlatform first.',
            $script:PckExitCode.NotConnected)
    }

    # Guards inspect a normalized view of the request: absolute URLs reduced to
    # their data-relative path, leading slashes stripped, and string bodies parsed
    # as JSON when they are JSON. A guard that can be bypassed by respelling the
    # same request is not a guard.
    $guardPath = $Path
    if ($guardPath -match '(?i)^https?://[^/]+/api/data/v\d+\.\d+/(.+)$') {
        $guardPath = $Matches[1]
    }
    $guardPath = $guardPath.TrimStart('/')

    $guardBody = $Body
    if ($Body -is [string]) {
        try { $guardBody = $Body | ConvertFrom-Json } catch { }
    }

    foreach ($guard in $script:PckRequestConstructionGuards) {
        & $guard -Method $Method -Path $guardPath -Body $guardBody
    }

    $Headers = $Headers.Clone()
    if ($Method -in @('Post', 'Patch', 'Put')) {
        if ($NoSolution -and -not [string]::IsNullOrWhiteSpace($SolutionName)) {
            throw [PckError]::new(
                '-SolutionName and -NoSolution are contradictory. Pass one or the other.',
                $script:PckExitCode.General)
        }
        if (-not $NoSolution) {
            if ([string]::IsNullOrWhiteSpace($SolutionName)) {
                throw [PckError]::new(
                    "A $Method call requires -SolutionName so the result lands inside a solution (canon 7). Pass -NoSolution only for operations that are deliberately not solution content.",
                    $script:PckExitCode.General)
            }
            $Headers['MSCRM.SolutionUniqueName'] = $SolutionName
        }
    }

    $merged = Get-PckAuthHeaders
    foreach ($key in $Headers.Keys) { $merged[$key] = $Headers[$key] }

    $request = @{
        Method  = $Method
        Uri     = if ($Path -match '^https?://') { $Path }
                  else { "$($script:PckContext.EnvironmentUrl)/api/data/$($script:PckApiVersion)/$Path" }
        Headers = $merged
    }
    if ($null -ne $Body) {
        $request.Body = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 20 }
        $request.ContentType = 'application/json'
    }

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            $response = Invoke-WebRequest @request -ErrorAction Stop
            break
        }
        catch [Microsoft.PowerShell.Commands.HttpResponseException] {
            $status = [int]$_.Exception.Response.StatusCode
            if ($status -in @(429, 503) -and $attempt -le $MaxRetries) {
                $delay = 5
                try {
                    $retryAfter = $_.Exception.Response.Headers.RetryAfter
                    if ($retryAfter -and $retryAfter.Delta.HasValue) {
                        $delay = [int]$retryAfter.Delta.Value.TotalSeconds
                    }
                }
                catch { }
                $delay = [Math]::Min([Math]::Max($delay, 1), 60)
                Write-Verbose "HTTP $status from Dataverse. Retrying in $delay seconds (attempt $attempt of $MaxRetries)."
                Start-Sleep -Seconds $delay
                continue
            }

            $detail = $null
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                try { $detail = ($_.ErrorDetails.Message | ConvertFrom-Json).error } catch { }
            }
            $code = if ($detail -and $detail.PSObject.Properties['code']) { $detail.code } else { "HTTP $status" }
            $message = if ($detail -and $detail.PSObject.Properties['message']) { $detail.message } else { $_.Exception.Message }

            # Response translators (design 6.2): known failure signatures become
            # war-story guidance instead of an opaque code.
            foreach ($translator in $script:PckResponseTranslators) {
                $translated = & $translator -Method $Method -Path $guardPath -Body $guardBody -Code $code -Message $message
                if ($translated) {
                    throw [PckError]::new($translated, $script:PckExitCode.KnownBrokenRoute)
                }
            }
            throw [PckError]::new(
                "Dataverse request failed: $Method $Path. Code: $code. $message",
                $script:PckExitCode.General)
        }
    }

    if ([int]$response.StatusCode -eq 204 -or [string]::IsNullOrWhiteSpace([string]$response.Content)) {
        if ($response.Headers.ContainsKey('OData-EntityId')) {
            $raw = [string]@($response.Headers['OData-EntityId'])[0]
            if ($raw -match '\(([0-9a-fA-F-]{36})\)') {
                return [pscustomobject]@{ EntityId = $Matches[1] }
            }
        }
        return $null
    }
    return $response.Content | ConvertFrom-Json
}

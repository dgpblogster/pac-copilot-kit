function Wait-PckDataverseSearchReady {
    <#
    .SYNOPSIS
    Blocks until seeded rows in the given tables are actually searchable,
    by polling the search query endpoint. Never consults /status.

    .DESCRIPTION
    The Dataverse search status endpoint reports zero indexed tables even while
    queries against the same data succeed, in both directions of wrong. The only
    trustworthy readiness signal is a real query returning hits, so that is the
    only signal this cmdlet uses (war story territory; design 6.2).

    -SearchText must be a term the seeded content actually contains; an empty
    table grounds nothing and matches nothing. The default timeout is sized for
    initial index provisioning on a fresh environment, which took roughly two
    hours in practice.

    .EXAMPLE
    Wait-PckDataverseSearchReady -Table wrk_caseresolution -SearchText 'scanner'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $Table,

        [Parameter(Mandatory)]
        [string] $SearchText,

        [double] $TimeoutMinutes = 150,

        [ValidateRange(0, 3600)]
        [int] $IntervalSeconds = 60,

        [switch] $Json
    )

    if (-not $script:PckContext) {
        throw [PckPreflightError]::new(
            'Not connected. Call Connect-PckPowerPlatform first.',
            $script:PckExitCode.NotConnected)
    }

    $queryUrl = "$($script:PckContext.EnvironmentUrl)/api/search/v1.0/query"
    $body = @{
        search   = $SearchText
        entities = @($Table)
        top      = 5
    }

    $started = Get-Date
    $deadline = $started.AddMinutes($TimeoutMinutes)
    $attempts = 0

    while ($true) {
        $attempts++
        $hits = 0
        try {
            $resp = Invoke-PckDataverseRequest -Method Post -Path $queryUrl -Body $body -NoSolution
            if ($resp -and $resp.PSObject.Properties['value']) {
                $hits = @($resp.value).Count
            }
        }
        catch {
            # A search endpoint that errors while the index provisions is part of
            # the readiness problem being waited out, not a reason to give up.
            Write-Verbose "Search probe failed (attempt $attempts): $($_.Exception.Message)"
        }

        if ($hits -gt 0) {
            $result = [pscustomobject]@{
                Ready          = $true
                Tables         = @($Table)
                SearchText     = $SearchText
                Hits           = $hits
                Attempts       = $attempts
                ElapsedSeconds = [int]((Get-Date) - $started).TotalSeconds
            }
            if ($Json) { return ($result | ConvertTo-Json -Depth 4) }
            return $result
        }

        if ((Get-Date) -ge $deadline) {
            throw [PckError]::new(
                "Dataverse search returned no hits for '$SearchText' in $($Table -join ', ') after $attempts probes over $([int]((Get-Date) - $started).TotalMinutes) minutes. Check that rows are seeded, that the search columns are find columns on the Quick Find view (war story 1), and that the org search flag is on (Enable-PckDataverseSearch). Initial provisioning on a fresh environment can take hours.",
                $script:PckExitCode.General)
        }

        Write-Verbose "No hits yet (attempt $attempts). Next probe in $IntervalSeconds seconds."
        if ($IntervalSeconds -gt 0) { Start-Sleep -Seconds $IntervalSeconds }
    }
}

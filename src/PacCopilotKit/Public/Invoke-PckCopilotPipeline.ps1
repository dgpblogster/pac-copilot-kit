function Invoke-PckCopilotPipeline {
    <#
    .SYNOPSIS
    The paved road: preflight, offline validation, pack, import, and publish
    against a pinned environment, in one call.

    .DESCRIPTION
    Forward from source (design 5.9): the workspace is packed and imported as
    the repository defines it; nothing is inferred from what the environment
    already contains.

    Order: environment context (canon 4), pac floor (war story 6), pac auth
    (implicit mode per design 5.2: a complete PCK_SPN_* set creates a
    temporary CI profile that is deleted on exit, anything else verifies the
    active dev profile is aligned), offline workspace lint, pac copilot pack,
    pac solution import with publish. The first failure stops the pipeline
    with the appropriate exit code; nothing later runs.

    -WhatIf runs everything read-only (context, floor, alignment, lint) and
    reports the pack and import it would have run. This is what the MCP verb
    plan-deployment wraps.

    .EXAMPLE
    Invoke-PckCopilotPipeline -SolutionName WorkbenchSupportAssistant `
        -SourcePath C:\src\agent -PublisherPrefix wrk -Json

    .EXAMPLE
    Invoke-PckCopilotPipeline -SolutionName WorkbenchSupportAssistant `
        -SourcePath .\agent -PublisherPrefix wrk -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $SolutionName,

        # The pac copilot workspace. Absolute, or relative to PCK_WORKSPACE_ROOT.
        [Parameter(Mandatory)]
        [string] $SourcePath,

        [Parameter(Mandatory)]
        [string] $PublisherPrefix,

        [string] $EnvironmentId,

        [switch] $Json
    )

    # These values become pac arguments and a filename; refuse anything that
    # could not be a solution name or publisher prefix before pac sees it.
    if ($SolutionName -notmatch '^[A-Za-z0-9_]+$') {
        throw [PckError]::new(
            "Solution name '$SolutionName' is not a valid solution unique name (letters, digits, underscores).",
            $script:PckExitCode.General)
    }
    if ($PublisherPrefix -notmatch '^[A-Za-z][A-Za-z0-9]{1,7}$') {
        throw [PckError]::new(
            "Publisher prefix '$PublisherPrefix' is not valid (2 to 8 alphanumerics, starting with a letter).",
            $script:PckExitCode.General)
    }

    $src = Resolve-PckOutputPath -Path $SourcePath
    if (-not (Test-Path -LiteralPath $src -PathType Container)) {
        throw [PckError]::new("Source path '$src' does not exist.", $script:PckExitCode.General)
    }

    $steps = [System.Collections.Generic.List[object]]::new()

    # 1. Environment context (canon 4). Reuse the session connection only when
    #    it matches the pinned environment.
    $resolvedEnv = Resolve-PckEnvironmentId -EnvironmentId $EnvironmentId
    if (-not $script:PckContext -or $script:PckContext.EnvironmentId -ne $resolvedEnv) {
        Connect-PckPowerPlatform -EnvironmentId $resolvedEnv | Out-Null
    }
    $steps.Add([pscustomobject]@{ Step = 'connect'; Status = 'ok'; Detail = $script:PckContext.EnvironmentUrl })

    # 2. pac floor (war story 6).
    Assert-PckPacVersion
    $steps.Add([pscustomobject]@{ Step = 'pac-version'; Status = 'ok'; Detail = 'at or above the tested floor' })

    $ciProfile = $null
    $zip = $null
    try {
        # 3. pac auth, mode implicit from the PCK_SPN_* set (design 5.2).
        $spnComplete = -not [string]::IsNullOrWhiteSpace($env:PCK_SPN_TENANT) -and
                       -not [string]::IsNullOrWhiteSpace($env:PCK_SPN_APP_ID) -and
                       -not [string]::IsNullOrWhiteSpace($env:PCK_SPN_SECRET)
        if ($spnComplete) {
            $profileName = "pck-ci-$PID"
            if ($PSCmdlet.ShouldProcess("pac auth profile '$profileName'", 'Create temporary CI auth profile')) {
                Invoke-PckPacCommand -Sensitive -Arguments @(
                    'auth', 'create', '--name', $profileName,
                    '--applicationId', $env:PCK_SPN_APP_ID,
                    '--clientSecret', $env:PCK_SPN_SECRET,
                    '--tenant', $env:PCK_SPN_TENANT,
                    '--environment', $resolvedEnv) | Out-Null
                $ciProfile = $profileName
                $steps.Add([pscustomobject]@{ Step = 'pac-auth'; Status = 'ok'; Detail = 'temporary CI profile created' })
            }
            else {
                $steps.Add([pscustomobject]@{ Step = 'pac-auth'; Status = 'whatif'; Detail = 'would create a temporary CI profile' })
            }
        }
        else {
            Assert-PckProfileAligned -EnvironmentId $resolvedEnv -EnvironmentUrl $script:PckContext.EnvironmentUrl
            $steps.Add([pscustomobject]@{ Step = 'pac-auth'; Status = 'ok'; Detail = 'active dev profile aligned' })
        }

        # 4. Offline lint, before anything touches the tenant (design 6.2).
        $issues = @(Test-PckAgentWorkspace -Path $src)
        if ($issues.Count -gt 0) {
            $detail = ($issues | ForEach-Object { "$($_.File):$($_.Line) [$($_.Rule)] $($_.Message)" }) -join "`n"
            throw [PckError]::new(
                "Workspace validation failed with $($issues.Count) issue(s). Nothing was deployed.`n$detail",
                $script:PckExitCode.General)
        }
        $steps.Add([pscustomobject]@{ Step = 'validate'; Status = 'ok'; Detail = 'workspace lint clean' })

        # 5. Pack. Local, no auth, safe in a build pipeline; the zip lands in
        #    the workspace.
        if ($PSCmdlet.ShouldProcess($src, "pac copilot pack ($SolutionName)")) {
            Invoke-PckPacCommand -WorkingDirectory $src -Arguments @(
                'copilot', 'pack',
                '--publisher-prefix', $PublisherPrefix,
                '--solution-name', $SolutionName) | Out-Null

            $zip = Join-Path $src "$SolutionName.zip"
            if (-not (Test-Path -LiteralPath $zip)) {
                $newest = Get-ChildItem -LiteralPath $src -Filter '*.zip' -File |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if (-not $newest) {
                    throw [PckError]::new(
                        'pac copilot pack completed but produced no zip in the source path.',
                        $script:PckExitCode.General)
                }
                $zip = $newest.FullName
            }
            $steps.Add([pscustomobject]@{ Step = 'pack'; Status = 'ok'; Detail = $zip })
        }
        else {
            $steps.Add([pscustomobject]@{ Step = 'pack'; Status = 'whatif'; Detail = "would pack $src as $SolutionName" })
        }

        # 6. Import and publish, against the profile just verified or created.
        if ($zip -and $PSCmdlet.ShouldProcess($script:PckContext.EnvironmentUrl, "pac solution import ($SolutionName, publish changes)")) {
            Invoke-PckPacCommand -WorkingDirectory $src -Arguments @(
                'solution', 'import', '--path', $zip, '--publish-changes') | Out-Null
            $steps.Add([pscustomobject]@{ Step = 'import'; Status = 'ok'; Detail = 'imported and published' })
        }
        elseif (-not $zip) {
            $steps.Add([pscustomobject]@{ Step = 'import'; Status = 'whatif'; Detail = "would import into $($script:PckContext.EnvironmentUrl)" })
        }
    }
    finally {
        # The temporary CI profile never outlives the run (design 5.2).
        if ($ciProfile) {
            try {
                Invoke-PckPacCommand -Arguments @('auth', 'delete', '--name', $ciProfile) | Out-Null
            }
            catch {
                Write-Warning "Could not delete temporary CI auth profile '$ciProfile': $($_.Exception.Message)"
            }
        }
    }

    $result = [pscustomobject]@{
        SolutionName  = $SolutionName
        EnvironmentId = $resolvedEnv
        SourcePath    = $src
        ZipPath       = $zip
        Steps         = @($steps)
        Succeeded     = $true
    }
    if ($Json) { ConvertTo-Json -InputObject $result -Depth 5 } else { $result }
}

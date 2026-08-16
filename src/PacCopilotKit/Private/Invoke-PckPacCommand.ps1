function Invoke-PckPacCommand {
    <#
    .SYNOPSIS
    The single pac CLI funnel: every pac invocation in the module routes
    through here, mirroring what Invoke-PckDataverseRequest is for the Web API.

    .DESCRIPTION
    Runs pac with the given arguments, optionally from an explicit working
    directory (design 5.7: nothing depends on $PWD implicitly), captures all
    output, and throws PckError with the exit code and output tail on failure.

    -Sensitive marks invocations whose arguments carry secrets, such as
    pac auth create with a client secret. For those, neither the arguments nor
    the output ever appear in verbose logging or error text; only the exit code
    does. pac may echo argument context into its own output, so withholding
    the arguments alone is not enough.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments,

        [string] $WorkingDirectory,

        [switch] $Sensitive
    )

    $pac = Get-Command -Name pac -CommandType Application -ErrorAction Ignore
    if (-not $pac) {
        throw [PckPreflightError]::new(
            'The pac CLI is not on the PATH. Install it from https://aka.ms/PowerPlatformCLI and retry.',
            $script:PckExitCode.PacUnavailable)
    }

    $display = $Sensitive ? 'pac (arguments withheld: sensitive)' : "pac $($Arguments -join ' ')"
    Write-Verbose "Running: $display"

    $output = @()
    if ($WorkingDirectory) { Push-Location -LiteralPath $WorkingDirectory }
    try {
        $output = @(& $pac.Source @Arguments 2>&1 | ForEach-Object { [string]$_ })
    }
    finally {
        if ($WorkingDirectory) { Pop-Location }
    }

    if ($LASTEXITCODE -ne 0) {
        $detail = if ($Sensitive) { 'Output withheld: the command carried sensitive arguments.' }
                  else { ($output | Select-Object -Last 10) -join "`n" }
        throw [PckError]::new(
            "pac exited with code $LASTEXITCODE. Command: $display`n$detail",
            $script:PckExitCode.General)
    }

    # pac exits 0 on argument and validation errors while printing 'Error: ...',
    # observed live three times in one session (war story 7). The exit code alone
    # is not trusted; an Error: line in the output is a failure.
    $errorLines = @($output | Where-Object { $_ -match '^\s*Error:' })
    if ($errorLines.Count -gt 0) {
        $detail = if ($Sensitive) { 'Output withheld: the command carried sensitive arguments.' }
                  else { $errorLines -join "`n" }
        throw [PckError]::new(
            "pac reported an error although its exit code was 0 (war story 7). Command: $display`n$detail",
            $script:PckExitCode.General)
    }
    return $output
}

#Requires -Version 7.4
Set-StrictMode -Version 3.0

# Error types. Preflight errors carry exit codes 10..19 (canon 9); everything else is
# an operational failure. Known-broken-route refusals use 20 so CI can tell "this route
# never works" apart from "this call failed today".
class PckError : System.Exception {
    [int] $ExitCode
    PckError([string] $Message, [int] $ExitCode) : base($Message) {
        $this.ExitCode = $ExitCode
    }
}

class PckPreflightError : PckError {
    PckPreflightError([string] $Message, [int] $ExitCode) : base($Message, $ExitCode) {}
}

# Load order matters only in that constants come first; the list below guarantees it.
$loadOrder = @(
    Get-ChildItem -Path "$PSScriptRoot/Private" -Filter '*.ps1' -File | Sort-Object Name
    Get-ChildItem -Path "$PSScriptRoot/Private/Guards" -Filter '*.ps1' -File | Sort-Object Name
    Get-ChildItem -Path "$PSScriptRoot/Public" -Filter '*.ps1' -File | Sort-Object Name
)
foreach ($file in $loadOrder) {
    . $file.FullName
}

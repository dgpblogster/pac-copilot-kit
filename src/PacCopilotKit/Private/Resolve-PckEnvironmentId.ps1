function Resolve-PckEnvironmentId {
    <#
    .SYNOPSIS
    Resolves the environment id: parameter, then PCK_DEFAULT_ENVIRONMENT_ID, then a
    hard error. The active pac auth profile is never consulted (canon 4).
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $EnvironmentId
    )

    if ([string]::IsNullOrWhiteSpace($EnvironmentId)) {
        $EnvironmentId = $env:PCK_DEFAULT_ENVIRONMENT_ID
    }
    if ([string]::IsNullOrWhiteSpace($EnvironmentId)) {
        throw [PckPreflightError]::new(
            'No environment id. Pass -EnvironmentId or set PCK_DEFAULT_ENVIRONMENT_ID. The active pac auth profile default org is never used (canon 4).',
            $script:PckExitCode.EnvironmentNotSpecified)
    }

    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($EnvironmentId, [ref] $parsed)) {
        throw [PckPreflightError]::new(
            "Environment id '$EnvironmentId' is not a GUID.",
            $script:PckExitCode.EnvironmentNotSpecified)
    }
    return $parsed.ToString()
}

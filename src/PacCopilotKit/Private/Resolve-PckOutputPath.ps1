function Resolve-PckOutputPath {
    <#
    .SYNOPSIS
    Resolves a path parameter per design rule 5.7: absolute paths pass through,
    relative paths resolve against PCK_WORKSPACE_ROOT, and a relative path with
    no root set is a hard error. Nothing in the module ever depends on $PWD.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    if ([string]::IsNullOrWhiteSpace($env:PCK_WORKSPACE_ROOT)) {
        throw [PckPreflightError]::new(
            "Path '$Path' is relative and PCK_WORKSPACE_ROOT is not set. Pass an absolute path, or set PCK_WORKSPACE_ROOT (design rule 5.7: nothing depends on the current directory).",
            $script:PckExitCode.WorkspaceRootUnset)
    }
    if (-not [System.IO.Path]::IsPathRooted($env:PCK_WORKSPACE_ROOT)) {
        throw [PckPreflightError]::new(
            "PCK_WORKSPACE_ROOT '$($env:PCK_WORKSPACE_ROOT)' is itself relative. It must be an absolute path.",
            $script:PckExitCode.WorkspaceRootUnset)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $env:PCK_WORKSPACE_ROOT $Path))
}

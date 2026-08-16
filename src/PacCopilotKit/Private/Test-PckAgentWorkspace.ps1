function Test-PckAgentWorkspace {
    <#
    .SYNOPSIS
    Offline lint of a pac copilot workspace, run before anything touches the
    tenant. Returns issue objects; an empty result is a clean workspace.

    .DESCRIPTION
    Named checks only, honestly scoped: this is not a schema validator.

    - Workspace: at least one .mcs.yml file exists.
    - TabIndentation: YAML forbids tabs; pac tooling surfaces this late.
    - PowerFxColonSpace: the highest-value check in the loop (design 6.2). An
      unquoted Power Fx value containing ': ' parses as a nested mapping
      instead of a string, and surfaces as strange agent behavior at runtime
      rather than as an error. Catching it here costs a second; catching it
      after deployment costs an afternoon.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $issues = [System.Collections.Generic.List[object]]::new()

    $files = @(Get-ChildItem -LiteralPath $Path -Recurse -Filter '*.mcs.yml' -File -ErrorAction Ignore)
    if ($files.Count -eq 0) {
        $issues.Add([pscustomobject]@{
            File = $Path; Line = 0; Rule = 'Workspace'
            Message = 'No .mcs.yml files found. Is this a pac copilot workspace?'
        })
        return @($issues)
    }

    foreach ($file in $files) {
        $lineNumber = 0
        foreach ($line in @(Get-Content -LiteralPath $file.FullName)) {
            $lineNumber++
            if ($line -match '^\t') {
                $issues.Add([pscustomobject]@{
                    File = $file.FullName; Line = $lineNumber; Rule = 'TabIndentation'
                    Message = 'YAML forbids tab indentation; this line starts with a tab.'
                })
            }
            # YAML-level quoting is the only protection: a plain scalar starting
            # with '=' breaks on ': ' anywhere, and Power Fx's own quotes are
            # invisible to YAML. Trailing comments are stripped before the test.
            $stripped = $line -replace '\s+#.*$', ''
            if ($stripped -match '^\s*[A-Za-z0-9_-]+:\s+=.*:\s') {
                $issues.Add([pscustomobject]@{
                    File = $file.FullName; Line = $lineNumber; Rule = 'PowerFxColonSpace'
                    Message = "A Power Fx value not YAML-quoted contains ': '. YAML parses this as a nested mapping and the agent misbehaves at runtime with no error; Power Fx's own quotes do not protect it. YAML-quote the whole value or use a block scalar (|)."
                })
            }
        }
    }
    return @($issues)
}

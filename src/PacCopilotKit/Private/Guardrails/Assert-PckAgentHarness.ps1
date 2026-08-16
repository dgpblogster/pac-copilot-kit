function Assert-PckAgentHarness {
    <#
    .SYNOPSIS
    Refuses agents that are not the standard harness.

    .DESCRIPTION
    Knowledge components created against a cliagent-* (newer experience) agent
    display in the Knowledge panel, because the panel reads the same component
    table, while the runtime never queries them. The agent answers from general
    model knowledge with no error anywhere. Unknown templates are refused too:
    the failure mode this guardrail prevents is silent, so unrecognized is unsafe
    (design 6.1; war story 2 in docs/war-stories.md).
    #>
    [CmdletBinding()]
    param(
        # A template string, or any object with a Template (or template) property,
        # such as a Get-PckAgentInfo result.
        [Parameter(Mandatory)]
        [object] $Agent
    )

    $template = if ($Agent -is [string]) {
        $Agent
    }
    else {
        $prop = $Agent.PSObject.Properties['Template'] ?? $Agent.PSObject.Properties['template']
        if (-not $prop) {
            throw [PckError]::new(
                'Assert-PckAgentHarness needs a template string or an object with a Template property.',
                $script:PckExitCode.General)
        }
        [string]$prop.Value
    }

    $harness = Get-PckHarnessFromTemplate -Template $template
    if ($harness -eq 'Standard') { return }

    $reason = if ($harness -eq 'NewExperience') {
        "template '$template' is the newer agent experience. Knowledge components created against it display in the Knowledge panel but the runtime never queries them; the agent answers from general model knowledge with no error anywhere."
    }
    else {
        "template '$template' is not a recognized standard-harness template. Refusing rather than risking silent non-grounding."
    }

    throw [PckPreflightError]::new(
        "Agent harness check failed: $reason To build standard-harness agents, turn the New experience toggle off on the Copilot Studio homepage, or pick Other ways to build.",
        $script:PckExitCode.HarnessUnsupported)
}

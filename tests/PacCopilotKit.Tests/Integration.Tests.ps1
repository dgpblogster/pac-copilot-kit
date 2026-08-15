#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

<#
Live-environment integration tests. Tagged Integration and skipped unless
PCK_DEFAULT_ENVIRONMENT_ID is set, so the default test run never touches the
network. Run them deliberately:

    Invoke-Pester -Path tests -Tag Integration

The environment id lives only in the operator's shell (canon 13).
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' '..' 'src' 'PacCopilotKit' 'PacCopilotKit.psd1'
    Import-Module $modulePath -Force
}

Describe 'Live environment' -Tag 'Integration' {

    It 'connects and answers WhoAmI' -Skip:(-not $env:PCK_DEFAULT_ENVIRONMENT_ID) {
        $ctx = Connect-PckPowerPlatform
        $ctx.UserId | Should -Not -BeNullOrEmpty
        $ctx.EnvironmentUrl | Should -Match '^https://'
    }

    It 'reads agents and classifies their harness' -Skip:(-not $env:PCK_DEFAULT_ENVIRONMENT_ID) {
        Connect-PckPowerPlatform | Out-Null
        $agents = @(Get-PckAgentInfo)
        foreach ($agent in $agents) {
            $agent.Harness | Should -BeIn @('Standard', 'NewExperience', 'Unknown')
        }
    }

    # Canon 6, applied to a guard with no translated call (design 6.4): the test
    # proves the untranslated call fails with the documented signature. The PATCH
    # deliberately bypasses the funnel and writes the fetchxml value back unchanged,
    # so even in the undocumented event that it succeeds, the record is unaltered.
    # If this test ever reports success on the PATCH, the platform shape changed
    # and war story 1 needs re-verification (canon 16).
    It 'proves the raw savedquery fetchxml PATCH fails with 0x80040216' -Skip:(-not $env:PCK_DEFAULT_ENVIRONMENT_ID) {
        Connect-PckPowerPlatform | Out-Null

        $ctx = InModuleScope PacCopilotKit { $script:PckContext }
        $headers = InModuleScope PacCopilotKit { Get-PckAuthHeaders }

        $view = (Invoke-RestMethod -Method Get -Headers $headers -Uri (
            "$($ctx.EnvironmentUrl)/api/data/v9.2/savedqueries?`$select=savedqueryid,fetchxml&`$filter=querytype eq 4&`$top=1"
        )).value | Select-Object -First 1
        $view | Should -Not -BeNullOrEmpty

        $failed = $false
        $errorBody = ''
        try {
            Invoke-RestMethod -Method Patch -Headers $headers -ContentType 'application/json' `
                -Uri "$($ctx.EnvironmentUrl)/api/data/v9.2/savedqueries($($view.savedqueryid))" `
                -Body (@{ fetchxml = $view.fetchxml } | ConvertTo-Json)
        }
        catch {
            $failed = $true
            $errorBody = [string]$_.ErrorDetails.Message
        }

        $failed | Should -BeTrue -Because 'war story 1 documents that no Web API route can update savedquery fetchxml'
        $errorBody | Should -Match '0x80040216'
    }
}

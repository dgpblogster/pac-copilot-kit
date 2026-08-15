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

    # War story 1, as narrowed by live verification on 2026-08-15: the fetchxml
    # update fails with 0x80040216 on most Quick Find views while a minority
    # accept the same call, and the discriminator is not yet identified. This
    # test therefore probes several custom-table Quick Finds and asserts the
    # translation contract on the first failure it finds. Every PATCH writes the
    # existing fetchxml back unchanged, so successes alter nothing that matters.
    # If every probed view accepts the call, the story needs re-verification
    # (canon 16) and the test says so by skipping loudly.
    It 'translates the Quick Find fetchxml failure wherever it reproduces' -Skip:(-not $env:PCK_DEFAULT_ENVIRONMENT_ID) {
        Connect-PckPowerPlatform | Out-Null

        $ctx = InModuleScope PacCopilotKit { $script:PckContext }
        $headers = InModuleScope PacCopilotKit { Get-PckAuthHeaders }

        # Note the returnedtypecode filter quirk (war story 4): the attribute
        # serializes as the entity's logical name and filters only as a quoted
        # logical name.
        $customTables = @((Invoke-RestMethod -Method Get -Headers $headers -Uri (
            "$($ctx.EnvironmentUrl)/api/data/v9.2/EntityDefinitions?`$select=LogicalName&`$filter=IsCustomEntity eq true"
        )).value)

        $tried = 0
        $translationError = $null
        foreach ($table in $customTables) {
            if ($tried -ge 5) { break }
            $view = @((Invoke-RestMethod -Method Get -Headers $headers -Uri (
                "$($ctx.EnvironmentUrl)/api/data/v9.2/savedqueries?`$select=savedqueryid,fetchxml&`$filter=querytype eq 4 and returnedtypecode eq '$($table.LogicalName)'"
            )).value) | Select-Object -First 1
            if (-not $view) { continue }
            $tried++
            try {
                InModuleScope PacCopilotKit -Parameters @{ id = $view.savedqueryid; fx = $view.fetchxml } {
                    param($id, $fx)
                    Invoke-PckDataverseRequest -Method Patch `
                        -Path "savedqueries($id)" `
                        -Body @{ fetchxml = $fx } -NoSolution
                } | Out-Null
            }
            catch {
                $translationError = $_
                break
            }
        }

        if ($tried -eq 0) {
            Set-ItResult -Skipped -Because 'no custom table with a Quick Find view exists in this environment'
            return
        }
        if (-not $translationError) {
            Set-ItResult -Skipped -Because "all $tried probed Quick Find views accepted the fetchxml PATCH; war story 1 needs re-verification (canon 16)"
            return
        }

        $translationError.Exception.ExitCode | Should -Be 20
        $translationError.Exception.Message | Should -Match '0x80040216'
        $translationError.Exception.Message | Should -Match 'story 1'
    }
}

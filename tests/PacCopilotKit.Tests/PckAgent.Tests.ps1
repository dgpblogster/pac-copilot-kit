#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' '..' 'src' 'PacCopilotKit' 'PacCopilotKit.psd1'
    Import-Module $modulePath -Force
}

Describe 'Get-PckAgentInfo' {
    BeforeEach {
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            [pscustomobject]@{
                value = @(
                    [pscustomobject]@{
                        botid      = 'aaaaaaaa-0000-0000-0000-000000000001'
                        name       = 'Support Assistant'
                        schemaname = 'wrk_SupportAssistant'
                        template   = 'default-2.1.0'
                    }
                    [pscustomobject]@{
                        botid      = 'aaaaaaaa-0000-0000-0000-000000000002'
                        name       = 'New Experience Agent'
                        schemaname = 'new_Agent_a1b2c3'
                        template   = 'cliagent-1.0.0'
                    }
                    [pscustomobject]@{
                        botid      = 'aaaaaaaa-0000-0000-0000-000000000003'
                        name       = 'Odd One'
                        schemaname = 'wrk_OddOne'
                        template   = 'something-else-9.9'
                    }
                )
            }
        }
    }

    It 'classifies default-* as Standard' {
        $result = Get-PckAgentInfo -Name 'Support Assistant'
        $result.Harness | Should -Be 'Standard'
    }

    It 'classifies cliagent-* as NewExperience' {
        $result = Get-PckAgentInfo -Name 'New Experience Agent'
        $result.Harness | Should -Be 'NewExperience'
    }

    It 'classifies anything else as Unknown' {
        $result = Get-PckAgentInfo -Name 'Odd One'
        $result.Harness | Should -Be 'Unknown'
    }

    It 'returns every agent when no filter is given' {
        @(Get-PckAgentInfo).Count | Should -Be 3
    }

    It 'filters against schemaname as well as name' {
        $result = @(Get-PckAgentInfo -Name 'wrk_*')
        $result.Count | Should -Be 2
    }

    It 'produces parseable JSON with -Json' {
        $parsed = Get-PckAgentInfo -Json | ConvertFrom-Json
        @($parsed).Count | Should -Be 3
        @($parsed)[0].Harness | Should -Be 'Standard'
    }

    It 'requests only the columns verified against live orgs (canon 16)' {
        Get-PckAgentInfo | Out-Null
        Should -Invoke -ModuleName PacCopilotKit Invoke-PckDataverseRequest -Times 1 -Exactly -ParameterFilter {
            $Path -eq 'bots?$select=botid,name,schemaname,template'
        }
    }
}

Describe 'Assert-PckAgentHarness (war story 2)' {
    It 'passes a standard-harness template string silently' {
        InModuleScope PacCopilotKit {
            Assert-PckAgentHarness -Agent 'default-2.1.0'
        }
    }

    It 'passes an agent object from Get-PckAgentInfo' {
        InModuleScope PacCopilotKit {
            Assert-PckAgentHarness -Agent ([pscustomobject]@{ Template = 'default-2.1.0' })
        }
    }

    It 'refuses cliagent-* with exit code 14 and names the silent failure' {
        $err = { InModuleScope PacCopilotKit { Assert-PckAgentHarness -Agent 'cliagent-1.0.0' } } |
            Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 14
        $err.Exception.Message | Should -Match 'never queries'
    }

    It 'refuses an unrecognized template rather than risking silent non-grounding' {
        $err = { InModuleScope PacCopilotKit { Assert-PckAgentHarness -Agent 'mystery-3.0.0' } } |
            Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 14
    }

    It 'rejects an object with no template property at all' {
        { InModuleScope PacCopilotKit { Assert-PckAgentHarness -Agent ([pscustomobject]@{ Foo = 1 }) } } |
            Should -Throw -ExpectedMessage '*Template property*'
    }
}

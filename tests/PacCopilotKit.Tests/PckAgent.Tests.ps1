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
                        botid              = 'aaaaaaaa-0000-0000-0000-000000000001'
                        name               = 'Support Assistant'
                        schemaname         = 'wrk_SupportAssistant'
                        template           = 'default-2.1.0'
                        authenticationmode = 2
                    }
                    [pscustomobject]@{
                        botid              = 'aaaaaaaa-0000-0000-0000-000000000002'
                        name               = 'New Experience Agent'
                        schemaname         = 'new_Agent_a1b2c3'
                        template           = 'cliagent-1.0.0'
                        authenticationmode = 2
                    }
                    [pscustomobject]@{
                        botid              = 'aaaaaaaa-0000-0000-0000-000000000003'
                        name               = 'Odd One'
                        schemaname         = 'wrk_OddOne'
                        template           = 'something-else-9.9'
                        authenticationmode = 1
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
            $Path -eq 'bots?$select=botid,name,schemaname,template,authenticationmode'
        }
    }

    It 'maps the authentication mode to its verified label' {
        $result = Get-PckAgentInfo -Name 'Support Assistant'
        $result.AuthenticationMode | Should -Be 2
        $result.AuthenticationModeName | Should -Be 'Integrated'
        (Get-PckAgentInfo -Name 'Odd One').AuthenticationModeName | Should -Be 'None'
    }
}

Describe 'Assert-PckAgentAuthMode (war story 3)' {
    It 'passes Integrated (2), the only mode that grounds' {
        InModuleScope PacCopilotKit { Assert-PckAgentAuthMode -Agent 2 }
    }

    It 'passes an agent object from Get-PckAgentInfo' {
        InModuleScope PacCopilotKit {
            Assert-PckAgentAuthMode -Agent ([pscustomobject]@{ AuthenticationMode = 2 })
        }
    }

    It 'refuses None with exit code 18 and names the silent failure' {
        $err = { InModuleScope PacCopilotKit { Assert-PckAgentAuthMode -Agent 1 } } |
            Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 18
        $err.Exception.Message | Should -Match 'never be queried'
    }

    It 'refuses every other verified mode' {
        foreach ($mode in @(0, 3, 4)) {
            $err = { InModuleScope PacCopilotKit -Parameters @{ m = $mode } { param($m) Assert-PckAgentAuthMode -Agent $m } } |
                Should -Throw -PassThru
            $err.Exception.ExitCode | Should -Be 18
        }
    }

    It 'refuses an unparseable mode rather than passing it' {
        $err = { InModuleScope PacCopilotKit { Assert-PckAgentAuthMode -Agent 'garbage' } } |
            Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 18
    }

    It 'rejects an object with no authentication mode property at all' {
        { InModuleScope PacCopilotKit { Assert-PckAgentAuthMode -Agent ([pscustomobject]@{ Foo = 1 }) } } |
            Should -Throw -ExpectedMessage '*AuthenticationMode property*'
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

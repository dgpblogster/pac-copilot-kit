#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

<#
Adversarial suite. Each test attacks the module the way a hostile or careless
caller would, rather than the way the happy-path tests do. A guard that can be
bypassed by respelling the same request is not a guard; these tests exist to
prove the bypasses are closed and keep them closed.
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' '..' 'src' 'PacCopilotKit' 'PacCopilotKit.psd1'
    Import-Module $modulePath -Force
}

Describe 'Savedquery guard bypass attempts (war story 1 must hold)' {
    BeforeAll {
        InModuleScope PacCopilotKit {
            $script:PckContext = [pscustomobject]@{
                EnvironmentId  = '11111111-1111-1111-1111-111111111111'
                EnvironmentUrl = 'https://unit.test.invalid'
                AuthMode       = 'Dev'
                ConnectedAt    = Get-Date
                UserId         = $null
                OrganizationId = $null
            }
            $script:PckToken = @{ AccessToken = 'unit-token'; ExpiresOn = (Get-Date).AddHours(1) }
        }
    }
    AfterAll {
        InModuleScope PacCopilotKit {
            $script:PckContext = $null
            $script:PckToken = $null
        }
    }
    BeforeEach {
        Mock -ModuleName PacCopilotKit Invoke-WebRequest {
            [pscustomobject]@{ StatusCode = 204; Content = ''; Headers = @{} }
        }
    }

    It 'is not bypassed by an absolute URL spelling of the same request' {
        $err = {
            InModuleScope PacCopilotKit {
                Invoke-PckDataverseRequest -Method Patch `
                    -Path 'https://unit.test.invalid/api/data/v9.2/savedqueries(aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee)' `
                    -Body @{ fetchxml = '<fetch/>' } -SolutionName 'UnitSolution'
            }
        } | Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 20
        Should -Invoke -ModuleName PacCopilotKit Invoke-WebRequest -Times 0 -Exactly
    }

    It 'is not bypassed by a leading slash on the path' {
        $err = {
            InModuleScope PacCopilotKit {
                Invoke-PckDataverseRequest -Method Patch `
                    -Path '/savedqueries(aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee)' `
                    -Body @{ fetchxml = '<fetch/>' } -SolutionName 'UnitSolution'
            }
        } | Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 20
        Should -Invoke -ModuleName PacCopilotKit Invoke-WebRequest -Times 0 -Exactly
    }

    It 'is not bypassed by delivering fetchxml as a raw JSON string body' {
        $err = {
            InModuleScope PacCopilotKit {
                Invoke-PckDataverseRequest -Method Patch `
                    -Path 'savedqueries(aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee)' `
                    -Body '{"fetchxml":"<fetch/>"}' -SolutionName 'UnitSolution'
            }
        } | Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 20
        Should -Invoke -ModuleName PacCopilotKit Invoke-WebRequest -Times 0 -Exactly
    }

    It 'is not bypassed by a query string appended to the single-property route' {
        $err = {
            InModuleScope PacCopilotKit {
                Invoke-PckDataverseRequest -Method Put `
                    -Path 'savedqueries(aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee)/fetchxml?anything=1' `
                    -Body '<fetch/>' -SolutionName 'UnitSolution'
            }
        } | Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 20
        Should -Invoke -ModuleName PacCopilotKit Invoke-WebRequest -Times 0 -Exactly
    }

    It 'still allows the legitimate layoutxml update via absolute URL' {
        InModuleScope PacCopilotKit {
            Invoke-PckDataverseRequest -Method Patch `
                -Path 'https://unit.test.invalid/api/data/v9.2/savedqueries(aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee)' `
                -Body @{ layoutxml = '<grid/>' } -SolutionName 'UnitSolution'
        }
        Should -Invoke -ModuleName PacCopilotKit Invoke-WebRequest -Times 1 -Exactly
    }
}

Describe 'Output contracts under hostile emptiness' {
    It 'emits an empty JSON array, not [null], when no agents exist (canon 8)' {
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            [pscustomobject]@{ value = @() }
        }
        $json = Get-PckAgentInfo -Json
        $json.Trim() | Should -Be '[]'
    }

    It 'emits an empty JSON array when the filter matches nothing' {
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            [pscustomobject]@{
                value = @(
                    [pscustomobject]@{
                        botid = 'aaaaaaaa-0000-0000-0000-000000000001'
                        name = 'Support Assistant'; schemaname = 'wrk_SupportAssistant'
                        template = 'default-2.1.0'
                    }
                )
            }
        }
        (Get-PckAgentInfo -Name 'no-such-agent' -Json).Trim() | Should -Be '[]'
    }

    It 'returns a genuinely empty pipeline without -Json' {
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            [pscustomobject]@{ value = @() }
        }
        @(Get-PckAgentInfo).Count | Should -Be 0
    }
}

Describe 'Connect-PckPowerPlatform hostile inputs' {
    AfterEach {
        InModuleScope PacCopilotKit {
            $script:PckContext = $null
            $script:PckToken = $null
        }
    }

    It 'refuses a plain-http environment URL rather than sending a bearer token over it' {
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            [pscustomobject]@{ UserId = 'u'; OrganizationId = 'o' }
        }
        $err = {
            Connect-PckPowerPlatform `
                -EnvironmentId '11111111-1111-1111-1111-111111111111' `
                -EnvironmentUrl 'http://unit.test.invalid'
        } | Should -Throw -PassThru
        $err.Exception.Message | Should -Match 'https'
        Should -Invoke -ModuleName PacCopilotKit Invoke-PckDataverseRequest -Times 0 -Exactly
    }

    It 'discards the cached context when WhoAmI verification fails' {
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            throw [PckError]::new('Dataverse request failed: unit-test refusal', 1)
        }
        {
            Connect-PckPowerPlatform `
                -EnvironmentId '11111111-1111-1111-1111-111111111111' `
                -EnvironmentUrl 'https://unit.test.invalid'
        } | Should -Throw
        InModuleScope PacCopilotKit { $script:PckContext } | Should -BeNullOrEmpty
    }
}

Describe 'Harness guard hostile inputs' {
    It 'refuses a null template rather than passing it' {
        $err = {
            InModuleScope PacCopilotKit {
                Assert-PckAgentHarness -Agent ([pscustomobject]@{ Template = $null })
            }
        } | Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 14
    }

    It 'refuses an empty-string template rather than passing it' {
        $err = { InModuleScope PacCopilotKit { Assert-PckAgentHarness -Agent ([pscustomobject]@{ Template = '' }) } } |
            Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 14
    }

    It 'is not fooled by a template that merely contains default' {
        $err = { InModuleScope PacCopilotKit { Assert-PckAgentHarness -Agent 'not-default-2.1.0' } } |
            Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 14
    }
}

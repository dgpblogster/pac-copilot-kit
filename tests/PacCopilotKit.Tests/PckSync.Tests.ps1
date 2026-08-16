#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' '..' 'src' 'PacCopilotKit' 'PacCopilotKit.psd1'
    Import-Module $modulePath -Force

    $script:envId = '11111111-1111-1111-1111-111111111111'
    $script:banner = @('Microsoft PowerPlatform CLI', 'Version: 2.10.1+g52c3983')
    $script:alignedWho = @("  Environment ID:             $script:envId")
}

Describe 'Sync-PckCopilotAgent' {
    BeforeEach {
        InModuleScope PacCopilotKit {
            $script:PckContext = [pscustomobject]@{
                EnvironmentId  = '11111111-1111-1111-1111-111111111111'
                EnvironmentUrl = 'https://unit.test.invalid'
                AuthMode       = 'Dev'
                ConnectedAt    = Get-Date
                UserId         = 'u'
                OrganizationId = 'o'
            }
            $script:PckToken = @{ AccessToken = 'unit-token'; ExpiresOn = (Get-Date).AddHours(1) }
        }
        $script:src = Join-Path $TestDrive "sync-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:src | Out-Null

        Mock -ModuleName PacCopilotKit Invoke-PckPacCommand {
            switch ("$($Arguments[0]) $($Arguments[1])") {
                'help '        { return $script:banner }
                'org who'      { return $script:alignedWho }
                'copilot pull' { return @('Pulled 3 files.') }
            }
        }
    }
    AfterEach {
        InModuleScope PacCopilotKit {
            $script:PckContext = $null
            $script:PckToken = $null
        }
    }

    It 'pulls with an explicit project dir after the guardrails pass' {
        $result = Sync-PckCopilotAgent -SourcePath $script:src -EnvironmentId $script:envId
        $result.Succeeded | Should -BeTrue
        Should -Invoke -ModuleName PacCopilotKit Invoke-PckPacCommand -Times 1 -Exactly -ParameterFilter {
            $Arguments[0] -eq 'copilot' -and $Arguments[1] -eq 'pull' -and
            $Arguments -contains '--project-dir' -and $Arguments -contains $script:src -and
            $WorkingDirectory -eq $script:src
        }
    }

    It 'refuses on a drifted profile before pulling anything (canon 4)' {
        Mock -ModuleName PacCopilotKit Invoke-PckPacCommand {
            switch ("$($Arguments[0]) $($Arguments[1])") {
                'help '   { return $script:banner }
                'org who' { return @('  Environment ID:             99999999-9999-9999-9999-999999999999') }
            }
        }
        $err = { Sync-PckCopilotAgent -SourcePath $script:src -EnvironmentId $script:envId } |
            Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 16
        Should -Invoke -ModuleName PacCopilotKit Invoke-PckPacCommand -Times 0 -Exactly -ParameterFilter {
            $Arguments[0] -eq 'copilot'
        }
    }

    It 'refuses a missing source path before any pac call' {
        { Sync-PckCopilotAgent -SourcePath (Join-Path $TestDrive 'nope') -EnvironmentId $script:envId } |
            Should -Throw -ExpectedMessage '*does not exist*'
        Should -Invoke -ModuleName PacCopilotKit Invoke-PckPacCommand -Times 0 -Exactly
    }
}

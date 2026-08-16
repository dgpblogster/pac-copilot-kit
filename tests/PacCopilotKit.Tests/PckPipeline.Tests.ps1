#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' '..' 'src' 'PacCopilotKit' 'PacCopilotKit.psd1'
    Import-Module $modulePath -Force

    $script:envId = '11111111-1111-1111-1111-111111111111'
    $script:alignedWho = @(
        '  Org URL:                    https://unit.test.invalid/'
        "  Environment ID:             $script:envId"
    )
    $script:banner = @('Microsoft PowerPlatform CLI', 'Version: 2.10.1+g52c3983')
}

Describe 'Invoke-PckCopilotPipeline' {
    BeforeEach {
        # A connected session pinned at the test environment.
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

        # Workspace with one clean file and a pre-created pack output.
        $script:src = Join-Path $TestDrive "ws-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:src | Out-Null
        Set-Content -Path (Join-Path $script:src 'agent.mcs.yml') -Value 'kind: Agent'
        Set-Content -Path (Join-Path $script:src 'UnitSolution.zip') -Value 'fake zip'

        Mock -ModuleName PacCopilotKit Invoke-PckPacCommand {
            switch ("$($Arguments[0]) $($Arguments[1])") {
                'help '          { return $script:banner }
                'org who'        { return $script:alignedWho }
                default          { return @() }
            }
        }

        $script:savedEnv = @{}
        foreach ($name in @('PCK_SPN_TENANT', 'PCK_SPN_APP_ID', 'PCK_SPN_SECRET')) {
            $script:savedEnv[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
    }
    AfterEach {
        foreach ($kv in $script:savedEnv.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($kv.Key, $kv.Value)
        }
        InModuleScope PacCopilotKit {
            $script:PckContext = $null
            $script:PckToken = $null
        }
    }

    It 'runs the full loop in order and reports every step' {
        $result = Invoke-PckCopilotPipeline -SolutionName UnitSolution -SourcePath $script:src `
            -PublisherPrefix wrk -EnvironmentId $script:envId

        $result.Succeeded | Should -BeTrue
        @($result.Steps).Step | Should -Be @('connect', 'pac-version', 'pac-auth', 'validate', 'pack', 'import')
        @($result.Steps).Status | Should -Not -Contain 'whatif'

        Should -Invoke -ModuleName PacCopilotKit Invoke-PckPacCommand -Times 1 -Exactly -ParameterFilter {
            $Arguments[0] -eq 'copilot' -and $Arguments[1] -eq 'pack' -and
            $Arguments -contains '--publisher-prefix' -and $Arguments -contains 'wrk' -and
            $WorkingDirectory -eq $script:src
        }
        Should -Invoke -ModuleName PacCopilotKit Invoke-PckPacCommand -Times 1 -Exactly -ParameterFilter {
            $Arguments[0] -eq 'solution' -and $Arguments[1] -eq 'import' -and
            $Arguments -contains '--publish-changes' -and
            $Arguments -contains (Join-Path $script:src 'UnitSolution.zip')
        }
    }

    It 'runs nothing mutating under -WhatIf and says what it would have done' {
        $result = Invoke-PckCopilotPipeline -SolutionName UnitSolution -SourcePath $script:src `
            -PublisherPrefix wrk -EnvironmentId $script:envId -WhatIf

        @($result.Steps | Where-Object Step -in @('pack', 'import')).Status | Should -Be @('whatif', 'whatif')
        Should -Invoke -ModuleName PacCopilotKit Invoke-PckPacCommand -Times 0 -Exactly -ParameterFilter {
            $Arguments[0] -in @('copilot', 'solution', 'auth')
        }
    }

    It 'stops on lint issues before pack ever runs, listing the finding' {
        Set-Content -Path (Join-Path $script:src 'bad.mcs.yml') -Value 'condition: =Concatenate(A, ": ", B)'
        $err = {
            Invoke-PckCopilotPipeline -SolutionName UnitSolution -SourcePath $script:src `
                -PublisherPrefix wrk -EnvironmentId $script:envId
        } | Should -Throw -PassThru
        $err.Exception.Message | Should -Match 'PowerFxColonSpace'
        $err.Exception.Message | Should -Match 'Nothing was deployed'
        Should -Invoke -ModuleName PacCopilotKit Invoke-PckPacCommand -Times 0 -Exactly -ParameterFilter {
            $Arguments[0] -eq 'copilot'
        }
    }

    It 'stops on a pac below the floor before anything else runs' {
        Mock -ModuleName PacCopilotKit Invoke-PckPacCommand {
            if ($Arguments[0] -eq 'help') { return @('Microsoft PowerPlatform CLI', 'Version: 2.9.0+g1') }
            return @()
        }
        $err = {
            Invoke-PckCopilotPipeline -SolutionName UnitSolution -SourcePath $script:src `
                -PublisherPrefix wrk -EnvironmentId $script:envId
        } | Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 13
        Should -Invoke -ModuleName PacCopilotKit Invoke-PckPacCommand -Times 0 -Exactly -ParameterFilter {
            $Arguments[0] -in @('org', 'copilot', 'solution')
        }
    }

    It 'stops on a drifted profile before pack or import run (canon 4)' {
        Mock -ModuleName PacCopilotKit Invoke-PckPacCommand {
            switch ("$($Arguments[0]) $($Arguments[1])") {
                'help '   { return $script:banner }
                'org who' { return @('  Environment ID:             99999999-9999-9999-9999-999999999999') }
                default   { return @() }
            }
        }
        $err = {
            Invoke-PckCopilotPipeline -SolutionName UnitSolution -SourcePath $script:src `
                -PublisherPrefix wrk -EnvironmentId $script:envId
        } | Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 16
        Should -Invoke -ModuleName PacCopilotKit Invoke-PckPacCommand -Times 0 -Exactly -ParameterFilter {
            $Arguments[0] -in @('copilot', 'solution')
        }
    }

    It 'refuses a hostile solution name before pac sees a single argument' {
        $err = {
            Invoke-PckCopilotPipeline -SolutionName 'x; del *' -SourcePath $script:src `
                -PublisherPrefix wrk -EnvironmentId $script:envId
        } | Should -Throw -PassThru
        $err.Exception.Message | Should -Match 'not a valid solution unique name'
        Should -Invoke -ModuleName PacCopilotKit Invoke-PckPacCommand -Times 0 -Exactly
    }

    It 'refuses a hostile publisher prefix likewise' {
        {
            Invoke-PckCopilotPipeline -SolutionName UnitSolution -SourcePath $script:src `
                -PublisherPrefix 'w r k' -EnvironmentId $script:envId
        } | Should -Throw -ExpectedMessage '*not valid*'
        Should -Invoke -ModuleName PacCopilotKit Invoke-PckPacCommand -Times 0 -Exactly
    }

    Context 'CI mode' {
        BeforeEach {
            $env:PCK_SPN_TENANT = '22222222-2222-2222-2222-222222222222'
            $env:PCK_SPN_APP_ID = '33333333-3333-3333-3333-333333333333'
            $env:PCK_SPN_SECRET = 'UNIT-SUPERSECRET-VALUE'
        }

        It 'creates the temporary profile as sensitive and deletes it after success' {
            Invoke-PckCopilotPipeline -SolutionName UnitSolution -SourcePath $script:src `
                -PublisherPrefix wrk -EnvironmentId $script:envId | Out-Null

            Should -Invoke -ModuleName PacCopilotKit Invoke-PckPacCommand -Times 1 -Exactly -ParameterFilter {
                $Arguments[0] -eq 'auth' -and $Arguments[1] -eq 'create' -and $Sensitive -eq $true
            }
            Should -Invoke -ModuleName PacCopilotKit Invoke-PckPacCommand -Times 1 -Exactly -ParameterFilter {
                $Arguments[0] -eq 'auth' -and $Arguments[1] -eq 'delete'
            }
            # CI mode never consults the dev profile.
            Should -Invoke -ModuleName PacCopilotKit Invoke-PckPacCommand -Times 0 -Exactly -ParameterFilter {
                $Arguments[0] -eq 'org' -and $Arguments[1] -eq 'who'
            }
        }

        It 'still deletes the temporary profile when the import fails, and leaks no secret' {
            Mock -ModuleName PacCopilotKit Invoke-PckPacCommand {
                switch ("$($Arguments[0]) $($Arguments[1])") {
                    'help '           { return $script:banner }
                    'solution import' { throw 'pac exited with code 1. Command: pac solution import' }
                    default           { return @() }
                }
            }
            $err = {
                Invoke-PckCopilotPipeline -SolutionName UnitSolution -SourcePath $script:src `
                    -PublisherPrefix wrk -EnvironmentId $script:envId
            } | Should -Throw -PassThru

            $err.Exception.Message | Should -Not -Match 'UNIT-SUPERSECRET-VALUE'
            Should -Invoke -ModuleName PacCopilotKit Invoke-PckPacCommand -Times 1 -Exactly -ParameterFilter {
                $Arguments[0] -eq 'auth' -and $Arguments[1] -eq 'delete'
            }
        }
    }
}

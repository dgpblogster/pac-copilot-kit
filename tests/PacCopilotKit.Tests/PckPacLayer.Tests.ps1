#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' '..' 'src' 'PacCopilotKit' 'PacCopilotKit.psd1'
    Import-Module $modulePath -Force
}

Describe 'Assert-PckPacVersion (war story 6)' {
    # Banner shape verified live 2026-08-16: 'Version: 2.10.1+g52c3983'.
    It 'passes a version at the floor' {
        Mock -ModuleName PacCopilotKit Invoke-PckPacCommand {
            @('Microsoft PowerPlatform CLI', 'Version: 2.10.1+g52c3983 (.NET Framework 4.8.9337.0)')
        }
        InModuleScope PacCopilotKit { Assert-PckPacVersion }
    }

    It 'refuses a version below the floor with exit code 13' {
        Mock -ModuleName PacCopilotKit Invoke-PckPacCommand {
            @('Microsoft PowerPlatform CLI', 'Version: 2.9.9+gabc (.NET)')
        }
        $err = { InModuleScope PacCopilotKit { Assert-PckPacVersion } } | Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 13
        $err.Exception.Message | Should -Match '2\.9\.9'
    }

    It 'refuses an unreadable banner rather than guessing' {
        Mock -ModuleName PacCopilotKit Invoke-PckPacCommand { @('something unexpected entirely') }
        $err = { InModuleScope PacCopilotKit { Assert-PckPacVersion } } | Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 13
    }
}

Describe 'Assert-PckProfileAligned (war story 6)' {
    # Output shape verified live 2026-08-16: 'Environment ID:' and 'Org URL:' lines.
    BeforeAll {
        $script:alignedWho = @(
            'Connected as user@unit.test'
            'Organization Information'
            '  Org ID:                     99999999-9999-9999-9999-999999999999'
            '  Org URL:                    https://unitorg.crm.dynamics.com/'
            '  Environment ID:             11111111-1111-1111-1111-111111111111'
        )
    }

    It 'passes when the active profile points at the pinned environment' {
        Mock -ModuleName PacCopilotKit Invoke-PckPacCommand { $script:alignedWho }
        InModuleScope PacCopilotKit {
            Assert-PckProfileAligned -EnvironmentId '11111111-1111-1111-1111-111111111111'
        }
    }

    It 'passes on an org URL match when the environment id line is absent' {
        Mock -ModuleName PacCopilotKit Invoke-PckPacCommand {
            @('  Org URL:                    https://unitorg.crm.dynamics.com/')
        }
        InModuleScope PacCopilotKit {
            Assert-PckProfileAligned -EnvironmentId '11111111-1111-1111-1111-111111111111' `
                -EnvironmentUrl 'https://unitorg.crm.dynamics.com'
        }
    }

    It 'refuses a drifted profile with exit code 16, naming both environments' {
        Mock -ModuleName PacCopilotKit Invoke-PckPacCommand { $script:alignedWho }
        $err = {
            InModuleScope PacCopilotKit {
                Assert-PckProfileAligned -EnvironmentId '22222222-2222-2222-2222-222222222222'
            }
        } | Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 16
        $err.Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
        $err.Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
        $err.Exception.Message | Should -Match 'canon 4'
    }

    It 'refuses when no profile answers at all' {
        Mock -ModuleName PacCopilotKit Invoke-PckPacCommand { throw 'pac exited with code 1. Command: pac org who' }
        $err = {
            InModuleScope PacCopilotKit {
                Assert-PckProfileAligned -EnvironmentId '22222222-2222-2222-2222-222222222222'
            }
        } | Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 16
        $err.Exception.Message | Should -Match 'pac auth create'
    }

    It 'is not fooled by the target id appearing somewhere other than the Environment ID line' {
        Mock -ModuleName PacCopilotKit Invoke-PckPacCommand {
            @('  Org ID:                     22222222-2222-2222-2222-222222222222'
              '  Environment ID:             11111111-1111-1111-1111-111111111111')
        }
        $err = {
            InModuleScope PacCopilotKit {
                Assert-PckProfileAligned -EnvironmentId '22222222-2222-2222-2222-222222222222'
            }
        } | Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 16
    }
}

Describe 'Test-PckAgentWorkspace' {
    It 'returns no issues for a clean workspace' {
        $dir = Join-Path $TestDrive 'clean'
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-Content -Path (Join-Path $dir 'agent.mcs.yml') -Value @(
            'kind: Agent'
            'displayName: Unit Agent'
            'instructions: |'
            '  Answer from: the knowledge sources only.'
            "prompt: '=If(A, `"x: y`", B)'"
            'plain: =Concatenate(A, B)'
        )
        $issues = InModuleScope PacCopilotKit -Parameters @{ p = $dir } { param($p) @(Test-PckAgentWorkspace -Path $p) }
        $issues.Count | Should -Be 0
    }

    It 'flags an unquoted Power Fx value containing colon-space, with its line number' {
        $dir = Join-Path $TestDrive 'powerfx'
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-Content -Path (Join-Path $dir 'topic.mcs.yml') -Value @(
            'kind: Topic'
            'condition: =If(Topic.x, "yes", Concatenate(A, ": ", B))'
        )
        $issues = InModuleScope PacCopilotKit -Parameters @{ p = $dir } { param($p) @(Test-PckAgentWorkspace -Path $p) }
        $issues.Count | Should -Be 1
        $issues[0].Rule | Should -Be 'PowerFxColonSpace'
        $issues[0].Line | Should -Be 2
    }

    It 'flags tab indentation' {
        $dir = Join-Path $TestDrive 'tabs'
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-Content -Path (Join-Path $dir 'settings.mcs.yml') -Value "kind: Settings`n`tname: tabbed"
        $issues = InModuleScope PacCopilotKit -Parameters @{ p = $dir } { param($p) @(Test-PckAgentWorkspace -Path $p) }
        @($issues | Where-Object Rule -eq 'TabIndentation').Count | Should -Be 1
    }

    It 'flags a folder with no workspace files at all' {
        $dir = Join-Path $TestDrive 'empty'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $issues = InModuleScope PacCopilotKit -Parameters @{ p = $dir } { param($p) @(Test-PckAgentWorkspace -Path $p) }
        $issues[0].Rule | Should -Be 'Workspace'
    }
}

Describe 'Invoke-PckPacCommand against a real (fake) executable' {
    BeforeAll {
        # A stand-in pac that echoes its arguments and fails, which is exactly
        # what an attacker wants a secret-carrying command to do.
        $script:fakePacDir = Join-Path $TestDrive 'fakepac'
        New-Item -ItemType Directory -Path $script:fakePacDir | Out-Null
        $script:fakeFailPath = Join-Path $script:fakePacDir 'pacfail.cmd'
        Set-Content -Path $script:fakeFailPath -Value "@echo off`r`necho ARGS: %*`r`nexit /b 7"
        $script:fakeOkPath = Join-Path $script:fakePacDir 'pacok.cmd'
        Set-Content -Path $script:fakeOkPath -Value "@echo off`r`necho line-one`r`necho line-two`r`nexit /b 0"
    }

    It 'returns output lines on success' {
        Mock -ModuleName PacCopilotKit Get-Command { Microsoft.PowerShell.Core\Get-Command $script:fakeOkPath } -ParameterFilter { $Name -eq 'pac' }
        $out = InModuleScope PacCopilotKit { Invoke-PckPacCommand -Arguments @('anything') }
        @($out) | Should -Contain 'line-one'
    }

    It 'throws with the exit code and output tail on failure' {
        Mock -ModuleName PacCopilotKit Get-Command { Microsoft.PowerShell.Core\Get-Command $script:fakeFailPath } -ParameterFilter { $Name -eq 'pac' }
        $err = { InModuleScope PacCopilotKit { Invoke-PckPacCommand -Arguments @('solution', 'import') } } |
            Should -Throw -PassThru
        $err.Exception.Message | Should -Match 'code 7'
        $err.Exception.Message | Should -Match 'ARGS: solution import'
    }

    It 'never leaks a secret through arguments or echoed output when -Sensitive' {
        Mock -ModuleName PacCopilotKit Get-Command { Microsoft.PowerShell.Core\Get-Command $script:fakeFailPath } -ParameterFilter { $Name -eq 'pac' }
        $err = {
            InModuleScope PacCopilotKit {
                Invoke-PckPacCommand -Sensitive -Arguments @('auth', 'create', '--clientSecret', 'SUPERSECRET-VALUE')
            }
        } | Should -Throw -PassThru
        $err.Exception.Message | Should -Not -Match 'SUPERSECRET'
        $err.Exception.Message | Should -Match 'withheld'
        $err.Exception.Message | Should -Match 'code 7'
    }

    It 'does not believe a zero exit code when pac printed an Error: line (war story 7)' {
        # Observed live 2026-08-16, three times in one session: pac exits 0 on
        # argument and validation errors while printing 'Error: ...'.
        $liar = Join-Path $script:fakePacDir 'pacliar.cmd'
        Set-Content -Path $liar -Value "@echo off`r`necho Error: A required argument --name is missing.`r`nexit /b 0"
        Mock -ModuleName PacCopilotKit Get-Command { Microsoft.PowerShell.Core\Get-Command (Join-Path $script:fakePacDir 'pacliar.cmd') } -ParameterFilter { $Name -eq 'pac' }
        $err = { InModuleScope PacCopilotKit { Invoke-PckPacCommand -Arguments @('copilot', 'init') } } |
            Should -Throw -PassThru
        $err.Exception.Message | Should -Match 'Error:'
        $err.Exception.Message | Should -Match 'exit code was 0'
    }

    It 'withholds even the lying output when the command was sensitive' {
        $liar = Join-Path $script:fakePacDir 'pacliar2.cmd'
        Set-Content -Path $liar -Value "@echo off`r`necho Error: bad secret SUPERSECRET-VALUE`r`nexit /b 0"
        Mock -ModuleName PacCopilotKit Get-Command { Microsoft.PowerShell.Core\Get-Command (Join-Path $script:fakePacDir 'pacliar2.cmd') } -ParameterFilter { $Name -eq 'pac' }
        $err = { InModuleScope PacCopilotKit { Invoke-PckPacCommand -Sensitive -Arguments @('auth', 'create') } } |
            Should -Throw -PassThru
        $err.Exception.Message | Should -Not -Match 'SUPERSECRET'
        $err.Exception.Message | Should -Match 'withheld'
    }

    It 'refuses with exit code 13 when pac is not on the PATH at all' {
        Mock -ModuleName PacCopilotKit Get-Command { $null } -ParameterFilter { $Name -eq 'pac' }
        $err = { InModuleScope PacCopilotKit { Invoke-PckPacCommand -Arguments @('help') } } |
            Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 13
    }
}

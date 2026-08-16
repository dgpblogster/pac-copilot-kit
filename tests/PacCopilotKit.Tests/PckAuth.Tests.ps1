#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' '..' 'src' 'PacCopilotKit' 'PacCopilotKit.psd1'
    Import-Module $modulePath -Force
}

Describe 'Resolve-PckEnvironmentId' {
    BeforeEach {
        $script:savedEnv = @{}
        foreach ($name in @('PCK_DEFAULT_ENVIRONMENT_ID')) {
            $script:savedEnv[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
    }
    AfterEach {
        foreach ($kv in $script:savedEnv.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($kv.Key, $kv.Value)
        }
    }

    It 'prefers the parameter over the environment variable' {
        $env:PCK_DEFAULT_ENVIRONMENT_ID = '99999999-9999-9999-9999-999999999999'
        $result = InModuleScope PacCopilotKit {
            Resolve-PckEnvironmentId -EnvironmentId '11111111-1111-1111-1111-111111111111'
        }
        $result | Should -Be '11111111-1111-1111-1111-111111111111'
    }

    It 'falls back to PCK_DEFAULT_ENVIRONMENT_ID' {
        $env:PCK_DEFAULT_ENVIRONMENT_ID = '99999999-9999-9999-9999-999999999999'
        $result = InModuleScope PacCopilotKit { Resolve-PckEnvironmentId -EnvironmentId '' }
        $result | Should -Be '99999999-9999-9999-9999-999999999999'
    }

    It 'hard-errors with exit code 10 when neither is set (canon 4)' {
        $err = { InModuleScope PacCopilotKit { Resolve-PckEnvironmentId -EnvironmentId '' } } |
            Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 10
        $err.Exception.Message | Should -Match 'canon 4'
    }

    It 'rejects a non-GUID value with exit code 10' {
        $err = { InModuleScope PacCopilotKit { Resolve-PckEnvironmentId -EnvironmentId 'not-a-guid' } } |
            Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 10
    }
}

Describe 'Get-PckAccessToken' {
    BeforeEach {
        $script:savedEnv = @{}
        foreach ($name in @('PCK_ACCESS_TOKEN', 'PCK_SPN_TENANT', 'PCK_SPN_APP_ID', 'PCK_SPN_SECRET')) {
            $script:savedEnv[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
    }
    AfterEach {
        foreach ($kv in $script:savedEnv.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($kv.Key, $kv.Value)
        }
    }

    It 'uses CI mode when all three PCK_SPN_* variables are set' {
        $env:PCK_SPN_TENANT = '22222222-2222-2222-2222-222222222222'
        $env:PCK_SPN_APP_ID = '33333333-3333-3333-3333-333333333333'
        $env:PCK_SPN_SECRET = 'unit-test-secret'

        Mock -ModuleName PacCopilotKit Invoke-RestMethod {
            [pscustomobject]@{ access_token = 'spn-token'; expires_in = 3600 }
        }

        $result = InModuleScope PacCopilotKit { Get-PckAccessToken -Resource 'https://unit.crm.dynamics.com' }
        $result.AccessToken | Should -Be 'spn-token'

        Should -Invoke -ModuleName PacCopilotKit Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -like 'https://login.microsoftonline.com/22222222-*' -and
            $Body.scope -eq 'https://unit.crm.dynamics.com/.default'
        }
    }

    It 'refuses an incomplete PCK_SPN_* set with exit code 11' {
        $env:PCK_SPN_TENANT = '22222222-2222-2222-2222-222222222222'
        $err = { InModuleScope PacCopilotKit { Get-PckAccessToken -Resource 'https://unit.crm.dynamics.com' } } |
            Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 11
    }

    It 'prefers PCK_ACCESS_TOKEN over every other dev source' {
        # A syntactically valid JWT whose exp claim is one hour out.
        $exp = [DateTimeOffset]::Now.AddHours(1).ToUnixTimeSeconds()
        $payload = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("{`"exp`":$exp}")).TrimEnd('=')
        $env:PCK_ACCESS_TOKEN = "eyJhbGciOiJub25lIn0.$payload."

        $result = InModuleScope PacCopilotKit { Get-PckAccessToken -Resource 'https://unit.crm.dynamics.com' }
        $result.AccessToken | Should -Be $env:PCK_ACCESS_TOKEN
        $result.ExpiresOn | Should -BeGreaterThan (Get-Date).AddMinutes(50)
    }

    It 'hard-errors with exit code 11 when no source is available' {
        Mock -ModuleName PacCopilotKit Get-Command { $null }
        Mock -ModuleName PacCopilotKit Get-Module { $null }

        $err = { InModuleScope PacCopilotKit { Get-PckAccessToken -Resource 'https://unit.crm.dynamics.com' } } |
            Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 11
        $err.Exception.Message | Should -Match 'PCK_ACCESS_TOKEN'
    }
}

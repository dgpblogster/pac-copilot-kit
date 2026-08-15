#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' '..' 'src' 'PacCopilotKit' 'PacCopilotKit.psd1'
    Import-Module $modulePath -Force

    $script:payload = [byte[]]@(0x50, 0x4B, 0x03, 0x04, 0xAA, 0xBB)
    $script:payloadBase64 = [Convert]::ToBase64String($script:payload)
}

Describe 'Export-PckSolutionBackup' {
    BeforeEach {
        $script:savedRoot = $env:PCK_WORKSPACE_ROOT
        $env:PCK_WORKSPACE_ROOT = $null
        # Mock bodies execute in this file's scope, so $script: here refers to the
        # test file, not the module. Learned the hard way; do not re-mock per test
        # with module-scope variables.
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            [pscustomobject]@{ ExportSolutionFile = $script:payloadBase64 }
        }
    }
    AfterEach {
        $env:PCK_WORKSPACE_ROOT = $script:savedRoot
    }

    It 'writes a timestamp-suffixed zip and reports it' {
        $result = Export-PckSolutionBackup -SolutionName UnitSolution -Path $TestDrive

        $result.Path | Should -Match 'UnitSolution-\d{8}-\d{6}\.zip$'
        $result.Bytes | Should -Be 6
        [System.IO.File]::ReadAllBytes($result.Path) | Should -Be $script:payload
    }

    It 'passes Managed through to ExportSolution and marks the filename' {
        $result = Export-PckSolutionBackup -SolutionName UnitSolution -Path $TestDrive -Managed

        $result.Path | Should -Match '-managed\.zip$'
        Should -Invoke -ModuleName PacCopilotKit Invoke-PckDataverseRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'Post' -and $Path -eq 'ExportSolution' -and $Body.Managed -eq $true
        }
    }

    It 'resolves a relative path against PCK_WORKSPACE_ROOT (design 5.7)' {
        $env:PCK_WORKSPACE_ROOT = $TestDrive
        $result = Export-PckSolutionBackup -SolutionName UnitSolution -Path 'backups'

        $result.Path | Should -BeLike (Join-Path $TestDrive 'backups' '*')
        Test-Path $result.Path | Should -BeTrue
    }

    It 'refuses a relative path with no workspace root, exit code 17' {
        $err = { Export-PckSolutionBackup -SolutionName UnitSolution -Path 'backups' } |
            Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 17
        Should -Invoke -ModuleName PacCopilotKit Invoke-PckDataverseRequest -Times 0 -Exactly
    }

    It 'refuses a solution name that could traverse a path, before any network call' {
        $err = { Export-PckSolutionBackup -SolutionName '..\evil' -Path $TestDrive } |
            Should -Throw -PassThru
        $err.Exception.Message | Should -Match 'not a valid solution unique name'
        Should -Invoke -ModuleName PacCopilotKit Invoke-PckDataverseRequest -Times 0 -Exactly
    }

    It 'fails loudly when ExportSolution returns no payload' {
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            [pscustomobject]@{ ExportSolutionFile = '' }
        }
        { Export-PckSolutionBackup -SolutionName UnitSolution -Path $TestDrive } |
            Should -Throw -ExpectedMessage '*no file payload*'
    }
}

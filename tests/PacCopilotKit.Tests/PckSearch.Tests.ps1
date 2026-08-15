#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' '..' 'src' 'PacCopilotKit' 'PacCopilotKit.psd1'
    Import-Module $modulePath -Force

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

Describe 'Enable-PckDataverseSearch' {
    It 'patches the org record when search is off, outside any solution' {
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            if ($Method -eq 'Get') {
                [pscustomobject]@{
                    value = @([pscustomobject]@{
                        organizationid                = 'bbbbbbbb-0000-0000-0000-000000000001'
                        isexternalsearchindexenabled  = $false
                    })
                }
            }
        }
        $result = Enable-PckDataverseSearch
        $result.AlreadyEnabled | Should -BeFalse
        $result.Enabled | Should -BeTrue

        Should -Invoke -ModuleName PacCopilotKit Invoke-PckDataverseRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'Patch' -and
            $Path -eq 'organizations(bbbbbbbb-0000-0000-0000-000000000001)' -and
            $Body.isexternalsearchindexenabled -eq $true -and
            $NoSolution -eq $true
        }
    }

    It 'is idempotent: an already-enabled org is reported, never re-patched (design 5.8)' {
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            [pscustomobject]@{
                value = @([pscustomobject]@{
                    organizationid                = 'bbbbbbbb-0000-0000-0000-000000000001'
                    isexternalsearchindexenabled  = $true
                })
            }
        }
        $result = Enable-PckDataverseSearch
        $result.AlreadyEnabled | Should -BeTrue

        Should -Invoke -ModuleName PacCopilotKit Invoke-PckDataverseRequest -Times 0 -Exactly -ParameterFilter {
            $Method -eq 'Patch'
        }
    }
}

Describe 'Wait-PckDataverseSearchReady' {
    It 'returns once a probe gets hits, and reports the attempt count' {
        # Mock bodies run in this file's scope; reset the counter here, not in the module.
        $script:probeCount = 0
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            $script:probeCount++
            if ($script:probeCount -ge 3) {
                [pscustomobject]@{ value = @([pscustomobject]@{ Name = 'hit' }) }
            }
            else {
                [pscustomobject]@{ value = @() }
            }
        }
        $result = Wait-PckDataverseSearchReady -Table wrk_caseresolution -SearchText 'scanner' -IntervalSeconds 0
        $result.Ready | Should -BeTrue
        $result.Attempts | Should -Be 3
        $result.Hits | Should -Be 1
    }

    It 'probes the query endpoint, never /status' {
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            [pscustomobject]@{ value = @([pscustomobject]@{ Name = 'hit' }) }
        }
        Wait-PckDataverseSearchReady -Table wrk_caseresolution -SearchText 'scanner' -IntervalSeconds 0 | Out-Null

        Should -Invoke -ModuleName PacCopilotKit Invoke-PckDataverseRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'Post' -and
            $Path -eq 'https://unit.test.invalid/api/search/v1.0/query' -and
            $Body.search -eq 'scanner' -and
            @($Body.entities) -contains 'wrk_caseresolution'
        }
        Should -Invoke -ModuleName PacCopilotKit Invoke-PckDataverseRequest -Times 0 -Exactly -ParameterFilter {
            $Path -like '*status*'
        }
    }

    It 'tolerates probe errors while the index provisions, instead of giving up' {
        $script:probeCount = 0
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            $script:probeCount++
            if ($script:probeCount -eq 1) {
                throw [PckError]::new('Dataverse request failed: index not provisioned', 1)
            }
            [pscustomobject]@{ value = @([pscustomobject]@{ Name = 'hit' }) }
        }
        $result = Wait-PckDataverseSearchReady -Table wrk_caseresolution -SearchText 'scanner' -IntervalSeconds 0
        $result.Ready | Should -BeTrue
        $result.Attempts | Should -Be 2
    }

    It 'times out with a diagnosis that names the usual suspects' {
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            [pscustomobject]@{ value = @() }
        }
        $err = {
            Wait-PckDataverseSearchReady -Table wrk_caseresolution -SearchText 'scanner' `
                -IntervalSeconds 0 -TimeoutMinutes 0
        } | Should -Throw -PassThru
        $err.Exception.Message | Should -Match 'find columns'
        $err.Exception.Message | Should -Match 'Enable-PckDataverseSearch'
    }

    It 'refuses when not connected, with exit code 15' {
        $err = {
            try {
                InModuleScope PacCopilotKit { $script:PckContext = $null }
                Wait-PckDataverseSearchReady -Table t -SearchText 's' -IntervalSeconds 0 -TimeoutMinutes 0
            }
            finally {
                InModuleScope PacCopilotKit {
                    $script:PckContext = [pscustomobject]@{
                        EnvironmentId  = '11111111-1111-1111-1111-111111111111'
                        EnvironmentUrl = 'https://unit.test.invalid'
                        AuthMode       = 'Dev'
                        ConnectedAt    = Get-Date
                        UserId         = $null
                        OrganizationId = $null
                    }
                }
            }
        } | Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 15
    }
}

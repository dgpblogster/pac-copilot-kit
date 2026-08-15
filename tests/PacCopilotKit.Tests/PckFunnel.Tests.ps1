#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' '..' 'src' 'PacCopilotKit' 'PacCopilotKit.psd1'
    Import-Module $modulePath -Force

    # Fabricate a connected session so funnel tests never touch the network.
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

Describe 'Invoke-PckDataverseRequest' {
    BeforeEach {
        Mock -ModuleName PacCopilotKit Invoke-WebRequest {
            [pscustomobject]@{ StatusCode = 200; Content = '{"value":[]}'; Headers = @{} }
        }
    }

    It 'refuses when not connected, with exit code 15' {
        $err = {
            InModuleScope PacCopilotKit {
                $saved = $script:PckContext
                $script:PckContext = $null
                try { Invoke-PckDataverseRequest -Method Get -Path 'WhoAmI' }
                finally { $script:PckContext = $saved }
            }
        } | Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 15
    }

    It 'refuses a mutating call without -SolutionName (canon 7)' {
        $err = {
            InModuleScope PacCopilotKit {
                Invoke-PckDataverseRequest -Method Post -Path 'dvtablesearchs' -Body @{ name = 'x' }
            }
        } | Should -Throw -PassThru
        $err.Exception.Message | Should -Match 'canon 7'
    }

    It 'stamps MSCRM.SolutionUniqueName on a mutating call' {
        InModuleScope PacCopilotKit {
            Invoke-PckDataverseRequest -Method Post -Path 'dvtablesearchs' `
                -Body @{ name = 'x' } -SolutionName 'UnitSolution'
        }
        Should -Invoke -ModuleName PacCopilotKit Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Headers['MSCRM.SolutionUniqueName'] -eq 'UnitSolution'
        }
    }

    It 'allows a deliberate non-solution mutation with -NoSolution' {
        InModuleScope PacCopilotKit {
            Invoke-PckDataverseRequest -Method Patch -Path 'organizations(11111111-1111-1111-1111-111111111111)' `
                -Body @{ isexternalsearchindexenabled = $true } -NoSolution
        }
        Should -Invoke -ModuleName PacCopilotKit Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            -not $Headers.ContainsKey('MSCRM.SolutionUniqueName')
        }
    }

    It 'refuses -SolutionName combined with -NoSolution' {
        {
            InModuleScope PacCopilotKit {
                Invoke-PckDataverseRequest -Method Post -Path 'dvtablesearchs' `
                    -Body @{ name = 'x' } -SolutionName 'UnitSolution' -NoSolution
            }
        } | Should -Throw -ExpectedMessage '*contradictory*'
    }

    It 'never stamps the solution header on a Get' {
        InModuleScope PacCopilotKit {
            Invoke-PckDataverseRequest -Method Get -Path 'bots' -SolutionName 'UnitSolution'
        }
        Should -Invoke -ModuleName PacCopilotKit Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            -not $Headers.ContainsKey('MSCRM.SolutionUniqueName')
        }
    }

    It 'returns the created EntityId from a 204 with OData-EntityId' {
        Mock -ModuleName PacCopilotKit Invoke-WebRequest {
            [pscustomobject]@{
                StatusCode = 204
                Content    = ''
                Headers    = @{
                    'OData-EntityId' = @('https://unit.test.invalid/api/data/v9.2/dvtablesearchs(aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee)')
                }
            }
        }
        $result = InModuleScope PacCopilotKit {
            Invoke-PckDataverseRequest -Method Post -Path 'dvtablesearchs' `
                -Body @{ name = 'x' } -SolutionName 'UnitSolution'
        }
        $result.EntityId | Should -Be 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    }
}

Describe 'Savedquery fetchxml translation (war story 1)' {
    # Live verification 2026-08-15: the route succeeds on some system views and
    # fails deterministically on custom-table Quick Finds, so the funnel attempts
    # the call and translates the known failure signature instead of refusing.
    BeforeEach {
        # Fabricate the exact Dataverse failure: an HttpResponseException whose
        # ErrorRecord carries the 0x80040216 error body.
        Mock -ModuleName PacCopilotKit Invoke-WebRequest {
            $ex = [Microsoft.PowerShell.Commands.HttpResponseException]::new(
                'Response status code does not indicate success: 400 (Bad Request).',
                [System.Net.Http.HttpResponseMessage]::new(400))
            $er = [System.Management.Automation.ErrorRecord]::new($ex, 'WebCmdletWebResponseException', 'InvalidOperation', $null)
            $er.ErrorDetails = [System.Management.Automation.ErrorDetails]::new(
                '{"error":{"code":"0x80040216","message":"An unexpected error occurred."}}')
            throw $er
        }
    }

    It 'attempts the PATCH, then translates 0x80040216 into the war story with exit 20' {
        $err = {
            InModuleScope PacCopilotKit {
                Invoke-PckDataverseRequest -Method Patch `
                    -Path 'savedqueries(aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee)' `
                    -Body @{ fetchxml = '<fetch/>' } -SolutionName 'UnitSolution'
            }
        } | Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 20
        $err.Exception.Message | Should -Match '0x80040216'
        $err.Exception.Message | Should -Match 'story 1'
        $err.Exception.Message | Should -Match 'solution surgery'
        Should -Invoke -ModuleName PacCopilotKit Invoke-WebRequest -Times 1 -Exactly
    }

    It 'translates the single-property PUT to /fetchxml the same way' {
        $err = {
            InModuleScope PacCopilotKit {
                Invoke-PckDataverseRequest -Method Put `
                    -Path 'savedqueries(aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee)/fetchxml' `
                    -Body '<fetch/>' -SolutionName 'UnitSolution'
            }
        } | Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 20
    }

    It 'leaves the same code on an unrelated entity untranslated' {
        $err = {
            InModuleScope PacCopilotKit {
                Invoke-PckDataverseRequest -Method Patch `
                    -Path 'bots(aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee)' `
                    -Body @{ fetchxml = 'coincidental-property-name' } -SolutionName 'UnitSolution'
            }
        } | Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 1
        $err.Exception.Message | Should -Match 'Dataverse request failed'
    }

    It 'lets a successful layoutxml PATCH through untouched' {
        Mock -ModuleName PacCopilotKit Invoke-WebRequest {
            [pscustomobject]@{ StatusCode = 204; Content = ''; Headers = @{} }
        }
        InModuleScope PacCopilotKit {
            Invoke-PckDataverseRequest -Method Patch `
                -Path 'savedqueries(aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee)' `
                -Body @{ layoutxml = '<grid/>' } -SolutionName 'UnitSolution'
        }
        Should -Invoke -ModuleName PacCopilotKit Invoke-WebRequest -Times 1 -Exactly
    }

    It 'even lets a successful fetchxml PATCH through, because system views accept it' {
        Mock -ModuleName PacCopilotKit Invoke-WebRequest {
            [pscustomobject]@{ StatusCode = 204; Content = ''; Headers = @{} }
        }
        InModuleScope PacCopilotKit {
            Invoke-PckDataverseRequest -Method Patch `
                -Path 'savedqueries(aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee)' `
                -Body @{ fetchxml = '<fetch/>' } -SolutionName 'UnitSolution'
        }
        Should -Invoke -ModuleName PacCopilotKit Invoke-WebRequest -Times 1 -Exactly
    }
}

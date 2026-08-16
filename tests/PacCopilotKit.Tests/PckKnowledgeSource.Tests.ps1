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

    # One dispatcher mock for the whole read-and-create surface. Individual
    # tests override single routes by re-mocking with a narrower body.
    $script:standardAgentRow = [pscustomobject]@{
        botid              = 'aaaaaaaa-0000-0000-0000-000000000001'
        name               = 'Unit Agent'
        schemaname         = 'wrk_UnitAgent'
        template           = 'default-2.1.0'
        authenticationmode = 2
    }
}

AfterAll {
    InModuleScope PacCopilotKit {
        $script:PckContext = $null
        $script:PckToken = $null
    }
}

Describe 'New-PckKnowledgeSource' {
    BeforeEach {
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            if ($Method -eq 'Get') {
                switch -Regex ($Path) {
                    '^bots\?'              { return [pscustomobject]@{ value = @($script:standardAgentRow) } }
                    '^solutions\?'         { return [pscustomobject]@{ value = @([pscustomobject]@{ solutionid = 's1'; uniquename = 'UnitSolution' }) } }
                    '^EntityDefinitions\(' { return [pscustomobject]@{ LogicalName = 'wrk_caseresolution' } }
                    '^organizations\?'     { return [pscustomobject]@{ value = @([pscustomobject]@{ organizationid = 'o1'; isexternalsearchindexenabled = $true }) } }
                    '^savedqueries\?'      { return [pscustomobject]@{ value = @([pscustomobject]@{
                                                savedqueryid = 'v1'; name = 'Quick Find'
                                                fetchxml = '<fetch><entity name="wrk_caseresolution"><filter isquickfindfields="1" type="or"><condition attribute="wrk_title" operator="like" value="{0}" /><condition attribute="wrk_symptom" operator="like" value="{0}" /></filter></entity></fetch>' }) } }
                    '^dvtablesearchs\?'    { return [pscustomobject]@{ value = @() } }
                }
                return $null
            }
            if ($Method -eq 'Post') {
                switch -Regex ($Path) {
                    '^dvtablesearchs$'        { return [pscustomobject]@{ EntityId = '11111111-aaaa-aaaa-aaaa-111111111111' } }
                    '^dvtablesearchentities$' { return [pscustomobject]@{ EntityId = '22222222-bbbb-bbbb-bbbb-222222222222' } }
                    '^botcomponents$'         { return [pscustomobject]@{ EntityId = '33333333-cccc-cccc-cccc-333333333333' } }
                    '\$ref$'                  { return $null }
                }
            }
            return $null
        }
    }

    It 'creates the four records in order, every one inside the solution' {
        $result = New-PckKnowledgeSource -BotName 'Unit Agent' -Table wrk_caseresolution `
            -SolutionName UnitSolution -DisplayName 'Curated Case Resolutions'

        $result.KnowledgeSourceId | Should -Be '33333333-cccc-cccc-cccc-333333333333'
        $result.DVTableSearchId | Should -Be '11111111-aaaa-aaaa-aaaa-111111111111'

        foreach ($route in @('^dvtablesearchs$', '^dvtablesearchentities$', '^botcomponents$', '\$ref$')) {
            Should -Invoke -ModuleName PacCopilotKit Invoke-PckDataverseRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'Post' -and $Path -match $route -and $SolutionName -eq 'UnitSolution'
            }
        }
    }

    It 'builds the component from the agent read, never from guesses' {
        New-PckKnowledgeSource -BotName 'Unit Agent' -Table wrk_caseresolution `
            -SolutionName UnitSolution | Out-Null

        Should -Invoke -ModuleName PacCopilotKit Invoke-PckDataverseRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'Post' -and $Path -eq 'botcomponents' -and
            $Body.schemaname -eq 'wrk_UnitAgent.knowledge.wrk_caseresolution' -and
            $Body.componenttype -eq 16 -and
            $Body['parentbotid@odata.bind'] -eq '/bots(aaaaaaaa-0000-0000-0000-000000000001)' -and
            $Body.data -match 'skillConfiguration: wrk_caseresolution_search'
        }
    }

    It 'creates one dvtablesearchentity per table' {
        New-PckKnowledgeSource -BotName 'Unit Agent' -Table @('wrk_caseresolution', 'wrk_kbarticle') `
            -SolutionName UnitSolution | Out-Null

        Should -Invoke -ModuleName PacCopilotKit Invoke-PckDataverseRequest -Times 2 -Exactly -ParameterFilter {
            $Method -eq 'Post' -and $Path -eq 'dvtablesearchentities'
        }
    }

    It 'refuses a newer-experience agent before creating anything (war story 2)' {
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            if ($Method -eq 'Get' -and $Path -match '^bots\?') {
                return [pscustomobject]@{ value = @([pscustomobject]@{
                    botid = 'b2'; name = 'New Agent'; schemaname = 'new_Agent'
                    template = 'cliagent-1.0.0'; authenticationmode = 2 }) }
            }
            return $null
        }
        $err = { New-PckKnowledgeSource -BotName 'New Agent' -Table wrk_caseresolution -SolutionName UnitSolution } |
            Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 14
        Should -Invoke -ModuleName PacCopilotKit Invoke-PckDataverseRequest -Times 0 -Exactly -ParameterFilter {
            $Method -eq 'Post'
        }
    }

    It 'refuses a non-Integrated agent before creating anything (war story 3)' {
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            if ($Method -eq 'Get' -and $Path -match '^bots\?') {
                return [pscustomobject]@{ value = @([pscustomobject]@{
                    botid = 'b3'; name = 'No Auth Agent'; schemaname = 'wrk_NoAuth'
                    template = 'default-2.1.0'; authenticationmode = 1 }) }
            }
            return $null
        }
        $err = { New-PckKnowledgeSource -BotName 'No Auth Agent' -Table wrk_caseresolution -SolutionName UnitSolution } |
            Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 18
        Should -Invoke -ModuleName PacCopilotKit Invoke-PckDataverseRequest -Times 0 -Exactly -ParameterFilter {
            $Method -eq 'Post'
        }
    }

    It 'refuses a missing solution with exit code 19 (war story 5)' {
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            if ($Method -eq 'Get' -and $Path -match '^bots\?') {
                return [pscustomobject]@{ value = @($script:standardAgentRow) }
            }
            if ($Method -eq 'Get' -and $Path -match '^solutions\?') {
                return [pscustomobject]@{ value = @() }
            }
            return $null
        }
        $err = { New-PckKnowledgeSource -BotName 'Unit Agent' -Table wrk_caseresolution -SolutionName Missing } |
            Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 19
        Should -Invoke -ModuleName PacCopilotKit Invoke-PckDataverseRequest -Times 0 -Exactly -ParameterFilter {
            $Method -eq 'Post'
        }
    }

    It 'refuses a duplicate search configuration name rather than guessing at reuse' {
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            if ($Method -eq 'Get') {
                switch -Regex ($Path) {
                    '^bots\?'              { return [pscustomobject]@{ value = @($script:standardAgentRow) } }
                    '^solutions\?'         { return [pscustomobject]@{ value = @([pscustomobject]@{ solutionid = 's1'; uniquename = 'UnitSolution' }) } }
                    '^EntityDefinitions\(' { return [pscustomobject]@{ LogicalName = 'wrk_caseresolution' } }
                    '^dvtablesearchs\?'    { return [pscustomobject]@{ value = @([pscustomobject]@{ dvtablesearchid = 'dup'; name = 'wrk_caseresolution_search' }) } }
                }
            }
            return $null
        }
        { New-PckKnowledgeSource -BotName 'Unit Agent' -Table wrk_caseresolution -SolutionName UnitSolution } |
            Should -Throw -ExpectedMessage '*already exists*'
        Should -Invoke -ModuleName PacCopilotKit Invoke-PckDataverseRequest -Times 0 -Exactly -ParameterFilter {
            $Method -eq 'Post'
        }
    }

    It 'rolls back every created record when the chain fails mid-way' {
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            if ($Method -eq 'Get') {
                switch -Regex ($Path) {
                    '^bots\?'              { return [pscustomobject]@{ value = @($script:standardAgentRow) } }
                    '^solutions\?'         { return [pscustomobject]@{ value = @([pscustomobject]@{ solutionid = 's1'; uniquename = 'UnitSolution' }) } }
                    '^EntityDefinitions\(' { return [pscustomobject]@{ LogicalName = 'wrk_caseresolution' } }
                    '^organizations\?'     { return [pscustomobject]@{ value = @([pscustomobject]@{ organizationid = 'o1'; isexternalsearchindexenabled = $true }) } }
                    '^savedqueries\?'      { return [pscustomobject]@{ value = @() } }
                    '^dvtablesearchs\?'    { return [pscustomobject]@{ value = @() } }
                }
                return $null
            }
            if ($Method -eq 'Post') {
                switch -Regex ($Path) {
                    '^dvtablesearchs$'        { return [pscustomobject]@{ EntityId = '11111111-aaaa-aaaa-aaaa-111111111111' } }
                    '^dvtablesearchentities$' { return [pscustomobject]@{ EntityId = '22222222-bbbb-bbbb-bbbb-222222222222' } }
                    # Module classes are not visible in this file's scope; any
                    # exception type exercises the rollback path equally.
                    '^botcomponents$'         { throw 'Dataverse request failed: unit-test midchain failure' }
                }
            }
            return $null
        }

        { New-PckKnowledgeSource -BotName 'Unit Agent' -Table wrk_caseresolution -SolutionName UnitSolution -WarningAction SilentlyContinue } |
            Should -Throw -ExpectedMessage '*midchain failure*'

        Should -Invoke -ModuleName PacCopilotKit Invoke-PckDataverseRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'Delete' -and $Path -eq 'dvtablesearchentities(22222222-bbbb-bbbb-bbbb-222222222222)'
        }
        Should -Invoke -ModuleName PacCopilotKit Invoke-PckDataverseRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'Delete' -and $Path -eq 'dvtablesearchs(11111111-aaaa-aaaa-aaaa-111111111111)'
        }
    }

    It 'refuses a hostile search name before any network call' {
        $err = { New-PckKnowledgeSource -BotName 'Unit Agent' -Table wrk_caseresolution `
            -SolutionName UnitSolution -SearchName "x' or name ne 'y" } |
            Should -Throw -PassThru
        $err.Exception.Message | Should -Match 'not a valid machine name'
        Should -Invoke -ModuleName PacCopilotKit Invoke-PckDataverseRequest -Times 0 -Exactly
    }

    It 'refuses an ambiguous bot name, naming the candidates' {
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            if ($Method -eq 'Get' -and $Path -match '^bots\?') {
                return [pscustomobject]@{ value = @(
                    [pscustomobject]@{ botid = 'b1'; name = 'Agent A'; schemaname = 'wrk_A'; template = 'default-2.1.0'; authenticationmode = 2 }
                    [pscustomobject]@{ botid = 'b2'; name = 'Agent AB'; schemaname = 'wrk_AB'; template = 'default-2.1.0'; authenticationmode = 2 }
                ) }
            }
            return $null
        }
        { New-PckKnowledgeSource -BotName 'Agent A*' -Table wrk_caseresolution -SolutionName UnitSolution } |
            Should -Throw -ExpectedMessage '*matches 2 agents*'
    }

    It 'reports rather than hides the preconditions it cannot solve' {
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            if ($Method -eq 'Get') {
                switch -Regex ($Path) {
                    '^bots\?'              { return [pscustomobject]@{ value = @($script:standardAgentRow) } }
                    '^solutions\?'         { return [pscustomobject]@{ value = @([pscustomobject]@{ solutionid = 's1'; uniquename = 'UnitSolution' }) } }
                    '^EntityDefinitions\(' { return [pscustomobject]@{ LogicalName = 'wrk_caseresolution' } }
                    '^organizations\?'     { return [pscustomobject]@{ value = @([pscustomobject]@{ organizationid = 'o1'; isexternalsearchindexenabled = $false }) } }
                    '^savedqueries\?'      { return [pscustomobject]@{ value = @([pscustomobject]@{
                                                savedqueryid = 'v1'; name = 'Quick Find'
                                                fetchxml = '<fetch><entity name="wrk_caseresolution"><filter isquickfindfields="1" type="or"><condition attribute="wrk_title" operator="like" value="{0}" /></filter></entity></fetch>' }) } }
                    '^dvtablesearchs\?'    { return [pscustomobject]@{ value = @() } }
                }
                return $null
            }
            if ($Method -eq 'Post') {
                switch -Regex ($Path) {
                    '^dvtablesearchs$'        { return [pscustomobject]@{ EntityId = '11111111-aaaa-aaaa-aaaa-111111111111' } }
                    '^dvtablesearchentities$' { return [pscustomobject]@{ EntityId = '22222222-bbbb-bbbb-bbbb-222222222222' } }
                    '^botcomponents$'         { return [pscustomobject]@{ EntityId = '33333333-cccc-cccc-cccc-333333333333' } }
                    '\$ref$'                  { return $null }
                }
            }
            return $null
        }

        $result = New-PckKnowledgeSource -BotName 'Unit Agent' -Table wrk_caseresolution `
            -SolutionName UnitSolution -WarningAction SilentlyContinue

        $result.SearchEnabled | Should -BeFalse
        @($result.Warnings) | Should -Not -BeNullOrEmpty
        (@($result.Warnings) -join ' ') | Should -Match 'Enable-PckDataverseSearch'
        (@($result.Warnings) -join ' ') | Should -Match 'war story 1'
        $result.FindColumns['wrk_caseresolution'] | Should -Be @('wrk_title')
    }
}

Describe 'Assert-PckSolutionExists (war story 5)' {
    It 'passes silently when the solution exists' {
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            [pscustomobject]@{ value = @([pscustomobject]@{ solutionid = 's1'; uniquename = 'UnitSolution' }) }
        }
        InModuleScope PacCopilotKit { Assert-PckSolutionExists -SolutionName UnitSolution }
    }

    It 'refuses a missing solution with exit code 19 and a pac hint' {
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest {
            [pscustomobject]@{ value = @() }
        }
        $err = { InModuleScope PacCopilotKit { Assert-PckSolutionExists -SolutionName Nope } } |
            Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 19
        $err.Exception.Message | Should -Match 'pac solution list'
    }

    It 'refuses a hostile solution name before any network call' {
        Mock -ModuleName PacCopilotKit Invoke-PckDataverseRequest { }
        $err = { InModuleScope PacCopilotKit { Assert-PckSolutionExists -SolutionName "x' or uniquename ne 'y" } } |
            Should -Throw -PassThru
        $err.Exception.ExitCode | Should -Be 19
        Should -Invoke -ModuleName PacCopilotKit Invoke-PckDataverseRequest -Times 0 -Exactly
    }
}

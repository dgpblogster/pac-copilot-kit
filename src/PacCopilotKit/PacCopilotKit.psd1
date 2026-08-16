@{
    RootModule        = 'PacCopilotKit.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '410387a5-8886-43db-a84c-465c8eb154e7'
    Author            = 'Mariano Gomez Bent'
    Copyright         = '(c) 2026 Mariano Gomez Bent. MIT license.'
    Description       = 'Paved-road toolkit for the Microsoft Copilot Studio agent lifecycle over the pac CLI and the Dataverse Web API. Creates Dataverse knowledge sources in-solution and repeatably, and makes the published Copilot Studio ALM prescription executable in a shell and in CI.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @(
        'Connect-PckPowerPlatform'
        'Enable-PckDataverseSearch'
        'Export-PckSolutionBackup'
        'Get-PckAgentInfo'
        'New-PckKnowledgeSource'
        'Wait-PckDataverseSearchReady'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('PowerPlatform', 'CopilotStudio', 'Dataverse', 'ALM', 'pac')
            LicenseUri = 'https://github.com/dgpblogster/pac-copilot-kit/blob/main/LICENSE'
            ProjectUri = 'https://github.com/dgpblogster/pac-copilot-kit'
        }
    }
}

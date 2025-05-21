# Based on the PSGallery settings:
# https://github.com/PowerShell/PSScriptAnalyzer/blob/main/Engine/Settings/PSGallery.psd1
@{
    IncludeRules = @(
        'PSAvoidTrailingWhitespace'
        'PSUseApprovedVerbs',
        'PSReservedCmdletChar',
        'PSReservedParams',
        'PSMissingModuleManifestField',
        'PSAvoidDefaultValueSwitchParameter',
        'PSAvoidUsingCmdletAliases',
        'PSAvoidUsingWMICmdlet',
        'PSAvoidUsingEmptyCatchBlock',
        'PSUseCmdletCorrectly',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSAvoidUsingPositionalParameters',
        'PSAvoidGlobalVars',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSAvoidUsingInvokeExpression',
        'PSAvoidUsingPlainTextForPassword',
        'PSAvoidUsingComputerNameHardcoded',
        'PSUsePSCredentialType',
        'PSDSC*'
    )
    ExcludeRules = @(
        'PSUseShouldProcessForStateChangingFunctions', # Enable later and refactor commands
        'PSShouldProcess', # Enable later and refactor commands
        'PSUseSingularNouns',
        'PSAvoidUsingWriteHost',
        'PSAvoidGlobalVars'
    )
}
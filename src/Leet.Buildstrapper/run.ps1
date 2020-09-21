#!/usr/bin/env pwsh
#requires -version 6

<#
.SYNOPSIS
Command execution proxy for Leet.Build system that performs all the necessary initialization.

.DESCRIPTION
This script is responsible for carrying over any build command to the registered modules through Leet.Build\Build-Repository cmdlet. To make this possible the script is also responsible for finding and installing required version of the Leet.Build modules in the system.
The script may be instructed in two ways:
First one by specifying version of the required Leet.Build module. This orders this script to download requested version of Leet.Build module from available PSRepositories when it is missing in the system.
Second one by providing path to the directory that contains required Leet.Build module files. This path will be added to process $env:PSModulePath variable if not alreade present there.

.EXAMPLE
PS > ./run.ps1 help

Use this command to display available build commands and learn about available parameters when the required Leet.Build modules configuration is available in the JSON configuration file or in environmental varaible.

.EXAMPLE
PS > ./run.ps1 help -LeetBuildVersion 1.0.0

Use this command to display available build commands and learn about available parameters when a specific version of Leet.Build module is expected.

.EXAMPLE
PS > ./run.ps1 help -LeetBuildLocation ~\Leet.Build

Use this command to display available build commands and learn about available parameters for a Leet.Build stored in the specified location.

.EXAMPLE
PS > ./run.ps1 -TaskName test -RepositoryRoot ~\Repository

Use this command to execute 'test' command against repository located at ~\Repository location using Leet.Build configured in JSON file or via envirnmental variable.
Configuration Leet.Build.json file need to be located under 'build' subfolder of the repository ~\Repository location.

.EXAMPLE
PS > ./run.ps1 build -LogFilePath ~\Leet.Build.log

Use this command to execute 'build' command against repository located at current location using Leet.Build configured in JSON file or via envirnmental variable and store execution log in ~\Leet.Build.log file.

.EXAMPLE
PS > ./run.ps1 build -PreservePreferences

Use this command to execute 'build' command without modification of PowerShell preference variables.
By default this scripts modifies some of the preference variables bo values better suited for build script, i.e. error shall break execution, etc. All the preference variables are restored after each command execution.

.EXAMPLE
PS > ./run.ps1 build -UnloadModules

Use this command to execute 'build' command and unloads all Leet.Build modules from PowerShell before executing the command.

.NOTES
Any parameter for Leet.Build ssytem may be provided in three ways:
1. Explicitely via PowerShell command arguments.
2. JSON property in 'Leet.Build.json' file stored under 'build' subdirectory of the spcified repository root.
3. Environmental variable with a 'Leet_' prefix before parameter name.

The list above also defines precedence order of the importance.

Leet.Build.json configuration file should be a simple JSON object with properties which names match parameter name and which values shall be used as arguments for the parameters.
A JSON schema for the configuration file is available at https://raw.githubusercontent.com/Leet/Build/master/schema/Leet.Build.schema.json

.LINK
Leet.Build\Build-Repository
#>

using namespace System.Diagnostics.CodeAnalysis
using namespace System.Management.Automation

[CmdletBinding(SupportsShouldProcess = $True,
               ConfirmImpact = 'Low',
               PositionalBinding = $False,
               DefaultParameterSetName = 'Remote')]
Param (
    # Name of the build task to invoke.
    [Parameter(Position = 0,
               Mandatory = $False,
               ValueFromPipeline = $True,
               ValueFromPipelineByPropertyName = $True)]
    [AllowEmptyString()]
    [String]
    $TaskName,

    # Version of the Leet.Build tools to use. If not specified the current script will try to read it from 'Leet.Build.json' file.
    [Parameter(HelpMessage = 'Enter version of the Leet.Build to be used to run build scripts.',
               ParameterSetName = 'Remote',
               Mandatory = $False,
               ValueFromPipeline = $True,
               ValueFromPipelineByPropertyName = $False)]
    [ValidateScript({ [SemanticVersion]::Parse($_) })]
    [String]
    $LeetBuildVersion,

    # Location of a local Leet.Build version to use for the build.
    [Parameter(HelpMessage = 'Enter path to a Leet.Build directory to be used to run build scripts.',
               ParameterSetName = 'Local',
               Mandatory = $True,
               ValueFromPipeline = $False,
               ValueFromPipelineByPropertyName = $False)]
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [String]
    $LeetBuildLocation,

    # The path to the project's repository root directory. If not specified the current script root directory will be used.
    [Parameter(Mandatory = $False,
               ValueFromPipeline = $False,
               ValueFromPipelineByPropertyName = $False)]
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [String]
    $RepositoryRoot = $PSScriptRoot,

    # Path to the build log file.
    [Parameter(Mandatory = $False,
               ValueFromPipeline = $False,
               ValueFromPipelineByPropertyName = $False)]
    [ValidateScript({ [System.IO.Path]::GetFullPath($_) })]
    [ValidateScript({ -not (Test-Path -Path $_ -PathType Container) })]
    [String]
    $LogFilePath = 'Leet.Build.log',

    # Indicates whether the buildstrapper script shall not modify preference variables.
    [Parameter(Mandatory = $False,
               ValueFromPipeline = $False,
               ValueFromPipelineByPropertyName = $False)]
    [Switch]
    $PreservePreferences,

    # Indicates whether the buildstrapper script shall unload all Leet.Build modules before importing them.
    [Parameter(Mandatory = $False,
               ValueFromPipeline = $False,
               ValueFromPipelineByPropertyName = $False)]
    [Switch]
    $UnloadModules,

    # Arguments to be passed to the Leet.Build toolchain.
    [Parameter(Mandatory = $False,
               ValueFromPipeline = $False,
               ValueFromPipelineByPropertyName = $True,
               ValueFromRemainingArguments = $True)]
    [String[]]
    $Arguments
)

DynamicParam {
    function Initialize-ScriptConfiguration {
        <#
        .SYNOPSIS
        Initializes the script by loading parameter values from configuration file or using default predefined values.

        .NOTES
        If the script parameter values are not specified they may be loaded from Leet.Build.json configuration file.
        This configuration file should be located in 'build' subdirectory of the folder specified in $script:RepositoryRoot variable.
        If the parameter value is not specified at command-line level nor in the configuration file then a default predefined value is being assigned to it or an error is being thrown depending on the parameter's nature.
        #>

        $configurationJson = Read-ConfigurationFromFile
        Set-ParameterValue 'LeetBuildVersion' $configurationJson
        Set-ParameterValue 'LeetBuildLocation' $configurationJson
    }


    function Read-ConfigurationFromFile {
        <#
        .SYNOPSIS
        Reads a script configuration values from Leet.Build.json configuration file.
        #>

        Param (
            # The path to the project's repository root directory. If not specified the current script root directory will be used.
            [String]
            $RepositoryRoot = $PSScriptRoot
        )

        $result = @{}
        Get-ChildItem -Path $RepositoryRoot -Filter 'Leet.Build.json' -Recurse | Foreach-Object {
            $configFilePath = $_.FullName
            Write-Verbose "Reading fallback configuration from '$configFilePath' file."

            if (Test-Path $configFilePath -PathType Leaf) {
                try {
                    $configFileContent = Get-Content -Raw -Encoding UTF8 -Path $configFilePath
                    $configJson = ConvertFrom-Json $configFileContent
                    $configJson.psobject.Properties | ForEach-Object {
                        $result | Add-Member -MemberType $_.MemberType -Name $_.Name -Value $_.Value -Force
                    }
                }
                catch {
                    Write-Error "'$configFilePath' file is not a correct JSON file."
                    throw
                }
            }
        }

        $result
    }


    function Install-LeetBuild {
        <#
        .SYNOPSIS
        Installs Leet.Build tools according to the specified script parameters.
        #>

        param ()

        if ($script:LeetBuildLocation) {
            Install-LocalLeetBuild
        } elseif ($script:LeetBuildVersion) {
            Install-RemoteLeetBuild
        }
    }


    function Install-LocalLeetBuild {
        <#
        .SYNOPSIS
        Sets local Leet.Build directory path as a head of the $env:PSModulePath variable.
        #>

        param ()

        Write-Verbose "Setting '$script:LeetBuildLocation' as the head of the PowerShell modules path..."
        $normalizedLocation = if ([System.IO.Path]::IsPathRooted($script:LeetBuildLocation)) {
            $script:LeetBuildLocation
        }
        else {
            Join-Path (Get-Location) $script:LeetBuildLocation
        }

        $env:PSModulePath = Join-DirectoryAndPath $normalizedLocation $env:PSModulePath
    }


    function Install-RemoteLeetBuild {
        <#
        .SYNOPSIS
        Installs Leet.Build module and its all dependencies from the available PowerShell repositories.
        #>

        param ()

        if (-not (Get-Module -FullyQualifiedName @{ ModuleName='Leet.Build'; ModuleVersion=$script:LeetBuildVersion } -ListAvailable)) {
            Write-Verbose "Installing Leet.Build v$script:LeetBuildVersion from the available PowerShell repositories..."
            Install-Module -Name 'Leet.Build'                        `
                           -RequiredVersion $script:LeetBuildVersion `
                           -Scope CurrentUser                        `
                           -AllowPrerelease                          `
                           -Force                                    `
                           -ErrorAction Stop
        }
    }


    function Import-LeetBuildModules {
        <#
        .SYNOPSIS
        Imports Leet.Build modules.
        #>

        param (
            # Indicates whether the buildstrapper script shall unload all Leet.Build modules before importing them.
            [Parameter(Mandatory = $False,
                       ValueFromPipeline = $False,
                       ValueFromPipelineByPropertyName = $False)]
            [Switch]
            $UnloadModules
        )

        if ($UnloadModules) {
            Remove-Module 'Leet.*' -Force
        }

        Import-Module 'Leet.Build' -Global -ErrorAction Stop
    }


    function Join-DirectoryAndPath {
        <#
        .SYNOPSIS
        Joins a specified directory and a $Path variable if it does not contain the direcory yet.
        #>

        param (
            # A directory to be added to the $Path.
            [String]
            $Directory,

            # A value of the path set to which the directory shall be added.
            [String]
            $Path
        )

        $normalizedDirectory = [System.IO.Path]::GetFullPath($Directory)
        $delimiter = [System.IO.Path]::PathSeparator
        $result = $normalizedDirectory

        ($Path -split $delimiter) | ForEach-Object {
            $normalizedItem = [System.IO.Path]::GetFullPath($_)
            if ($IsWindows) {
                if ($normalizedItem -ine $normalizedDirectory) {
                    $result += "$delimiter$_"
                }
            } else {
                if ($normalizedItem -cne $normalizedDirectory) {
                    $result += "$delimiter$_"
                }
            }
        }

        return $result
    }


    function Set-ParameterValue {
        <#
        .SYNOPSIS
        Sets a value for the specified script's parameter if not specified via command line using environment variables or Leet.Build.json configuration file.
        #>

        param (
            # Name of the script's parameter which value shall be set.
            [String]
            $ParameterName,

            # Custom PowerShell object with JSON configuration.
            [PSCustomObject]
            $ConfigurationJson
        )

        if (Test-Path "variable:script:$ParameterName") {
            return
        }

        $value = $null

        $localParameterName = $ParameterName
        if ($localParameterName -notmatch '^Leet[a-zA-Z]*_[a-zA-Z]+[a-zA-Z0-9_]*$') {
            $localParameterName = "Leet_$localParameterName"
        }

        if ($ConfigurationJson -and (Get-Member -Name $ParameterName -InputObject $ConfigurationJson)) {
            $value = $ConfigurationJson.$ParameterName
        }

        if (Test-Path "env:\$localParameterName") {
            $value = Get-Content "env:\$localParameterName"
        }

        if ($null -ne $value) {
            Set-Variable -Scope "script" -Name $ParameterName -Value $value
            Write-Verbose "  -$ParameterName = `"$value`""
        }
    }

    function Import-RepositoryExtension {
        <#
        .SYNOPSIS
        Executes Leet.Build.Repository scripts from the specified repository.
        #>
        [CmdletBinding(PositionalBinding = $False)]

        param (
            # The directory to the repository's root directory path.
            [Parameter(HelpMessage = "Provide path to the repository's root directory.",
                       Position = 0,
                       Mandatory = $True,
                       ValueFromPipeline = $False,
                       ValueFromPipelineByPropertyName = $False)]
            [String]
            $RepositoryRoot)

        process {
            Get-ChildItem -Path $RepositoryRoot -Filter "$LeetBuildRepository.ps1" -Recurse | ForEach-Object {
                . "$_"
            }
        }
    }

    Initialize-ScriptConfiguration
    Install-LeetBuild
    Import-LeetBuildModules
    Import-RepositoryExtension $RepositoryRoot

    $parameterTypeName = 'System.Management.Automation.RuntimeDefinedParameter'
    $attributes = New-Object -Type System.Management.Automation.ParameterAttribute
    $attributes.Mandatory = $false
    $result = New-Object -Type System.Management.Automation.RuntimeDefinedParameterDictionary

    $buildExtensionCommand = Get-Command -Module 'Leet.Build.Extensibility' -Name 'Get-BuildExtension'
    & $buildExtensionCommand | ForEach-Object {
        $extensionPrefix = $($_.Name.Replace('.', [String]::Empty))

        ForEach-Object { $_.Tasks.Values } |
        ForEach-Object { $_.Jobs } |
        ForEach-Object {
            if ($_ -is [ScriptBlock]) {
                if ($_.Ast.ParamBlock) {
                    $_.Ast.ParamBlock.Parameters | ForEach-Object {
                        $parameterAst = $_
                        $parameterName = $_.Name.VariablePath.UserPath

                        ($parameterName, "$($extensionPrefix)_$parameterName") | ForEach-Object {
                            if (-not ($result.Keys -contains $_)) {
                                $attributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
                                $attributeCollection.Add($attributes)
                                $parameterAst.Attributes | ForEach-Object {
                                    if ($_.TypeName.Name -eq "ArgumentCompleter" -or $_.TypeName.Name -eq "ArgumentCompleterAttribute") {
                                        $commonArgument = if ($_.PositionalArguments.Count -gt 0) {
                                            $_.PositionalArguments[0]
                                        }
                                        else {
                                            $_.NamedArguments[0].Argument
                                        }

                                        $completerParameter = if ($commonArgument -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                                            $commonArgument.ScriptBlock.GetScriptBlock()
                                        }
                                        else {
                                            $commonArgument.StaticType
                                        }

                                        $autocompleterAttribute = New-Object -Type System.Management.Automation.ArgumentCompleterAttribute $completerParameter
                                        $attributeCollection.Add($autocompleterAttribute)
                                    }
                                }

                                $dynamicParam = New-Object -Type $parameterTypeName ($_, $parameterAst.StaticType, $attributeCollection)
                                $result.Add($dynamicParam.Name, $dynamicParam)
                            }
                        }
                    }
                }
            }
        }
    }

    $result
}

Begin {
    function Start-Logging {
        <#
        .SYNOPSIS
        Starts logging build messages to a specified log file.
        #>

        [SuppressMessage('PSUseShouldProcessForStateChangingFunctions',
                         '',
                         Justification = 'Functions called by this function will handle the confirmation.')]

        param ()

        if ($script:LogFilePath) {
            Start-Transcript -Path $script:LogFilePath | Out-Null
        }
    }


    function Stop-Logging {
        <#
        .SYNOPSIS
        Stops logging build messages to a specified log file.
        #>

        [SuppressMessage('PSUseShouldProcessForStateChangingFunctions',
                         '',
                         Justification = 'Functions called by this function will handle the confirmation.')]
        [SuppressMessage('PSAvoidUsingEmptyCatchBlock',
                         '',
                         Justification = 'Empty catch block is the only way to make Stop-Transcript work with -WhatIf applied to Start-Transcript.')]

        param ()

        if ($script:LogFilePath) {
            try {
                Stop-Transcript -ErrorAction 'SilentlyContinue' | Out-Null
            }
            catch { }
        }
    }


    function Set-PreferenceVariables {
        <#
        .SYNOPSIS
        Sets global peference variables to its local values to propagate them in module functions.
        #>
        [CmdletBinding(PositionalBinding = $False,
                       SupportsShouldProcess = $True,
                       ConfirmImpact = 'Low')]

        param ()

        process {
            if (-not $Script:PreservePreferences) {
                if ($PSCmdlet.ShouldProcess("Global preference variables.", "Modify with backup.")) {
                    $global:ConfirmPreference     = $ConfirmPreference
                    $global:DebugPreference       = $DebugPreference
                    $global:ErrorActionPreference = if ($Env:CI -and $OverrideErrorAction) { 'Stop' } else { $ErrorActionPreference }
                    $global:InformationPreference = if ($OverrideInformationAction) { 'Continue' } else { $InformationPreference }
                    $global:ProgressPreference    = if ($Env:CI -and $OverrideProgressAction) { 'SilentlyContinue' } else { $ProgressPreference }
                    $global:VerbosePreference     = if (('True', '1') -contains $env:LeetBuild_Verbose -and $OverrideVerbose) { 'Continue' } else { $VerbosePreference }
                    $global:WarningPreference     = if ($Env:CI -and $OverrideWarningAction) { 'Continue' } else { $WarningPreference }
                    $global:WhatIfPreference      = $WhatIfPreference
                }
            }
        }
    }


    function Reset-PreferenceVariables {
        <#
        .SYNOPSIS
        Resets global peference variables to the values from before script run.
        #>
        [CmdletBinding(PositionalBinding = $False,
                       SupportsShouldProcess = $True,
                       ConfirmImpact = 'Low')]

        param ()

        if (-not $Script:PreservePreferences) {
            if ($PSCmdlet.ShouldProcess("Global preference variables.", "Revert changes.")) {
                $global:ConfirmPreference     = $script:ConfirmPreferenceBackup
                $global:DebugPreference       = $script:DebugPreferenceBackup
                $global:ErrorActionPreference = $script:ErrorActionPreferenceBackup
                $global:InformationPreference = $script:InformationPreferenceBackup
                $global:ProgressPreference    = $script:ProgressPreferenceBackup
                $global:VerbosePreference     = $script:VerbosePreferenceBackup
                $global:WarningPreference     = $script:WarningPreferenceBackup
                $global:WhatIfPreference      = $script:WhatIfPreferenceBackup
            }
        }
    }


    function Write-Invocation {
        <#
        .SYNOPSIS
        Writes a verbose message about the specified invocation.
        #>

        param (
            # Invocation which information shall be written.
            [InvocationInfo]
            $Invocation
        )

        Write-Verbose "Executing: '$($Invocation.MyCommand.Name)' with parameters:"
        $Invocation.BoundParameters.Keys | ForEach-Object {
            Write-Verbose "  -$_ = `"$($Invocation.BoundParameters[$_])`""
        }
    }

    try {
        Set-StrictMode -Version 3

        $ConfirmPreferenceBackup     = $global:ConfirmPreference
        $DebugPreferenceBackup       = $global:DebugPreference
        $ErrorActionPreferenceBackup = $global:ErrorActionPreference
        $InformationPreferenceBackup = $global:InformationPreference
        $ProgressPreferenceBackup    = $global:ProgressPreference
        $VerbosePreferenceBackup     = $global:VerbosePreference
        $WarningPreferenceBackup     = $global:WarningPreference
        $WhatIfPreferenceBackup      = $global:WhatIfPreference

        $OverrideErrorAction       = -not $PSBoundParameters.ContainsKey('ErrorAction')
        $OverrideInformationAction = -not $PSBoundParameters.ContainsKey('InformationAction')
        $OverrideProgressAction    = -not $PSBoundParameters.ContainsKey('ProgressAction')
        $OverrideVerbose           = -not $PSBoundParameters.ContainsKey('Verbose')
        $OverrideWarningAction     = -not $PSBoundParameters.ContainsKey('WarningAction')

        Start-Logging
        Set-PreferenceVariables
        Write-Invocation $MyInvocation
        Initialize-ScriptConfiguration
        Install-LeetBuild
        Import-LeetBuildModules -UnloadModules:$script:UnloadModules
    }
    catch {
        Stop-Logging
        throw
    }
}

Process {
    try {
        Leet.Build\Build-Repository -RepositoryRoot $script:RepositoryRoot -TaskName $script:TaskName -NamedArguments $PSBoundParameters -UnknownArguments $script:Arguments
    }
    catch {
        throw
    }
    finally {
        Reset-PreferenceVariables
        Stop-Logging
    }
}

End {
    Stop-Logging
}

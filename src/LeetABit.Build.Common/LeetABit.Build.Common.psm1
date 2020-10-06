#requires -version 6
using namespace System.Management.Automation
using namespace System.Collections

Set-StrictMode -Version 3.0
Import-LocalizedData -BindingVariable LocalizedData -FileName LeetABit.Build.Common.Resources.psd1


##################################################################################################################
# Public Commands
##################################################################################################################


function ConvertTo-ExpressionString {
    <#
    .SYNOPSIS
        Converts an object to a PowerShell expression string.
    .DESCRIPTION
        The ConvertTo-ExpressionString cmdlet converts any .NET object to a object type's defined string representation.
        Dictionaries and PSObjects are converted to hash literal expression format. The field and properties are converted to key expressions,
        the field and properties values are converted to property values, and the methods are removed. Objects that implements IEnumerable
        are converted to array literal expression format.
    .EXAMPLE
        ConvertTo-ExpressionString -Obj $Null, $True, $False

        $Null
        $True
        $False

        Converts PowerShell literals expression string.
    .EXAMPLE
        ConvertTo-ExpressionString -Obj @{Name = "Custom object instance"}

        @{
          'Name' = 'Custom object instance'
        }

        Converts hashtable to PowerShell hash literal expression string.
    .EXAMPLE
        ConvertTo-ExpressionString -Obj @( $Name )

        @(
          $Null
        )

        Converts array to PowerShell array literal expression string.
    .EXAMPLE
        ConvertTo-ExpressionString -Obj (New-PSObject "SampleType" @{Name = "Custom object instance"})

        <# SampleType #`>
        @{
          'Name' = 'Custom object instance'
        }

        Converts custom PSObject to PowerShell hash literal expression string with a custom type name in the comment block.
    #>
    [CmdletBinding(PositionalBinding = $False)]
    [OutputType([String[]])]

    param (
        # Object to convert.
        [Parameter(HelpMessage = 'Provide an object to convert.',
                   Position = 0,
                   Mandatory = $True,
                   ValueFromPipeline = $True,
                   ValueFromPipelineByPropertyName = $True)]
        [AllowNull()]
        [Object]
        $Obj
    )

    process {
        ConvertTo-ExpressionStringWithIndentation $Obj 0
    }
}


function Import-CallerPreference {
    <#
    .SYNOPSIS
        Fetches "Preference" variable values from the caller's scope.
    .DESCRIPTION
        Script module functions do not automatically inherit their caller's variables, but they can be
        obtained through the $PSCmdlet variable in Advanced Functions. This function is a helper function
        for any script module Advanced Function; by passing in the values of $PSCmdlet and
        $ExecutionContext.SessionState, Import-CallerPreference will set the caller's preference variables locally.
    .EXAMPLE
        Import-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

        Imports the default PowerShell preference variables from the caller into the local scope.
    .LINK
        about_Preference_Variables
    #>
    [CmdletBinding(PositionalBinding = $False)]

    param (
        # The $PSCmdlet object from a script module Advanced Function.
        [Parameter(HelpMessage = 'Provide an instance of the $PSCmdlet object.',
                   Position = 0,
                   Mandatory = $True,
                   ValueFromPipeline = $False,
                   ValueFromPipelineByPropertyName = $False)]
        [PSCmdlet]
        $Cmdlet,

        # The $ExecutionContext.SessionState object from a script module Advanced Function.
        # This is how the Import-CallerPreference function sets variables in its callers' scope,
        # even if that caller is in a different script module.
        [Parameter(HelpMessage = 'Provide an instance of the $ExecutionContext.SessionState object.',
                   Position = 1,
                   Mandatory = $True,
                   ValueFromPipeline = $False,
                   ValueFromPipelineByPropertyName = $False)]
        [SessionState]
        $SessionState
    )

    begin {
        $preferenceVariablesMap = @{
            'ErrorView' = $null
            'FormatEnumerationLimit' = $null
            'InformationPreference' = $null
            'LogCommandHealthEvent' = $null
            'LogCommandLifecycleEvent' = $null
            'LogEngineHealthEvent' = $null
            'LogEngineLifecycleEvent' = $null
            'LogProviderHealthEvent' = $null
            'LogProviderLifecycleEvent' = $null
            'MaximumAliasCount' = $null
            'MaximumDriveCount' = $null
            'MaximumErrorCount' = $null
            'MaximumFunctionCount' = $null
            'MaximumHistoryCount' = $null
            'MaximumVariableCount' = $null
            'OFS' = $null
            'OutputEncoding' = $null
            'ProgressPreference' = $null
            'PSDefaultParameterValues' = $null
            'PSEmailServer' = $null
            'PSModuleAutoLoadingPreference' = $null
            'PSSessionApplicationName' = $null
            'PSSessionConfigurationName' = $null
            'PSSessionOption' = $null

            'ConfirmPreference' = 'Confirm'
            'DebugPreference' = 'Debug'
            'ErrorActionPreference' = 'ErrorAction'
            'VerbosePreference' = 'Verbose'
            'WarningPreference' = 'WarningAction'
            'WhatIfPreference' = 'WhatIf'
        }
    }

    process {
        foreach ($variableName in $preferenceVariablesMap.Keys) {
            $parameterName = $preferenceVariablesMap[$variableName]
            if (-not $parameterName `
                -or `
                -not $Cmdlet.MyInvocation.BoundParameters.ContainsKey($parameterName)) {
                $variable = $Cmdlet.SessionState.PSVariable.Get($variableName)

                if ($variable)
                {
                    if ($SessionState -eq $ExecutionContext.SessionState)
                    {
                        Set-Variable -Scope 1 -Name $variable.Name -Value $variable.Value -Force -Confirm:$false -WhatIf:$false
                    }
                    else
                    {
                        $SessionState.PSVariable.Set($variable.Name, $variable.Value)
                    }
                }
            }
        }
    }
}


function New-PSObject {
    <#
    .SYNOPSIS
        Creates an instance of a System.Management.Automation.PSObject object.
    .DESCRIPTION
        The New-PSObject cmdlet creates an instance of a System.Management.Automation.PSObject object.
    .EXAMPLE
        New-PSObject -TypeName "CustomType" -Property @{InstanceName = "Sample instance"}

        Creates a new custom PSObject with custom type [SampleType] and one property "InstanceName" with value equal to Sample instance".
    #>
    [CmdletBinding(PositionalBinding = $False)]
    [OutputType([PSObject])]

    param (
        # Specifies a custom type name for the object.
        # Enter a hash table in which the keys are the names of properties or methods and the values are property values or method arguments. New-Object creates the object and sets each property value and invokes each method in the order that they appear in the hash table.
        # If you specify a property that does not exist on the object, New-PSObject adds the specified property to the object as a NoteProperty.
        [Parameter(Position = 0,
                   Mandatory = $False,
                   ValueFromPipeline = $False,
                   ValueFromPipelineByPropertyName = $True)]
        [String[]]
        $TypeName,

        # Sets property values and invokes methods of the new object.
        [Parameter(Position = 1,
                   Mandatory = $False,
                   ValueFromPipeline = $True,
                   ValueFromPipelineByPropertyName = $True)]
        [IDictionary]
        $Property
    )

    begin {
        Import-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    }

    process {
        $result = New-Object PSObject -Property $Property
        if ($PSBoundParameters.ContainsKey('TypeName') -and $TypeName) {
            foreach ($currentTypeName in $TypeName) {
                $result.PSObject.TypeNames.Add($currentTypeName)
            }
        }

        $result
    }
}


##################################################################################################################
# Private Commands
##################################################################################################################


function ConvertTo-ExpressionStringWithIndentation {
    <#
    .SYNOPSIS
        Converts an object to a PowerShell expression string with a specified indentation.
    .DESCRIPTION
        The ConvertTo-ExpressionStringWithIndentation cmdlet converts any .NET object to a object type's defined string representation.
        Dictionaries and PSObjects are converted to hash literal expression format. The field and properties are converted to key expressions,
        the field and properties values are converted to property values, and the methods are removed. Objects that implements IEnumerable
        are converted to array literal expression format.
        Each line of the resulting string is indented by the specified number of spaces.
    #>
    [CmdletBinding(PositionalBinding = $False)]
    [OutputType([String[]])]

    param (
        # Object to convert.
        [Parameter(HelpMessage = 'Provide an object to convert.',
                   Position = 0,
                   Mandatory = $True,
                   ValueFromPipeline = $True,
                   ValueFromPipelineByPropertyName = $True)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [Object]
        $Obj,

        # Number of spaces to perpend to each line of the resulting string.
        [Parameter(HelpMessage = 'Provide an indentation level.',
                   Position = 1,
                   Mandatory = $False,
                   ValueFromPipeline = $True,
                   ValueFromPipelineByPropertyName = $True)]
        [ValidateRange([ValidateRangeKind]::NonNegative)]
        [Int32]
        $IndentationLevel = 0
    )

    process {
        $prefix = " " * $IndentationLevel

        if ($Null -eq $Obj) {
            '$Null'
        }
        elseif ($Obj -is [String]) {
            "'$Obj'"
        }
        elseif ($Obj -is [SwitchParameter] -or $Obj -is [Boolean]) {
            "`$$Obj"
        }
        elseif ($Obj -is [IDictionary]) {
            $result = "@{"
            $Obj.Keys | ForEach-Object {
                $value = ConvertTo-ExpressionStringWithIndentation $Obj[$_] ($IndentationLevel + 2)
                $result += [Environment]::NewLine + "$prefix  '$_' = $value; "
            }

            $result = $result.Substring(0, $result.Length - 2)
            $result += [Environment]::NewLine + "$prefix}"
            $result
        }
        elseif ($Obj -is [PSCustomObject]) {
            $result = ""

            if ($Obj.PSObject.TypeNames.Count -gt 0) {
                $result += "<# "
                $Obj.PSObject.TypeNames | ForEach-Object {
                    if ($_ -ne "Selected.System.Management.Automation.PSCustomObject" -and
                        $_ -ne "System.Management.Automation.PSCustomObject" -and
                        $_ -ne "System.Object") {
                        $result += "[$_], "
                    }
                }

                $result = $result.Substring(0, $result.Length - 2)
                $result += " #>"
                $result += [Environment]::NewLine
            }

            $result += "@{"
            Get-Member -InputObject $Obj -MemberType NoteProperty | ForEach-Object {
                $value = $Obj | Select-Object -ExpandProperty $_.Name
                $value = ConvertTo-ExpressionStringWithIndentation $value ($IndentationLevel + 1)
                $result += [Environment]::NewLine + "$prefix  '$($_.Name)' = $value; "
            }

            $result = $result.Substring(0, $result.Length - 2)
            $result += [Environment]::NewLine + "$prefix}"
            $result
        }
        elseif ($Obj -is [IEnumerable]) {
            $result = "("
            $Obj | ForEach-Object {
                $value = ConvertTo-ExpressionStringWithIndentation $_ ($IndentationLevel + 1)
                $result += [Environment]::NewLine + "$prefix  $value, "
            }

            $result = $result.Substring(0, $result.Length - 2)
            $result += [Environment]::NewLine + "$prefix)"
            $result
        }
        else {
            [String]$Obj
        }
    }
}


##################################################################################################################
# Classes
##################################################################################################################


<#
    Validates specified argument as a path to a container.
#>
class ValidateContainerPathAttribute : ValidateArgumentsAttribute
{
    [void] Validate([object]$arguments, [EngineIntrinsics]$engineIntrinsics)
    {
        if ([Object]::ReferenceEquals($arguments, $Null)) {
            throw [System.ArgumentNullException]::new()
        }

        $path = [String]$arguments

        if ([String]::IsNullOrWhiteSpace($path)) {
            throw [System.ArgumentException]::new('String cannot be empty nor contains only empty spaces.')
        }

        Join-Path $path '.'

        if (-not (Test-Path -Path $path -PathType Container)) {
            throw [System.ArgumentException]::new("Argument '$path' is not a valid path to an existing container.")
        }
    }
}


<#
    Validates specified argument as a path to a leaf.
#>
class ValidateLeafPathAttribute : ValidateArgumentsAttribute
{
    [void] Validate([object]$arguments, [EngineIntrinsics]$engineIntrinsics)
    {
        if ([Object]::ReferenceEquals($arguments, $Null)) {
            throw [System.ArgumentNullException]::new()
        }

        $path = [String]$arguments

        if ([String]::IsNullOrWhiteSpace($path)) {
            throw [System.ArgumentException]::new('String cannot be empty nor contains only empty spaces.')
        }

        Join-Path $path '.'

        if (-not (Test-Path -Path $path -PathType Leaf)) {
            throw [System.ArgumentException]::new('Argument is not a valid path to an existing leaf.')
        }
    }
}


<#
    Validates specified argument as a string of consecutive alphanumeric characters.
#>
class ValidateIdentifierAttribute : ValidateArgumentsAttribute
{
    [void] Validate([object]$arguments, [EngineIntrinsics]$engineIntrinsics)
    {
        if ([Object]::ReferenceEquals($arguments, $Null)) {
            throw [System.ArgumentNullException]::new()
        }

        $identifier = [String]$arguments

        if ([String]::IsNullOrWhiteSpace($identifier)) {
            throw [System.ArgumentException]::new('String cannot be empty nor contains only empty spaces.')
        }

        if ($identifier -notmatch '^[a-z_][a-z0-9_]*$') {
            throw [System.ArgumentException]::new('Specified string was not a correct identifier.')
        }
    }
}


<#
    Validates specified argument as an empty string or string of consecutive alphanumeric characters.
#>
class ValidateIdentifierOrEmptyAttribute : ValidateArgumentsAttribute
{
    [void] Validate([object]$arguments, [EngineIntrinsics]$engineIntrinsics)
    {
        if ([Object]::ReferenceEquals($arguments, $Null)) {
            throw [System.ArgumentNullException]::new()
        }

        $identifier = [String]$arguments

        if ([String]::IsNullOrEmpty($identifier)) {
            return
        }

        if ([String]::IsNullOrWhiteSpace($identifier)) {
            throw [System.ArgumentException]::new('String cannot be empty nor contains only empty spaces.')
        }

        if ($identifier -notmatch '^[a-z_][a-z0-9_]*$') {
            throw [System.ArgumentException]::new('Specified string was not a correct identifier.')
        }
    }
}


<#
    Validates specified argument as a path to a leaf or not existing entry.
#>
class ValidateNonContainerPathAttribute : ValidateArgumentsAttribute
{
    [void] Validate([object]$arguments, [EngineIntrinsics]$engineIntrinsics)
    {
        if ([Object]::ReferenceEquals($arguments, $Null)) {
            throw [System.ArgumentNullException]::new()
        }

        $path = [String]$arguments

        if ([String]::IsNullOrWhiteSpace($path)) {
            throw [System.ArgumentException]::new('String cannot be empty nor contains only empty spaces.')
        }

        Join-Path $path '.'

        if (Test-Path -Path $path -PathType Container) {
            throw [System.ArgumentException]::new('Argument cannot be a path to an existing container.')
        }
    }
}


<#
    Validates specified argument as a path to a container or not existing entry.
#>
class ValidateNonLeafPathAttribute : ValidateArgumentsAttribute
{
    [void] Validate([object]$arguments, [EngineIntrinsics]$engineIntrinsics)
    {
        if ([Object]::ReferenceEquals($arguments, $Null)) {
            throw [System.ArgumentNullException]::new()
        }

        $path = [String]$arguments

        if ([String]::IsNullOrWhiteSpace($path)) {
            throw [System.ArgumentException]::new('String cannot be empty nor contains only empty spaces.')
        }

        Join-Path $path '.'

        if (Test-Path -Path $path -PathType Leaf) {
            throw [System.ArgumentException]::new('Argument cannot be a path to an existing leaf.')
        }
    }
}


<#
    Validates specified argument as a PowerShell path.
#>
class ValidatePathAttribute : ValidateArgumentsAttribute
{
    [void] Validate([object]$arguments, [EngineIntrinsics]$engineIntrinsics)
    {
        if ([Object]::ReferenceEquals($arguments, $Null)) {
            throw [System.ArgumentNullException]::new()
        }

        $path = [String]$arguments

        if ([String]::IsNullOrWhiteSpace($path)) {
            throw [System.ArgumentException]::new('String cannot be empty nor contains only empty spaces.')
        }

        Join-Path $path '.'
    }
}


Export-ModuleMember -Function '*' -Variable '*' -Alias '*' -Cmdlet '*'

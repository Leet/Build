#requires -version 6

Set-StrictMode -Version 2

$ErrorActionPreference = 'Stop'
$WarningPreference     = 'Continue'

<#
.SYNOPSIS
Execute the given LeetBuild command.

.PARAMETER Command
The command to be executed.

.PARAMETER Arguments
Command arguments to be passed to the command.

.EXAMPLE
Invoke-LeetBuildCommand "msbuild" /t:Rebuild
#>
function Invoke-LeetBuild ( [String]   $RepositoryRoot ,
                            [String[]] $Arguments      ) {
}

Export-ModuleMember -Variable '*' -Alias '*' -Function '*' -Cmdlet '*'

<#
.SYNOPSIS
This script will build your project 

.Description
This script will build your project using MSBuild

.PARAMETER ProjectName
Name of the project that you want to build.

#>
param (    
    [Parameter(Mandatory=$true)]
    [string] $ProjectName
)

Install-Module  -Name Invoke-MsBuild

$BasePath = (Resolve-Path '..').Path
$ProjectPath = "$BasePath\$ProjectName\$ProjectName.csproj"
$BuildFlags = "/p:Configuration=Release /p:Platform=AnyCPU"

$buildResult = Invoke-MsBuild -Path $ProjectPath -MsBuildParameters "$BuildFlags" -ShowBuildOutputInCurrentWindow

if ($buildResult.BuildSucceeded -eq $true)
{
	Write-Host ("Build completed successfully in {0:N1} seconds." -f $buildResult.BuildDuration.TotalSeconds)
}
elseif ($buildResult.BuildSucceeded -eq $false)
{
	Write-Host ("Build failed after {0:N1} seconds. Check the build log file '$($buildResult.BuildLogFilePath)' for errors." -f $buildResult.BuildDuration.TotalSeconds)
}
elseif ($null -eq $buildResult.BuildSucceeded)
{
	Write-Host "Unsure if build passed or failed: $($buildResult.Message)"
}
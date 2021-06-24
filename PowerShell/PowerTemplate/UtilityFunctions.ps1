#requires -version 7
<#
.SYNOPSIS
  Utility Functions
.DESCRIPTION
  Contains several commonly used functions 
.NOTES
  Version:        1.0
  Author:         Shannon Barrett
  Creation Date:  04/08/2021
  Purpose/Change: Initial script development  

#>

<#
.SYNOPSIS
Get-Input prints colored output for user input
.DESCRIPTION
Will output the string message requesting user input and it will return the host response. 
Optionally you can specify background colors, foreground colors and if it the response will be a password.  

If the response is a password it will return a secure string. 

.PARAMETER Msg
The string that will be written to the host. 

.PARAMETER BackgroundColor
Specify the background color. Default is black. 

.PARAMETER ForegroundColor
Specify the foreground color. Default is dark green.

.PARAMETER IsPassword
Allows user to input a password value that will be masked and returned as a SecureString.

#>
function Get-Input() {
  param
  (
      [Parameter(Position = 0, ValueFromPipeline = $true)]
      [string]$Msg,
      [string]$BackgroundColor = "Black",
      [string]$ForegroundColor = "DarkGreen",
      [switch]$IsPassword = $false
  )

  Write-Host -ForegroundColor $ForegroundColor -NoNewline $Msg ": ";
  if ($IsPassword){
    return Read-Host -AsSecureString
  }  
    return Read-Host
}

<#
.SYNOPSIS
Prints colored banner with statement

.PARAMETER Statement
The string that will be written in the banner.

.PARAMETER BackgroundColor
Specify the background color. Default is black. 

.PARAMETER ForegroundColor
Specify the foreground color. Default is yellow.

.PARAMETER Width
The width of the banner. Default is 80. 

#>
function Write-Header()
{
    param(
      $Statement,
      $BackgroundColor = "Black",
      $ForegroundColor = "Yellow",
      $Width = 80
    )

    $newline = "`r`n"
    # create border
    $border = ""
    $border = $border.PadLeft($Width, '=')
    
    # add spacing to statement
    $Statement = $Statement.PadLeft($Statement.Length + 1,' ')
    $Statement = $Statement.PadRight($Statement.Length + 1,' ')
    $diff = $border.Length - $Statement.Length
    $lpad = $diff/2
    $rpad = $diff/2
    if ($diff % 2 -ne 0)
    {
        $lpad = ($diff + 1)/2
        $rpad = $lpad - 1
    }

    $fgc = $host.ui.RawUI.ForegroundColor
    $host.ui.RawUI.ForegroundColor = $ForegroundColor
    $bgc = $host.ui.RawUI.BackgroundColor
    $host.ui.RawUI.BackgroundColor = $BackgroundColor

    $lformated = $statement.PadLeft($statement.Length + $lpad,'=')
    $formated = $lformated.PadRight($lformated.Length + $rpad,'=')    
    $newline
    $border
    $formated
    $border
    $newline

    $host.ui.RawUI.ForegroundColor = $fgc
    $host.ui.RawUI.BackgroundColor = $bgc
}


<#
.SYNOPSIS
Confirms that a powershell module is available.

.DESCRIPTION
Confirm-Module will determine if the specified module is imported.  If the module is not imported it will attempt to install and import the module. 

.PARAMETER ModuleName
The name of the Powershell module that you'd like to confirm. 

#>
function Confirm-Module () {
  param(
    $ModuleName
    )
    # If module is imported say that and do nothing
    if (Get-Module | Where-Object {$_.Name -eq $ModuleName}) {
        write-host "Module $ModuleName is already imported."
    }
    else {

        # If module is not imported, but available on disk then import
        if (Get-Module -ListAvailable | Where-Object {$_.Name -eq $ModuleName}) {
            Import-Module $ModuleName #-Verbose
        }
        else {

            # If module is not imported, not available on disk, but is in online gallery then install and import
            if (Find-Module -Name $ModuleName | Where-Object {$_.Name -eq $ModuleName}) {
                Install-Module -Name $ModuleName -Force -Scope CurrentUser #-Verbose 
                Import-Module $ModuleName #-Verbose
            }
            else {

                # If module is not imported, not available and not in online gallery then abort
                write-host "Module $ModuleName not imported, not available and not in online gallery, exiting."
                EXIT 1
            }
        }
    }
}

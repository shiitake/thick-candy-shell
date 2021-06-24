#requires -version 2
<#
.SYNOPSIS
  This module creates a new script using a standard template
.DESCRIPTION
  This module will setup the basic stuff that you'll want in your script and will help you keep things organized. 
.PARAMETER Name
    The name of the new script.
.INPUTS
  <Inputs if any, otherwise state None>
.OUTPUTS
  <Outputs if any, otherwise state None - example: Log file stored in C:\Windows\Temp\<name>.log>
.NOTES
  Version:        1.0
  Author:         Shannon Barrett
  Creation Date:  11/25/2020
  Purpose/Change: Initial script development
  
.EXAMPLE
  <Example goes here. Repeat this attribute for more than one example>
#>

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#Set Error Action to Silently Continue
$ErrorActionPreference = "SilentlyContinue"

#Dot Source required Function Libraries
# . "C:\Scripts\Functions\Logging_Functions.ps1"

#----------------------------------------------------------[Declarations]----------------------------------------------------------

#Script Version
$sScriptVersion = "1.0"

#Log File Info
$FileLoggingEnabled = $true

#User Input Info
$IncludeUserInput = $false

#-----------------------------------------------------------[Functions]------------------------------------------------------------

function Get-Input() {
    param
    (
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [string]$msg,
        [string]$BackgroundColor = "Black",
        [string]$ForegroundColor = "DarkGreen"
    )

    Write-Host -ForegroundColor $ForegroundColor -NoNewline $msg ": ";
    return Read-Host
}

Function Add-HeaderSection {
  param (
    $Name,
    $Author
    )
  $CreateDate = Get-Date -Format "MM/dd/yyyy"
  
  $Header = "#requires -version 2
<#
.SYNOPSIS
  $Name - <Overview of script>
.DESCRIPTION
  <Brief description of script>
.PARAMETER <Parameter_Name>
  <Brief description of parameter input required. Repeat this attribute if required>
.INPUTS
  <Inputs if any, otherwise state None>
.OUTPUTS
  <Outputs if any, otherwise state None - example: Log file stored in C:\Windows\Temp\<name>.log>
.NOTES
  Version:        1.0
  Author:         $Author
  Creation Date:  $CreateDate
  Purpose/Change: Initial script development
  
.EXAMPLE
  <Example goes here. Repeat this attribute for more than one example>
#>

"
  return $Header
}

Function Add-InitializationsSection {
  $section = "
#---------------------------------------------------------[Initializations]--------------------------------------------------------

#Set Error Action to Silently Continue
`$ErrorActionPreference = `"SilentlyContinue`"

#Dot Source required Function Libraries
# . `"C:\Scripts\Functions\Logging_Functions.ps1`"

"
  return $section

}

Function Add-DeclarationsSection { 
  param (
    $Name,
    $FileLoggingEnabled
    )
  $sb = [System.Text.StringBuilder]::new()
  $section = "  
#----------------------------------------------------------[Declarations]----------------------------------------------------------

#Script Version
`$sScriptVersion = `"1.0`"

"
  [void]$sb.Append($section)
  if ($FileLoggingEnabled)
  {
    $logging = "
#Log File Info
`$sLogPath = Resolve-Path -Path .
`$sLogName = `"`$Name.log`"
`$sLogFile = Join-Path -Path `$sLogPath -ChildPath `$sLogName

"
    [void]$sb.Append($logging)
  }
  return $sb.ToString()
}

Function Add-FunctionSection {
  param (
    $FileLoggingEnabled,
    $IncludeUserInput    
    )
  $sb = [System.Text.StringBuilder]::new()
  $section = "  
#-----------------------------------------------------------[Functions]------------------------------------------------------------

"
  [void]$sb.Append($section)
  if ($IncludeUserInput)
  {
    $inputfunction = "
function Get-Input() {
  param
  (
      [Parameter(Position = 0, ValueFromPipeline = `$true)]
      [string]`$msg,
      [string]`$BackgroundColor = `"Black`",
      [string]`$ForegroundColor = `"DarkGreen`"
  )

  Write-Host -ForegroundColor `$ForegroundColor -NoNewline `$msg `": `";
  return Read-Host
}

"
  [void]$sb.Append($inputfunction)
  }

  if ($FileLoggingEnabled) {
    $logging = "
function Write-Log {
  param (
    [Parameter(Mandatory=`$False, Position=0)]
    [String]`$Entry
  )
  `"`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') `$Entry`" | Out-File -FilePath `$sLogFile -Append
}
    
"
    [void]$sb.Append($logging)
  }
  $sampleFunction = "
<#
Function <FunctionName>{
  Param()
  
  Begin{
    Log-Write -LogPath `$sLogFile -LineValue `"<description of what is going on>...`"
  }
  
  Process{
    Try{
      <code goes here>
    }
    
    Catch{
      Log-Error -LogPath `$sLogFile -ErrorDesc `$_.Exception -ExitGracefully `$True
      Break
    }
  }
  
  End{
    If($?){
      Log-Write -LogPath `$sLogFile -LineValue `"Completed Successfully.`"
      Log-Write -LogPath `$sLogFile -LineValue `" `"
    }
  }
}
#>

"
  [void]$sb.Append($sampleFunction)
  return $sb.ToString()
}

Function Add-ExecutionSection {
  return "
#-----------------------------------------------------------[Execution]------------------------------------------------------------
#Script Execution goes here


"

}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

function New-Script {
  param (
      $Name,
      $Author
    )
  if (!$Name) {
    $NamePrompt = Get-Input "Please enter the name of the script."
    if ($NamePrompt.Length -gt 0){
      $Name = $NamePrompt
    }
  }
  if (!$Author) {
    $UserPrompt = Get-Input "Please enter the name of the script author (that's probably you!)"
    if ($NamePrompt.Length -gt 0 ){
      $Author = $NamePrompt
    } else {
      $Author = 'N/A'
    }
  }

  $sb = [System.Text.StringBuilder]::new()
  $header = Add-HeaderSection $Name $Author
  [void]$sb.Append($header)
  $initialization = Add-InitializationsSection
  [void]$sb.Append($initialization)
  $FileLoggingPrompt = Get-Input "Do you want to enable file logging? (Y/N)"
  if ($FileLoggingPrompt.ToLower() -eq 'n')
  {
    $FileLoggingEnabled = $false
  }
  $UserInputPrompt = Get-Input "Will your script prompt a user for input? (Y/N)"
  if ($UserInputPrompt.ToLower() -eq 'y')
  {
    $IncludeUserInput = $true
  }
  $declarations = Add-DeclarationsSection $Name $FileLoggingEnabled
  [void]$sb.Append($declarations)
  $functions = Add-FunctionSection $FileLoggingEnabled $IncludeUserInput
  [void]$sb.Append($functions)
  $execution = Add-ExecutionSection
  [void]$sb.Append($execution)
  [void]$sb.Append( 'Write-Host "Hello World"')
  # $sb.ToString()

  # create script fle
  $ScriptPath = Join-Path -Path (Resolve-Path -Path .) -ChildPath "$Name.ps1"
  $sb.ToString() | Out-File -FilePath $ScriptPath

}
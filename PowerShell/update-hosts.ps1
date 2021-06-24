param([switch]$Elevated)

function Test-Admin {
  $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
  $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

if ((Test-Admin) -eq $false)  {
    if ($elevated) 
    {
        # tried to elevate, did not work, aborting
    } 
    else {
        Start-Process powershell.exe -Verb RunAs -ArgumentList ('-noprofile -noexit -file "{0}" -elevated ' -f ($myinvocation.MyCommand.Definition))
    }
    exit
}
'Running with full privileges'
$hostsPath = "C:\Windows\System32\drivers\etc\hosts"

$azureSectionHeader = "# Azure Hosts #"
$azureSectionFooter = "# End Azure #"

function AddLine($hostsPath, $line, $value)
{
    add-content -Path $hostsPath -Value $value
    

}

function AddFooter
{

}
# check for azure azureSectionHeader
$headerLine = (sls $azureSectionHeader $hostsPath).LineNumber
$footerLine = (sls $azureSectionFooter $hostsPath).LineNumber
if (!$headerLine)
{
    # no header     
    add-content -Path $hostsPath -Value "`n`n$azureSectionHeader"    
    $headerLine = (sls $azureSectionHeader $hostsPath).LineNumber
    
}
if (!$footerLine)
{
    add-content -Path $hostsPath -Value "`n$azureSectionFooter"
    $footerLine = (sls $azureSectionFooter $hostsPath).LineNumber
}

Write-Host "Header at line: $headerLine"
Write-Host "Footer at line: $footerLine"



# (Get-Content $hostsFile -Raw) | 
 #   Foreach-Object {
     #   $_  
    #}

        # -replace '10.3.4.53','#10.3.4.53' | Set-Content -Path C:\Windows\System32\drivers\etc\hosts

# Sleep 2

# Stop-Process -Name "powershell"

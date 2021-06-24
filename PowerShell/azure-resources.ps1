
<#
.SYNOPSIS
This script will connect to your Azure subscription and will print out the resource group info.

.Description
This script will connect to your Azure subscription and print resource group info.

For each of the resource groups it should print the resource name, location and type.

If you don't have the required modules it will attempt to download and install them.

#>


function Load-Module ($m) {
    # If module is imported say that and do nothing
    if (Get-Module | Where-Object {$_.Name -eq $m}) {
        write-host "Module $m is already imported."
    }
    else {

        # If module is not imported, but available on disk then import
        if (Get-Module -ListAvailable | Where-Object {$_.Name -eq $m}) {
            Import-Module $m #-Verbose
        }
        else {

            # If module is not imported, not available on disk, but is in online gallery then install and import
            if (Find-Module -Name $m | Where-Object {$_.Name -eq $m}) {
                Install-Module -Name $m -Force -Scope CurrentUser #-Verbose 
                Import-Module $m #-Verbose
            }
            else {

                # If module is not imported, not available and not in online gallery then abort
                write-host "Module $m not imported, not available and not in online gallery, exiting."
                EXIT 1
            }
        }
    }
}

function MakeTitle($statement, $width)
{
    $newline = "`r`n"
    # create border
    $border = ""
    $border = $border.PadLeft($width, '=')

    
    # add spacing to statement
    $statement = $statement.PadLeft($statement.Length + 1,' ')
    $statement = $statement.PadRight($statement.Length + 1,' ')
    $diff = $border.Length - $statement.Length
    $lpad = $diff/2
    $rpad = $diff/2
    if ($diff % 2 -ne 0)
    {
        $lpad = ($diff + 1)/2
        $rpad = $lpad - 1
    }

    $t = $host.ui.RawUI.ForegroundColor
    $host.ui.RawUI.ForegroundColor = "Yellow"

    $lformated = $statement.PadLeft($statement.Length + $lpad,'=')
    $formated = $lformated.PadRight($lformated.Length + $rpad,'=')
    $newline
    $border
    $formated
    $border
    $newline

    $host.ui.RawUI.ForegroundColor = $t
}

function Verify-Connected() {
    try {
        if (Get-AzContext) {
            return $true
        }
        else {
            return $false
        }
    }
    catch 
    {
        Write-Host "There was a problem checking your Azure credentials. "
        Write-Host $_
        return $false        
    }
    
}

# Work starts Here
# Requires installation of Az PowerShell Module
$TitleWidth = 100
Write-Host "Checking for required PowerShell Modules."
Load-Module "Az"

$isConnected = Verify-Connected
if (!$isConnected) {
    Write-Host "You need to sign in to your Azure account to run this script. Please run `Connect-AzAccount` and then run this script again."
    EXIT 1
}

$SubscriptionId
try {

    $groups = Get-AzResourceGroup

    if ($groups.Count -gt 0) {
        
        MakeTitle "Resource Groups" $TitleWidth

        $groups | ForEach-Object {
        $resourceGroup = $_.ResourceGroupName
        $location = $_.Location
        MakeTitle "Resource Group: $resourceGroup (Location: $location)" $TitleWidth

        Get-AzResource -ResourceGroupName $resourceGroup | ft Name, ResourceType -AutoSize
        }
    } 
    else {
        Write-Host "No resource groups found"
    }
} 
catch {

    Write-Error "We had a problem retrieving your azure resources. "
    Write-Host $_                
    EXIT 1
}

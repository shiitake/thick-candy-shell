<#
.SYNOPSIS
This script will set up your local SQL Server instance running at localhost and populate it with data from an azure environment.

.Description
This script connects to localhost using the default sa login created through docker compose. It will prompt the user for credentials to create a new sql login and will prepare the server in import data. 

It will then prompt the user for the database credentials for your azure environment. It will create a temporary copy of your database in the azure environment to prevent concurrency errors that are common when downloading a live database. It will 
then download a backup and save it to a file called DevExport.bacpac. Afte downloading this file it will import it into the local sql server as MyDb-Local. Once that has been completed it will delete the temporary database.

.PARAMETER Database
(Alias db) Default = MyDb
Specify which database to download. 

.PARAMETER Environment
(Alias env) Default = Dev
Specify which environment you want to download. Options are Dev and QA

.PARAMETER SkipDownload
(Alias s, skip)
Skip downloading the bacpac file and will attempt to install from an existing bacpac. 

.PARAMETER SkipCopy
(Alias sc)
Skip creating a temporary copy of the database. 

.PARAMETER SkipLogin
(Alias sl)
Skip creating a new login on your local database.
#>

param (
    [Alias ("db")]
    [string]$Database = "MyDb",
    [Alias ("env")]
    [string]$Environment = "Dev",
    [Alias ("s", "Skip")]
    [switch]$SkipDownload = $false,
    [Alias ("sc")]
    [switch]$SkipCopy = $false,    
    [Alias ("sl")]
    [switch]$SkipLogin = $false
)

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

function Write-Header($statement, $width)
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
    $newline
    $border
    $formated
    $border
    $newline

    $host.ui.RawUI.ForegroundColor = $t
}


function Confirm-Module ($m) {
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

function Create-Temporary-Copy($dbName, $tempDb, $servername, $resourceGroupName, $elasticPoolName) {       
    try  
    {
        Write-Host "Temporary database being created: $tempDb"        
        $databaseCopy = New-AzSqlDatabaseCopy -ServerName $serverName -CopyDatabaseName $tempDb -DatabaseName $dbName -ResourceGroupName $resourceGroupName -ElasticPoolName $elasticPoolName
        return $true
    }
    catch
    {
        Write-Host "There was a problem copying the $dbName database"
        Write-Host $_
        return $false
    }

}

function Delete-Temporary-Copy($tempDb, $serverName, $resourceGroupName) {        
    try 
    {      
        $databaseRemoved = Remove-AzSqlDatabase -DatabaseName $tempDb -ServerName $serverName -ResourceGroupName $resourceGroupName
        return $true
    }
    catch
    {
        Write-Host "There was a problem deleting the temp database. You may have to do that manually through the portal."
        Write-Host $_
        return $false
    }

}


# It all starts here
$HeaderWidth = 60

Write-Host "Checking for required PowerShell Modules."
Confirm-Module "SqlServer"
Confirm-Module "Az"

$isConnected = Verify-Connected
if (!$isConnected) {
    Write-Host "You need to sign in to your Azure account to run this script. Please run `Connect-AzAccount` and then run this script again."
    EXIT 1
}

$cred = Get-Credential -Message "Enter login name and password you'd like to use on the local sql server."
$UserName = $cred.GetNetworkCredential().UserName
$Password = $cred.GetNetworkCredential().Password

if (!$SkipLogin)
{
    Write-Header "Creating new user login" $HeaderWidth    

    $query = @'
CREATE LOGIN {0} WITH PASSWORD='{1}', DEFAULT_DATABASE=[master], CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF
GO
ALTER SERVER ROLE [sysadmin] ADD MEMBER {2}
GO
SP_CONFIGURE 'show advanced options', 1
GO
RECONFIGURE
GO
SP_CONFIGURE 'CONTAINED DATABASE AUTHENTICATION', 1
GO
RECONFIGURE
GO
SP_CONFIGURE 'show advanced options', 0 
GO
RECONFIGURE
GO
'@ -f $UserName,$Password.ToString(),$UserName

    try
    { 
        Invoke-Sqlcmd -ServerInstance "localhost" -username sa -password 'sa_password!!123' -Database "Master" -Query $query
        Write-Host "New login created: $UserName"
    }
    catch
    {
        Write-Host "There was a problem creating the new login. You might have to create the login manually in SSMS" -ForegroundColor yellow    
        EXIT 1
    }
}
else {
    Write-Host "Skipping login creation"
}

# make copy of database
$rand = Get-Random
$TempDB = "$Database-Tmp-$rand"
$resourceGroupName = "MyResourceGroup"
$sourceServerName = "development"
$elasticPoolName = "My-Pool"
$isCleanedUp = $false

if ($skipCopy) {
    $TempDB = Get-Input "Please input name of temporary database we should use. (It should have been logged in a previous run.)"
    $deleteTmpDb = Get-Input "Do you want to delete this temporary database when we finish copying it (Y/N)? Default: yes "
    if ($deleteTmpDb.ToLower() -eq "n") {
        $isCleanedUp = $true
    }
}
else {
    Write-Header "Creating Temp database" $HeaderWidth
    $DevDB = "$Database-Dev"
    $copyFinished = Create-Temporary-Copy $DevDB $TempDB $sourceServerName $resourceGroupName $elasticPoolName
    if (!$copyFinished) {
        EXIT 1
    }    
}

$CMD = "SqlPackage.exe"
$BacpacFile = "$Database-Export.bacpac"

if ($skipDownload)
{
    Write-Host "Skipping download and will look for $BacpacFile to import "
}
else 
{
    Write-Header "Downloading latest copy of the $Database database" $HeaderWidth    

    $sqlCred = Get-Credential -Message "Enter the credentials for the $Database database"
    $SqlUserName = $sqlCred.GetNetworkCredential().UserName
    $SqlPassWord = $sqlCred.GetNetworkCredential().Password

    $ConnectionString = "Server=tcp:MyDb.database.windows.net,1433;Initial Catalog=$TempDB;Persist Security Info=False;User ID=$SqlUserName;Password=$SqlPassWord;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

    $action = "/a:Export"
    $file = "/tf:$BacpacFile"
    $connection = "/scs:$ConnectionString"
    $ua = "/ua:False"
    try 
    {
        & $CMD $action $file $connection $ua
    }
    catch
    {
        Write-Error "We couldn't download the database correctly."
        Write-Host $_                
        EXIT 1
    }
    finally 
    {
        if (!$isCleanedUp) {            
            Write-Header "Deleting Temp database" $HeaderWidth
            Delete-Temporary-Copy $TempDB $sourceServerName $resourceGroupName
            $isCleanedUp = $true
        }        
    }
}

Write-Header "Importing to local database" $HeaderWidth
$action = "/a:Import"
$server = "/tsn:localhost"
$database = "/tdn:$Database-Local"
$file = "/sf:$BacpacFile"
$user = "/tu:$UserName"
$pw = "/tp:$Password"

try 
{
    & $CMD $action $file $server $database $user $pw
}
catch
{
    Write-Error "We weren't able to import the database correctly"
    Write-Host $_
}
finally 
{
    if (!$isCleanedUp) {
        Write-Header "Cleaning up temporary database" $HeaderWidth
        Delete-Temporary-Copy $TempDB $sourceServerName $resourceGroupName
    }    
}
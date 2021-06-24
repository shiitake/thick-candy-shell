<#
.SYNOPSIS
Apply database migrations using the ef6.exe binary.

.Description
This script is a wrapper for the ef6.exe binary. It will build the project, copy the ef6.exe binary to the solution directory and then will run the command using some predefined parameters.

It is similar to running the 'Update-Database' command in Visual Studio but the commands are slightly different. The server and database names are hardcoded but you will be required to enter the username and password.

It defaults to running with verbose output. To surpress this you can use the quiet parameter.

.PARAMETER Environment
(Alias env, e) This specifies which environment you're wanting to run on. The options are "dev", "prod", "qa". The default value is "local".
For non-local environments you will be prompted for a valid username and password to connect to the database. 

.PARAMETER Target
(Alias t) Specify a migration that you'd like to target.

.PARAMETER Username
(Alias u) Specify the database login to use.

.PARAMETER Password
(Alias p) Specify the database password to use. NOTE: you will need to pass in a SecureString for the parameter to work. See the example below. 

.PARAMETER SkipBuild
(Alias s, skip)  Skip the project build process. 

.PARAMETER Force
(Alias f) Force an update in a situation where they may be data loss. Default value is false.

.PARAMETER Debug
(Alias d) Do not run the migration but display the connection string and ef6.exe command parameters. Default value is false. 

.PARAMETER Quiet
(Alias q) Do not display verbose output from migrate command. 


.EXAMPLE
PS> .\update-database.ps1 -env prod -target MyLastMigration -force -test

Running migration on Production
Input database username. : testUser
Input database password. : userPass
Connecton string:  Server=tcp:Production.database.windows.net,1433;database=ProdDb;User ID=testUser;Password=userPass;Trusted_Connection=False;
Migration command:
C:\git\MyProject\bin\ef6.exe MyProject.dll /targetMigration='MyLastMigration' /startupDirectory='C:\git\MyProject\bin\' /connectionString='Server=tcp:Production.database.windows.net,1433;database=ProdDb;User ID=testUser;Password=userPass;Trusted_Connection=False;' /connectionProviderName='System.Data.SqlClient' /startupConfigurationFile=C:\git\MyProject\bin\MyProject.dll.config /verbose /force

#>

param (
    [Alias("env", "e")]
    [string] $Environment = "local",
    [Alias("t")]
    [string] $Target,
    [Alias("u")]
    [string] $UserName,
    [Alias("p")]
    [SecureString] $Password,
    [Alias("s", "skip")]
    [switch] $SkipBuild = $false,
    [Alias("f")]
    [switch] $Force = $false,
    [Alias("d")]
    [switch] $Debug = $false,
    [Alias("q")]
    [switch] $Quiet = $false
)

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


function take_input() {
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

function BuildProject($ProjectPath, $Quiet)
{
    Write-Host "Building project"
    Load-Module "Invoke-MsBuild"
    $BuildFlags = "/p:Configuration=Release /p:Platform=AnyCPU"
    
    if ($Quiet)
    {
        $buildResult = Invoke-MsBuild -Path $ProjectPath -MsBuildParameters "$BuildFlags"
    }
    else
    {
        $buildResult = Invoke-MsBuild -Path $ProjectPath -MsBuildParameters "$BuildFlags" -ShowBuildOutputInCurrentWindow
    }
    
    if ($buildResult.BuildSucceeded -eq $true)
    {
        Write-Host ("Build completed successfully in {0:N1} seconds." -f $buildResult.BuildDuration.TotalSeconds)
        return $true
    }
    elseif ($buildResult.BuildSucceeded -eq $false)
    {
        Write-Host ("Build failed after {0:N1} seconds. Check the build log file '$($buildResult.BuildLogFilePath)' for errors." -f $buildResult.BuildDuration.TotalSeconds)
        return $false
    }
    elseif ($null -eq $buildResult.BuildSucceeded)
    {
        Write-Host "Unsure if build passed or failed: $($buildResult.Message)"
        return $false
    }
}

# It all starts here
$ConnStr = ""

# Check for db credentials
if (($Environment.ToLower() -ne "local") -and ((!$UserName) -or (!$Password)))
{
    $cred = Get-Credential -Message "Input username and password"
    $UserName = $cred.GetNetworkCredential().UserName
    $Password = $cred.GetNetworkCredential().SecurePassword
}

switch($Environment.ToLower())
{
    "prod" { 
        $serverName = "production.database.windows.net"
        $databaseName = "ProdDb"
        Break }
    "qa" { 
        $serverName = "qa.database.windows.net"
        $databaseName = "QaDb"
        Break }
    "dev" { 
        $serverName = "dev.database.windows.net"
        $databaseName = "DevDb"
        Break }        
    default { 
        $username = "sa"
        $Password = ConvertTo-SecureString -String 'password!!1' -AsPlainText
        $serverName = "localhost"
        $databaseName = "LocalDb"
        Break }
}

$PlainPass = ConvertFrom-SecureString -SecureString $Password -AsPlainText

if ($Debug) { 
    $SkipBuild = $true
    Write-Host "Debug mode: Passwords will be obfuscated." -ForegroundColor Green
    $ConnStr =  "Server=tcp:$serverName,1433;database=$databaseName;User ID=$UserName;Password=********;Trusted_Connection=False;"
    Write-Host "Connecton string:  $ConnStr" 
}
else {
    $ConnStr =  "Server=tcp:$serverName,1433;database=$databaseName;User ID=$UserName;Password=$PlainPass;Trusted_Connection=False;"
}


$BasePath = (Resolve-Path '..').Path
$Project = "MyProject"

# ToolsPath is location of ef6.exe
$ToolsPath = "$BasePath\deploy\"

# startup directory needs to be location of assembly
$StartupDirectory = "$BasePath\$Project\bin"

$Migrator = $StartupDirectory + '\ef6.exe'
$Assembly = "$StartupDirectory\$Project.dll"
$ConfigFile = "$StartupDirectory\$Assembly.config"

$ConnProvider = "System.Data.SqlClient"

$DataDirectory = "$BasePath\$Project\App_Data"

$WebConfigFile = "$BasePath\$Project\Web.config"

$MigrationTarget = ""
if ($Target) {
   $MigrationTarget = "--target='$target'" 
}

$ForceMigration = ""
if ($Force) {
    $ForceMigration = "--force"
}

$IsVerbose = "--verbose"
if ($Quiet) {
    $IsVerbose = ""
}

try
{
    # Make sure that project has been built  
    if($SkipBuild) 
    {
        Write-Host "Skipping build."
    }
    else 
    {
        $ProjectPath = "$BasePath\$Project\$Project.csproj"
        $DidBuildSucceed = BuildProject $ProjectPath $Quiet
        if (!$DidBuildSucceed) 
        {
            $continue = take_input "There was a problem building the project. Press Y to continue?"
            if ($continue.ToLower() -ne "y")
            {
                Write-Host "Cancelling update."
                EXIT 1
            }
        }
    }   


    Write-Host "Starting migration"
    # copy file to bin location
    Copy-Item "ef6.exe" -Destination $StartupDirectory

    $migrateCommand = "$Migrator database update --assembly '$Assembly' $MigrationTarget --data-dir '$DataDirectory' --root-namespace $Project --connection-string '$ConnStr' --connection-provider '$ConnProvider' --config '$WebConfigFile' $IsVerbose $ForceMigration --prefix-output"

    if ($Debug) { 
        Write-Host "Migration command: "
        Write-Host $migrateCommand
    }
    else {
        Invoke-Expression $migrateCommand
    }

}
catch
{
    Write-Error "We couldn't run the migration"
    Write-Host $_
    EXIT 1
}

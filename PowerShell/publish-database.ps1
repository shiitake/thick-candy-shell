#requires -version 7
<#
.SYNOPSIS
This script helps publish database changes using the SqlPackage.exe binary.

.Description
This script will build the database project, copy the migrate.exe binary to the solution directory and then will run the command using some predefined parameters.

It is similar to running the Publish option in  Visual Studio but the commands are slightly different. The server and database names are hardcoded but you will be required to enter the username and password.

It defaults to running with verbose output. To surpress this you can use the quiet parameter.

.PARAMETER Environment
(Alias env, e) This specifies which environment you're wanting to run on. The options are "dev", "prod", "qa". The default value is "local".
For non-local environments you will be prompted for a valid username and password to connect to the database. 

.PARAMETER SciptOnly 
(Alias script, s) This will generate the publish script without publishing any changes to the database.

.PARAMETER SkipBuild
(Alias sb, skip)  This allow you to skip the project build process. 

.PARAMETER UserName
(Alias u)  This allows you to specify the database login to use.

.PARAMETER PASSWORD
(Alias p)  This allows you to specify the database password to use. Note:  You will need to pass in a SecureString for the paramater to work. See the example below.

.PARAMETER Force
(Alias f) Allows you to force an update in a situation where they may be data loss. Default value is false.

.PARAMETER Debug
(Alias d) This will not run the migration but will display the connection string and SqlPackage.exe command parameters. Default value is false. 

.PARAMETER Quiet
(Alias q) Will not display verbose output from migrate command. 

.EXAMPLE
PS> .\publish-database.ps1 -env prod -force -quiet

=======================================================
=========== Building database project =================
=======================================================
Build completed successfully in 1.5 seconds. 
=======================================================
======= Publishing dacpac file to prod database =======
=======================================================
Generating publish script for database 'MyDb' on server 'tcp:localhost,1433'.
Initializing deployment (Start)
Initializing deployment (Complete)
Analyzing deployment plan (Start)
Analyzing deployment plan (Complete)
Reporting and scripting deployment plan (Start)
Reporting and scripting deployment plan (Complete)
Updating database (Start)
Update complete
Updating database (Complete)
Successfully published database.
Time elapsed 0:02:53.80

.EXAMPLE 

PS> .\publish-database.ps1 -env prod -username sa -password (ConvertTo-SecureString sa_password!!123 -AsPlainText)

#>

param (
    [Alias("env", "e")]
    [string] $Environment = "local",
    [Alias("s", "script")]
    [switch] $ScriptOnly = $false,
    [Alias("sb", "skip")]
    [switch] $SkipBuild = $false,
    [Alias("u")]
    [string] $UserName,
    [Alias("p")]
    [SecureString] $Password,
    [Alias("f")]
    [switch] $Force = $false,
    [Alias("d")]
    [switch] $Debug = $false,
    [Alias("q")]
    [switch] $Quiet = $false
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


function BuildProject($ProjectPath, $Quiet)
{
    Confirm-Module "Invoke-MsBuild"
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
$HeaderWidth = 60

# Check for db credentials
if (($Environment.ToLower() -ne "local") -and ((!$UserName) -or (!$Password)))
{
    $cred = Get-Credential -Message "Input database and username."
    $UserName = $cred.GetNetworkCredential().UserName
    $Password = $cred.GetNetworkCredential().SecurePassword
}

$ConnStr = ""
switch($Environment.ToLower())
{
    "prod" { 
        $serverName = "prouction.database.windows.net"
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
    Write-Host "Debug mode. Passwords will be obfuscated." -ForegroundColor Green
    $ConnStr =  "Server=tcp:$serverName,1433;database=$databaseName;User ID=$UserName;Password=********;Trusted_Connection=False;"
    Write-Host "Connecton string:  $ConnStr"
}
else {
    $ConnStr =  "Server=tcp:$serverName,1433;database=$databaseName;User ID=$UserName;Password=$PlainPass;Trusted_Connection=False;"
}

$BasePath = (Resolve-Path '..').Path
$Project = "MyDatabase"

try 
{
    if($SkipBuild) 
    {
        Write-Host "Skipping build."
    }
    else 
    {
        $statement = "Building database project"
        Write-Header $statement $HeaderWidth
        $ProjectPath = "$BasePath\$Project\$Project.sqlproj"
        $DidBuildSucceed = BuildProject $ProjectPath $Quiet
        if (!$DidBuildSucceed) 
        {
            $continue = Get-Input "There was a problem building the project. Press Y to continue?"
            if ($continue.ToLower() -ne "y")
            {
                Write-Host "Cancelling update."
                EXIT 1
            }
        }
    }   

    $statement = "Publishing dacpac file to $Environment database"
    Write-Header $statement $HeaderWidth

    $CMD = "SqlPackage.exe"
    $DacPacFile = "$Basepath\$Project\bin\Release\$Project.dacpac" 

    $scriptPath = "publish-script.sql"

    $action = "/a:Publish"
    if ($ScriptOnly) {
        $action = "/a:Script"
    }
    $file = "/sf:$DacPacFile"
    $connection = "/tcs:$ConnStr"
    $ua = "/ua:False"
    $extra = "/dsp:$scriptPath"
    $properties = "/p:ExcludeObjectType=Users"

    $AllowDataLoss = ""
    if ($Force) {
        $AllowDataLoss = "/p:BlockOnPossibleDataLoss=False"
    }

    $IsVerbose = ""
    if ($Quiet) {
        $IsVerbose = "/q"
    }

    if($Debug)
    {
        Write-Host "SQL Command: $CMD $action $file $connection $ua $extra $properties $AllowDataLoss $IsVerbose"
    }
    else
    {
        & $CMD $action $file $connection $ua $extra $properties $AllowDataLoss $IsVerbose
    }
}
catch
{
    Write-Error "We couldn't publish the database correctly."
    Write-Host $_                
    EXIT 1
}

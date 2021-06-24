<#
.SYNOPSIS
Create new database migrations using the ef6.exe binary.

.Description
This script is a wrapper for the ef6.exe binary. It will build the project, copy the ef6.exe binary to the solution directory and then create a new migraiton against the database specified database.

It is similar to running the 'Add-Migration' command in Visual Studio but the commands are slightly different. The server and database names are hardcoded but you will be required to enter the username and password.

It defaults to running with verbose output. To surpress this you can use the quiet parameter.

.PARAMETER Environment
(Alias env, e) This specifies which environment you're wanting to run on. The options are "dev", "prod", "qa". The default value is "local".
For non-local environments you will be prompted for a valid username and password to connect to the database. 

.PARAMETER Name 
(Alias n) The name of the new migration you'll be creating. If the migration already exists it will re-scaffold it.

.PARAMETER Username
(Alias u) Specify the database login to use.

.PARAMETER Password
(Alias p) Specify the database password to use. NOTE: you will need to pass in a SecureString for the parameter to work. See the example below. 

.PARAMETER SkipBuild
(Alias s, skip)  Skip the project build process. 

.PARAMETER ListMigrations
(Alias l, list)  List the most recent migrations applied. 

.PARAMETER Count
(Alias c)  How many migrations to display. Default is 10.

.PARAMETER Force
(Alias f) Force an update in a situation where they may be data loss. Default value is false.

.PARAMETER Debug
(Alias d) Do not run the migration but will display the connection string and ef6.exe command parameters. Default value is false. 

.PARAMETER Quiet
(Alias q) Do not display verbose output from migrate command. 

.EXAMPLE
PS> .\add-migration.ps1 -env prod -name MyLastMigration -force -debug

Creating new migration on Production
Input database username. : testUser
Input database password. : userPass
Connecton string:  Server=tcp:production.database.windows.net,1433;database=ProdDb;User ID=testUser;Password=userPass;Trusted_Connection=False;
Migration command:
C:\git\MyProject\bin\ef6.exe MyProject.dll /targetMigration='MyLastMigration' /startupDirectory='C:\git\MyProject\bin\' /connectionString='Server=tcp:production.database.windows.net,1433;database=ProdDb;User ID=testUser;Password=userPass;Trusted_Connection=False;' /connectionProviderName='System.Data.SqlClient' /startupConfigurationFile=C:\git\MyProject\bin\\MyProject.dll.config /verbose /force

.EXAMPLE 
PS> .\update-database.ps1 -env prod -username sa -password (ConvertTo-SecureString sa_password!!123 -AsPlainText)


#>


param (
    [Alias("env", "e")]
    [string] $Environment = "local",    
    [Alias("n")]
    [string] $Name,
    [Alias("u")]
    [string] $UserName,
    [Alias("p")]
    [SecureString] $Password,
    [Alias("s", "skip")]
    [switch] $SkipBuild = $false,
    [Alias("l", "list")]
    [switch] $ListMigrations = $false,
    [Alias("c")]
    [int] $Count = 10,
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

function Get-MigrationList($MigrateCommand)
{
        $result = (Invoke-Expression $MigrateCommand) 2> $null
        
        $migList = [System.Collections.ArrayList]@()                        
        $matchPattern = '202[0-9]{12}_[\w-]*'
        $migList = $result | select-string -pattern $matchPattern -AllMatches |
            % { $_.Matches.Groups[0].value.Trim() } |
            sort $_ -Descending
        
        return $migList        
}

# It all starts here
$ConnStr = ""
if (!$ListMigrations -and !$Name)
{
    $Name = take_input "Please enter the name of the migration you want to create."
    if (!$Name)
    {
        Write-Host "Invalid name."
        EXIT 1
    }
}

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
$ProjectPath = "$BasePath\$Project\$Project.csproj"
$ForceMigration = ""
if ($Force) {
    $ForceMigration = " --force"
}

$IsVerbose = " --verbose"
if ($Quiet) {
    $IsVerbose = ""
}

if ($ListMigrations) {
    $SkipBuild = $true
    $MigrationAction = "migrations list --project-dir='$BasePath\$Project'"
} 
else {
   $MigrationAction = "migrations add $Name --project-dir='$BasePath\$Project'"
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

    $migrateCommand = "$Migrator $MigrationAction --assembly '$Assembly' --data-dir '$DataDirectory' --root-namespace $Project --connection-string '$ConnStr' --connection-provider '$ConnProvider' --config '$WebConfigFile' $IsVerbose $ForceMigration"

    if (!$ListMigrations) {
        $migrateCommand += " --prefix-output --json"
    }

    if ($Debug) { 
        Write-Host "Migration command: "
        Write-Host $migrateCommand
    }

    elseif ($ListMigrations) {
        $MigrationList = Get-MigrationList $MigrateCommand     
        
        Write-Host "Most recent migrations:"
        $Range = $Count -1
        if ($Range -gt $MigrationList.Count - 1)
        {
            $Range = ($MigrationList.Count -1)
        }
        $MigrationList[0..$Range] | sort $_
            % { Write-Host $_ }        
    }

    else {            
        Invoke-Expression $migrateCommand | Tee-Object -Variable result
        $json = $null
        $Rescaffolding = $false
        $MigrationFailed = $false
        foreach ($line in $result) {
            $level = $null
            $text = $null        
            $parts = $line.Split(':', 2)
            if ($parts.Length -eq 2)
            {
                $level = $parts[0]
                # gets rid of spaces        
                $text = $parts[1].Trim()
            }
            if ($level -eq 'data')
            {
                $json += $text
            }
            if ($level -eq 'info' -and $text -like '*Re-scaffolding*')
            {
                write-host "Rescaffolding text: $text"
                $Rescaffolding = $true
            }
            if ($level -eq 'error')
            {
                $MigrationFailed = $true
            }
        }   
        if ($MigrationFailed)     
        {
            Write-Error "Migration failed. See messages above for more details."
            EXIT 1
        }
        
        if ($Rescaffolding) {
            Write-Host "Rescaffolding migration."
        }
        else {
            $data = $json | ConvertFrom-Json        

            # get migration name
            $migrationPath = $data.migration
            $migrationName = (Get-ChildItem $migrationPath).BaseName
            
            #Add migration to project file#
            Write-Host "Adding migration to project."

            $proj = [xml](Get-Content $ProjectPath)

            
            $xmlns = "http://schemas.microsoft.com/developer/msbuild/2003"        
            [System.Xml.XmlNamespaceManager] $nsmgr = $proj.NameTable
            $nsmgr.AddNamespace("a", "http://schemas.microsoft.com/developer/msbuild/2003")

            # Add migration to ItemGroup/Compile
            # <Compile Include="Migrations\MigrationName.cs" />
            # <Compile Include="Migrations\MigrationName.Designer.cs">
            #   <DependentUpon>MigrationName.cs</DependentUpon>
            # </Compile>

            # this should get the Migrations.Configuration.cs node
            $xpathCompile = "//a:Project/a:ItemGroup/a:Compile[starts-with(@Include, 'Migrations')][last()]"       
            $MigNode = $proj.SelectSingleNode($xpathCompile, $nsmgr)

            $compileNode1 = $proj.CreateElement("Compile", $xmlns)
            $compileNode1.SetAttribute("Include", "Migrations\$migrationName.cs")
            
            $MigNode.ParentNode.InsertBefore($compileNode1, $MigNode)

            $compileNode2 = $proj.CreateElement("Compile", $xmlns);
            $compileNode2.SetAttribute("Include", "Migrations\$migrationName.Designer.cs")

            $dependentUponNode = $proj.CreateElement("DependentUpon", $xmlns);
            $dependentUponNode.InnerXml = "$migrationName.cs"
            $compileNode2.AppendChild($dependentUponNode)        

            $MigNode.ParentNode.InsertBefore($compileNode2, $MigNode);

            # Now add migration to ItemGroup/EmbeddedResource
            # <EmbeddedResource Include="Migrations\$migrationName.resx">
            #  <DependentUpon>$migrationName.cs</CependentUpon>
            # </EmbeddedResource>

            # This will get the last Migration entry
            $xpathEmbed = "//a:Project/a:ItemGroup/a:EmbeddedResource[starts-with(@Include, 'Migrations')][last()]"
            $MigNode2 = $proj.SelectSingleNode($xpathEmbed, $nsmgr)

            $embedNode = $proj.CreateElement("EmbeddedResource", $xmlns);
            $embedNode.SetAttribute("Include", "Migrations\$migrationName.resx")

            $dependentUponNode2 = $proj.CreateElement("DependentUpon", $xmlns);
            $dependentUponNode2.InnerXml = "$migrationName.cs"
            $embedNode.AppendChild($dependentUponNode2)
            $MigNode2.ParentNode.InsertAfter($embedNode, $MigNode2);

            # save the project file. 
            $proj.Save($ProjectPath)
        }   
    }
}
catch
{
    Write-Error "We couldn't create the migration"
    Write-Host $_
    EXIT 1
}

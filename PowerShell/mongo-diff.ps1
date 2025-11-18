param(
    [Parameter(Mandatory=$true)]
    [string]$SourceConnectionString,
    
    [Parameter(Mandatory=$true)]
    [string]$SourceDatabase,
    
    [Parameter(Mandatory=$true)]
    [string]$TargetConnectionString,
    
    [Parameter(Mandatory=$true)]
    [string]$TargetDatabase,
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = ".\mongodb_sync_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARNING','ERROR')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    Write-Host $logMessage -ForegroundColor $(
        switch($Level) {
            'INFO' { 'White' }
            'WARNING' { 'Yellow' }
            'ERROR' { 'Red' }
        }
    )
    
    Add-Content -Path $LogPath -Value $logMessage
}

function Get-MongoCollections {
    param(
        [string]$ConnectionString,
        [string]$Database
    )
    
    Write-Log "Retrieving collections from database: $Database"
    
    $command = @"
mongosh "$ConnectionString" --quiet --eval "db.getSiblingDB('$Database').getCollectionNames()" --json
"@
    
    try {
        $result = Invoke-Expression $command | ConvertFrom-Json
        Write-Log "Found $($result.Count) collections in $Database"
        return $result
    }
    catch {
        Write-Log "Failed to retrieve collections from $Database : $_" -Level ERROR
        throw
    }
}

function Get-CollectionHash {
    param(
        [string]$ConnectionString,
        [string]$Database,
        [string]$Collection
    )
    
    $command = @"
mongosh "$ConnectionString" --quiet --eval "db.getSiblingDB('$Database').runCommand({dbHash:1, collections:['$Collection']})" --json
"@
    
    try {
        $result = Invoke-Expression $command | ConvertFrom-Json
        return $result.collections.$Collection
    }
    catch {
        Write-Log "Failed to get hash for collection $Collection : $_" -Level WARNING
        return $null
    }
}

function Copy-MongoCollection {
    param(
        [string]$SourceConnectionString,
        [string]$SourceDatabase,
        [string]$TargetConnectionString,
        [string]$TargetDatabase,
        [string]$Collection,
        [bool]$Overwrite = $false
    )
    
    $action = if ($Overwrite) { "Overwriting" } else { "Copying" }
    Write-Log "$action collection: $Collection"
    
    # Drop target collection if overwriting
    if ($Overwrite) {
        $dropCommand = @"
mongosh "$TargetConnectionString" --quiet --eval "db.getSiblingDB('$TargetDatabase').$Collection.drop()"
"@
        try {
            Invoke-Expression $dropCommand | Out-Null
            Write-Log "Dropped existing collection: $Collection"
        }
        catch {
            Write-Log "Failed to drop collection $Collection : $_" -Level WARNING
        }
    }
    
    # Export from source
    $dumpPath = Join-Path $env:TEMP "mongodb_dump_$Collection"
    $sourceUri = $SourceConnectionString
    
    Write-Log "Exporting $Collection from source database..."
    $exportCommand = "mongodump --uri=`"$sourceUri`" --db=`"$SourceDatabase`" --collection=`"$Collection`" --out=`"$dumpPath`""
    
    try {
        $exportResult = Invoke-Expression $exportCommand 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "mongodump failed with exit code $LASTEXITCODE"
        }
        Write-Log "Export completed for $Collection"
    }
    catch {
        Write-Log "Failed to export collection $Collection : $_" -Level ERROR
        return $false
    }
    
    # Import to target
    $targetUri = $TargetConnectionString
    
    Write-Log "Importing $Collection to target database..."
    $importCommand = "mongorestore --uri=`"$targetUri`" --db=`"$TargetDatabase`" --collection=`"$Collection`" `"$dumpPath\$SourceDatabase\$Collection.bson`""
    
    try {
        $importResult = Invoke-Expression $importCommand 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "mongorestore failed with exit code $LASTEXITCODE"
        }
        Write-Log "Import completed for $Collection"
        
        # Clean up dump
        Remove-Item -Path $dumpPath -Recurse -Force -ErrorAction SilentlyContinue
        
        return $true
    }
    catch {
        Write-Log "Failed to import collection $Collection : $_" -Level ERROR
        Remove-Item -Path $dumpPath -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
}

# Main script execution
try {
    Write-Log "========================================="
    Write-Log "MongoDB Collection Sync Started"
    Write-Log "========================================="
    Write-Log "Source: $SourceConnectionString / $SourceDatabase"
    Write-Log "Target: $TargetConnectionString / $TargetDatabase"
    Write-Log ""
    
    # Get collections from both databases
    $sourceCollections = Get-MongoCollections -ConnectionString $SourceConnectionString -Database $SourceDatabase
    $targetCollections = Get-MongoCollections -ConnectionString $TargetConnectionString -Database $TargetDatabase
    
    Write-Log ""
    Write-Log "Starting collection comparison and sync..."
    Write-Log ""
    
    $stats = @{
        Total = $sourceCollections.Count
        Copied = 0
        Overwritten = 0
        Skipped = 0
        Failed = 0
    }
    
    foreach ($collection in $sourceCollections) {
        Write-Log "Processing collection: $collection"
        
        if ($targetCollections -notcontains $collection) {
            # Collection missing in target
            Write-Log "Collection '$collection' not found in target database - copying" -Level WARNING
            
            $success = Copy-MongoCollection -SourceConnectionString $SourceConnectionString `
                                           -SourceDatabase $SourceDatabase `
                                           -TargetConnectionString $TargetConnectionString `
                                           -TargetDatabase $TargetDatabase `
                                           -Collection $collection `
                                           -Overwrite $false
            
            if ($success) {
                $stats.Copied++
            } else {
                $stats.Failed++
            }
        }
        else {
            # Collection exists in both - compare hashes
            Write-Log "Collection '$collection' exists in both databases - comparing hashes..."
            
            $sourceHash = Get-CollectionHash -ConnectionString $SourceConnectionString -Database $SourceDatabase -Collection $collection
            $targetHash = Get-CollectionHash -ConnectionString $TargetConnectionString -Database $TargetDatabase -Collection $collection
            
            if ($null -eq $sourceHash -or $null -eq $targetHash) {
                Write-Log "Unable to retrieve hash for collection '$collection' - skipping" -Level WARNING
                $stats.Skipped++
                continue
            }
            
            Write-Log "Source hash: $sourceHash"
            Write-Log "Target hash: $targetHash"
            
            if ($sourceHash -ne $targetHash) {
                Write-Log "Hashes differ for collection '$collection' - overwriting target" -Level WARNING
                
                $success = Copy-MongoCollection -SourceConnectionString $SourceConnectionString `
                                               -SourceDatabase $SourceDatabase `
                                               -TargetConnectionString $TargetConnectionString `
                                               -TargetDatabase $TargetDatabase `
                                               -Collection $collection `
                                               -Overwrite $true
                
                if ($success) {
                    $stats.Overwritten++
                } else {
                    $stats.Failed++
                }
            }
            else {
                Write-Log "Collection '$collection' is identical - skipping"
                $stats.Skipped++
            }
        }
        
        Write-Log ""
    }
    
    Write-Log "========================================="
    Write-Log "MongoDB Collection Sync Completed"
    Write-Log "========================================="
    Write-Log "Total collections processed: $($stats.Total)"
    Write-Log "Collections copied: $($stats.Copied)"
    Write-Log "Collections overwritten: $($stats.Overwritten)"
    Write-Log "Collections skipped (identical): $($stats.Skipped)"
    Write-Log "Collections failed: $($stats.Failed)"
    Write-Log "========================================="
    
    if ($stats.Failed -gt 0) {
        exit 1
    }
}
catch {
    Write-Log "Script execution failed: $_" -Level ERROR
    Write-Log $_.ScriptStackTrace -Level ERROR
    exit 1
}
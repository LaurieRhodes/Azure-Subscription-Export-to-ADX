# Get-StorageTableValue

## Purpose

Retrieves timestamp values from Azure Storage Tables with automatic initialization and retry logic. This function specializes in timestamp management for export state tracking with built-in default value handling.

## Key Concepts

### Timestamp State Management
Designed specifically for managing export timestamps and state information with automatic initialization when no previous state exists.

### Retry Logic Integration
Includes built-in retry mechanism for transient storage failures, ensuring reliable state retrieval even under network issues.

### Default Value Handling
Provides intelligent default value management when no previous state exists, eliminating manual initialization requirements.

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `StorageTable` | Object | Yes | - | Storage table object for operations |
| `TableName` | String | Yes | - | Name of the table to query |
| `PartitionKey` | String | No | "part1" | Partition key for the row |
| `RowKey` | String | No | "1" | Row key for the specific row |
| `DefaultStartTime` | String | No | Current UTC time | Default timestamp if none exists |

## Return Value

Returns the timestamp string value or the default value if no existing timestamp is found.

## Usage Examples

### Export State Retrieval
```powershell
# Get last successful export start time
$lastStartTime = Get-StorageTableValue -StorageTable $storageTable -TableName "ExportTimestamps"

Write-Host "Starting export from: $lastStartTime"

# Convert to DateTime for processing
$startDateTime = [DateTime]::Parse($lastStartTime)
$incrementalExport = $startDateTime -gt (Get-Date).AddDays(-1)
```

### Custom Default Values
```powershell
# Use specific default for initial export
$customDefault = "2025-01-01T00:00:00.000Z"
$exportStartTime = Get-StorageTableValue -StorageTable $storageTable -TableName "ExportTimestamps" -DefaultStartTime $customDefault

Write-Host "Export will start from: $exportStartTime"
```

### Retry Logic Example
```powershell
# The function includes automatic retry for transient failures
try {
    $lastRun = Get-StorageTableValue -StorageTable $storageTable -TableName "ExportState"
    Write-Host "Retrieved timestamp successfully: $lastRun"
} catch {
    Write-Error "Failed to retrieve timestamp after retries: $($_.Exception.Message)"
    # Function automatically retried 3 times before failing
    throw
}
```

## Retry Configuration

### Built-in Retry Strategy
```powershell
$maxRetries = 3
$retryDelaySeconds = 2  # Doubles on each retry (2, 4, 8 seconds)

do {
    try {
        $row = Get-AzTableRow -Table $cloudTable -PartitionKey $PartitionKey -RowKey $RowKey -ErrorAction Stop
        break  # Success
    } catch {
        $retryCount++
        if ($retryCount -eq $maxRetries) {
            throw  # Final failure
        }
        Start-Sleep -Seconds $retryDelaySeconds
        $retryDelaySeconds *= 2
    }
} while ($retryCount -lt $maxRetries)
```

## Initialization Behavior

### Automatic Default Creation
```powershell
# When no existing value found
if ($null -eq $row -or $null -eq $row.starttime) {
    $properties = @{
        "starttime" = $DefaultStartTime
    }
    
    Add-AzTableRow -Table $cloudTable -PartitionKey $PartitionKey -RowKey $RowKey -Property $properties -UpdateExisting
    return $DefaultStartTime
}
```

### Storage Validation
The function validates storage context availability in the parent scope:
```powershell
if (-not (Get-Variable -Name 'StorageTable' -ErrorAction SilentlyContinue)) {
    throw "Storage context not found. Ensure 'StorageTable' variable is defined in parent scope."
}
```

## Dependencies

### Required Variables
- **StorageTable**: Must be available in parent scope
- **Storage Context**: Valid Azure Storage context

### Required Modules
- **AzTable**: Table storage operations
- **Az.Storage**: Storage account management

## Integration Patterns

### With Export Functions
```powershell
# Typical usage in export orchestration
$lastExportTime = Get-StorageTableValue -StorageTable $storageContext -TableName "AADExportState"

# Use for incremental export logic
$exportSinceTime = [DateTime]::Parse($lastExportTime)
$incrementalUsers = Get-AADUsersModifiedSince -Since $exportSinceTime
```

### With State Management
```powershell
# Retrieve and update export state
$currentState = Get-StorageTableValue -StorageTable $storageTable -TableName "ExportProgress"

# Process export...

# Update state after completion
Push-StorageTableValue -StorageAccountName $storageAccount -TableName "ExportProgress" -DateTimeValue (Get-Date)
```

## Error Handling

### Validation Errors
- **Missing storage context**: Validates parent scope variable availability
- **Invalid table name**: Validates table name format and length
- **Storage account access**: Validates permissions and connectivity

### Recovery Strategies
- **Transient failures**: Automatic retry with exponential backoff
- **Missing table**: Automatic table creation with default initialization
- **Missing row**: Returns default value rather than error
- **Corrupted data**: Returns default value and logs warning

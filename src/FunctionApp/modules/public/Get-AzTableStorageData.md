# Get-AzTableStorageData

## Purpose

Retrieves specific property values from Azure Table Storage with automatic table creation and initialization. This function provides read access to table storage with built-in error handling and table management.

## Key Concepts

### Automatic Table Management
Creates tables automatically if they don't exist, eliminating manual setup requirements and ensuring consistent table structure.

### Property-Specific Retrieval
Targets specific properties within table rows rather than returning entire row objects, providing focused data access.

### Storage Context Integration
Uses Azure Storage context for authentication, supporting both connection strings and managed identity scenarios.

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `TableName` | String | Yes | Name of the Azure Storage Table to query |
| `StorageContext` | IStorageContext | Yes | Azure Storage context for authentication |
| `PartitionKey` | String | Yes | Table partition key for the target row |
| `RowKey` | String | Yes | Table row key for the specific row |
| `PropertyName` | String | Yes | Name of the property to retrieve from the row |

## Return Value

Returns the property value as a string, or `$null` if the row or property is not found.

## Usage Examples

### Standard Property Retrieval
```powershell
# Get last export timestamp
$lastExport = Get-AzTableStorageData -TableName "ExportState" -StorageContext $storageContext -PartitionKey "exports" -RowKey "lastrun" -PropertyName "timestamp"

if ($null -eq $lastExport) {
    Write-Host "No previous export found - first run"
    $startTime = (Get-Date).AddDays(-1)
} else {
    Write-Host "Last export: $lastExport"
    $startTime = [DateTime]::Parse($lastExport)
}
```

### Error Handling
```powershell
try {
    $configValue = Get-AzTableStorageData -TableName "Configuration" -StorageContext $storageContext -PartitionKey "settings" -RowKey "main" -PropertyName "exportEnabled"
    
    if ($null -eq $configValue) {
        Write-Warning "Export configuration not found - using defaults"
        $exportEnabled = $true
    } else {
        $exportEnabled = [bool]::Parse($configValue)
    }
} catch {
    Write-Error "Failed to retrieve configuration: $($_.Exception.Message)"
    throw
}
```

## Table Auto-Creation Behavior

### Table Creation Logic
```powershell
if ($null -eq $StorageTable.Name) {
    Write-Information "Creating new storage table: $TableName"
    $result = New-AzStorageTable -Name $TableName -Context $StorageContext
    
    # Initialize with default property
    $Table = (Get-AzStorageTable -Name $TableName -Context $StorageContext.Context).cloudTable
    $result = Add-AzTableRow -table $Table -PartitionKey "part1" -RowKey "1" -property @{"$($PropertyName)"=""} -UpdateExisting
}
```

### Initialization Pattern
- Creates table if it doesn't exist
- Adds initial row with empty property value
- Uses standard partition/row key structure for consistency

## Dependencies

### Required Modules
- **AzTable**: Azure Table Storage operations
- **Az.Storage**: Storage account context management

### Authentication Requirements
- **Storage Account Access**: Read permissions on target storage account
- **Table Storage Permissions**: Table read/write access via storage context

## Error Scenarios

### Common Errors
- **Storage account not found**: Verify storage context configuration
- **Permission denied**: Check storage account access permissions
- **Table creation failure**: Verify storage account write permissions
- **Property not found**: Returns `$null` (not an error condition)

### Error Handling Pattern
```powershell
try {
    $cloudTable = (Get-AzStorageTable -Name $TableName -Context $StorageContext).CloudTable
    $row = Get-AzTableRow -Table $cloudTable -PartitionKey $PartitionKey -RowKey $RowKey
    
    if ($null -eq $row) {
        Write-Information "No row found with PartitionKey: $PartitionKey, RowKey: $RowKey"
        return $null
    }
    
    return $row.$PropertyName.ToString()
} catch {
    Write-Error "Error in Get-AzTableStorageData: $_"
    throw
}
```

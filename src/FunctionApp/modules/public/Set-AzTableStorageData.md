# Set-AzTableStorageData

## Purpose

Creates or updates rows in Azure Table Storage with comprehensive property management and automatic table creation. This function provides write access to table storage with built-in table management and row upsert capabilities.

## Key Concepts

### Upsert Operations
Automatically handles both row creation (if row doesn't exist) and row updates (if row exists) in a single operation.

### Automatic Table Creation
Creates tables on-demand if they don't exist, with optional control via the `CreateIfNotExists` parameter.

### Comprehensive Property Management
Accepts hashtable of properties for flexible row data management, supporting multiple properties in single operations.

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `TableName` | String | Yes | - | Name of the Azure Storage Table |
| `StorageContext` | IStorageContext | Yes | - | Azure Storage context for authentication |
| `PartitionKey` | String | Yes | - | Table partition key for the row |
| `RowKey` | String | Yes | - | Table row key for the specific row |
| `Properties` | Hashtable | Yes | - | Properties to set or update in the row |
| `CreateIfNotExists` | Switch | No | $true | Create table if it doesn't exist |

## Return Value

Returns the created or updated Azure Table row object with all properties.

## Usage Examples

### Standard Row Update
```powershell
# Update export state with multiple properties
$properties = @{
    lastExportTime = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    recordCount = 1250
    status = "completed"
    exportId = [guid]::NewGuid().ToString()
}

$row = Set-AzTableStorageData -TableName "ExportState" -StorageContext $storageContext -PartitionKey "exports" -RowKey "latest" -Properties $properties

Write-Host "Updated export state:"
Write-Host "  - Last Export: $($row.lastExportTime)"
Write-Host "  - Record Count: $($row.recordCount)"
Write-Host "  - Status: $($row.status)"
```

### Configuration Management
```powershell
# Store configuration settings
$configProperties = @{
    exportEnabled = "true"
    batchSize = "999"
    retryCount = "3"
    extendedProperties = "false"
}

Set-AzTableStorageData -TableName "Configuration" -StorageContext $storageContext -PartitionKey "settings" -RowKey "main" -Properties $configProperties -CreateIfNotExists
```

### Error Handling with Verification
```powershell
try {
    $updateProperties = @{
        timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        operationId = $correlationId
    }
    
    $updatedRow = Set-AzTableStorageData -TableName "AuditLog" -StorageContext $storageContext -PartitionKey "operations" -RowKey $operationId -Properties $updateProperties
    
    # Verify update succeeded
    if ($null -eq $updatedRow) {
        throw "Row update verification failed"
    }
    
    Write-Host "✅ Audit log updated successfully"
} catch {
    Write-Error "Failed to update audit log: $($_.Exception.Message)"
    throw
}
```

## Operation Flow

### Table Management
```powershell
# 1. Check if table exists
$storageTable = Get-AzStorageTable -Name $TableName -Context $StorageContext -ErrorAction Ignore

# 2. Create table if needed
if ($null -eq $storageTable.Name) {
    if ($CreateIfNotExists) {
        $result = New-AzStorageTable -Name $TableName -Context $StorageContext
        $cloudTable = (Get-AzStorageTable -Name $TableName -Context $StorageContext.Context).CloudTable
    } else {
        throw "Table $TableName does not exist and CreateIfNotExists is false"
    }
}
```

### Row Upsert Logic
```powershell
# 3. Check for existing row
$existingRow = Get-AzTableRow -Table $cloudTable -PartitionKey $PartitionKey -RowKey $RowKey -ErrorAction Ignore

# 4. Add or update row
if ($null -eq $existingRow) {
    # Add new row
    $result = Add-AzTableRow -Table $cloudTable -PartitionKey $PartitionKey -RowKey $RowKey -Property $Properties
} else {
    # Update existing row
    $result = Add-AzTableRow -Table $cloudTable -PartitionKey $PartitionKey -RowKey $RowKey -Property $Properties -UpdateExisting
}
```

### Verification Step
```powershell
# 5. Verify operation
$verifiedRow = Get-AzTableRow -Table $cloudTable -PartitionKey $PartitionKey -RowKey $RowKey
if ($null -eq $verifiedRow) {
    throw "Failed to verify row after write operation"
}
```

## Properties Management

### Hashtable Structure
```powershell
# Example properties hashtable
$properties = @{
    "stringProperty" = "text value"
    "numericProperty" = 12345
    "dateProperty" = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    "booleanProperty" = $true.ToString()
    "guidProperty" = [guid]::NewGuid().ToString()
}
```

### Data Type Handling
- **Strings**: Stored directly
- **Numbers**: Converted to string representation
- **Dates**: Use ISO 8601 format for consistency
- **Booleans**: Convert to string ("true"/"false")
- **GUIDs**: Convert to string representation

## Dependencies

### Required Modules
- **AzTable**: Azure Table Storage operations (`Add-AzTableRow`, `Get-AzTableRow`)
- **Az.Storage**: Storage context and table management (`New-AzStorageTable`, `Get-AzStorageTable`)

### Authentication Requirements
- **Storage Account Access**: Read/write permissions on target storage account
- **Table Storage Permissions**: Full table access via storage context

## Error Scenarios

### Common Errors and Solutions
- **Storage context invalid**: Verify storage account connection
- **Permission denied**: Check storage account IAM permissions
- **Table creation failure**: Verify storage account write permissions
- **Row verification failure**: Check table consistency and network connectivity

### Error Messages
```powershell
# Configuration error
"Table TableName does not exist and CreateIfNotExists is false"

# Permission error  
"Error in Set-AzTableStorageData: Forbidden"

# Verification error
"Failed to verify row after write operation"
```

## Integration Patterns

### With Export State Management
```powershell
# Track export completion
$exportState = @{
    lastCompletedExport = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    lastExportId = $correlationId
    userCount = $statistics.Users
    groupCount = $statistics.Groups
    success = $true.ToString()
}

Set-AzTableStorageData -TableName "ExportHistory" -StorageContext $storageContext -PartitionKey "daily" -RowKey (Get-Date -Format "yyyy-MM-dd") -Properties $exportState
```

### With Configuration Management
```powershell
# Store function configuration
$config = @{
    enabledExtendedProperties = $false.ToString()
    maxRetryCount = "3"
    batchSize = "999"
    lastConfigUpdate = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
}

Set-AzTableStorageData -TableName "FunctionConfig" -StorageContext $storageContext -PartitionKey "settings" -RowKey "current" -Properties $config
```

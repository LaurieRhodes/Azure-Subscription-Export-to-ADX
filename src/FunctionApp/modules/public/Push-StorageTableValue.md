# Push-StorageTableValue

## Purpose

Updates timestamp values in Azure Storage Tables using REST API with managed identity authentication. This function provides direct REST API access to table storage for timestamp management and state tracking.

## Key Concepts

### REST API Direct Access
Uses Azure Storage REST API directly rather than PowerShell modules, providing more control over authentication and request formatting.

### Managed Identity Authentication
Acquires storage tokens using managed identity for secure, credential-less access to Azure Storage accounts.

### Timestamp-Specific Operations
Optimized for timestamp value updates with hardcoded "lastUpdated" property management.

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `ClientId` | String | Yes | - | Managed identity client ID for authentication |
| `StorageAccountName` | String | Yes | - | Name of the Azure Storage Account |
| `TableName` | String | Yes | - | Name of the table to update |
| `DateTimeValue` | DateTime | No | 1 hour ago | Timestamp value to store |

## Return Value

Returns the response value from the Azure Storage REST API operation.

## Usage Examples

### Standard Timestamp Update
```powershell
# Update last export completion time
Push-StorageTableValue -ClientId $env:CLIENTID -StorageAccountName "myexportstorageaccount" -TableName "ExportState" -DateTimeValue (Get-Date)

Write-Host "Export completion timestamp updated"
```

### Export State Tracking
```powershell
# Track export completion in orchestration function
try {
    $exportCompleted = Get-Date
    
    # Update export state
    Push-StorageTableValue -ClientId $env:CLIENTID -StorageAccountName $env:STORAGEACCOUNTNAME -TableName "AADExportState" -DateTimeValue $exportCompleted
    
    Write-Host "✅ Export state updated: $($exportCompleted.ToString('yyyy-MM-dd HH:mm:ss UTC'))"
} catch {
    Write-Warning "Failed to update export state: $($_.Exception.Message)"
    # Don't fail entire export for state update issues
}
```

### Integration with Export Pipeline
```powershell
# Called at end of successful export
if ($exportResult.Success) {
    # Update last successful export time
    Push-StorageTableValue -ClientId $env:CLIENTID -StorageAccountName $storageAccountName -TableName "ExportHistory" -DateTimeValue $exportResult.EndTime
    
    Write-Host "Export history updated with completion time"
}
```

## REST API Implementation

### Authentication Flow
```powershell
# 1. Acquire storage token
$token = Get-AzureADToken -resource "https://storage.azure.com/" -clientId $ClientId

# 2. Create REST headers
$authHeader = @{
    "Authorization" = "Bearer $($token)"
    "Content-Type" = "application/json"
    'Accept' = 'application/json;odata=nometadata'
    "x-ms-version" = "2020-08-04"
    "x-ms-date" = (Get-Date).ToUniversalTime().ToString("R")
}
```

### Entity Update Structure
```powershell
# 3. Create entity payload
$entity = @{
    lastUpdated = $DateTimeValue.ToUniversalTime().ToString("R")
}

# 4. REST API call
$uri = "https://$($StorageAccountName).table.core.windows.net/$($TableName)(PartitionKey='$($TableName)',RowKey='lastUpdated')"
$response = Invoke-RestMethod -Uri $uri -Headers $authHeader -Method PUT -Body (ConvertTo-Json $entity)
```

## Table Structure

### Fixed Entity Structure
The function uses a hardcoded entity structure:
- **PartitionKey**: Same as TableName
- **RowKey**: "lastUpdated"  
- **Property**: "lastUpdated" with DateTime value

### URI Format
```
https://{StorageAccountName}.table.core.windows.net/{TableName}(PartitionKey='{TableName}',RowKey='lastUpdated')
```

## Dependencies

### Required Functions
- **Get-AzureADToken**: For acquiring storage access tokens

### Required Environment Variables
- **CLIENTID**: Available via parameter, typically from `$env:CLIENTID`

### External Dependencies
- **Azure Storage Account**: Target storage account must exist
- **Managed Identity Permissions**: Storage account access required

## Authentication Requirements

### Managed Identity Permissions
The User-Assigned Managed Identity requires:
- **Storage Account Contributor** OR
- **Storage Table Data Contributor** (more specific)
- **Storage Account Key Operator Service Role** (if using key-based access)

### Storage Account Configuration
- **Public access**: May need to be enabled for REST API access
- **Firewall rules**: Function App IP ranges must be allowed
- **Network access**: Storage account network settings must allow Function App access

## Error Handling

### Common Errors
```powershell
try {
    Push-StorageTableValue -ClientId $clientId -StorageAccountName $storageAccount -TableName $tableName -DateTimeValue (Get-Date)
} catch {
    if ($_.Exception.Message -match "401|Unauthorized") {
        Write-Error "❌ STORAGE AUTHENTICATION ERROR"
        Write-Error "1. Check managed identity permissions on storage account"
        Write-Error "2. Verify CLIENTID environment variable"
        Write-Error "3. Ensure storage account allows managed identity access"
    }
    elseif ($_.Exception.Message -match "404|Not Found") {
        Write-Error "❌ STORAGE ACCOUNT OR TABLE NOT FOUND"
        Write-Error "1. Verify storage account name: $StorageAccountName"
        Write-Error "2. Check table name: $TableName"
        Write-Error "3. Ensure table exists or has auto-create enabled"
    }
    elseif ($_.Exception.Message -match "403|Forbidden") {
        Write-Error "❌ STORAGE PERMISSIONS ERROR"
        Write-Error "1. Managed identity lacks sufficient storage permissions"
        Write-Error "2. Check firewall rules on storage account"
    }
    
    Write-Error "Failed to update entity: $_"
    throw
}
```

## Legacy Function Notice

### Usage Context
This function appears to be designed for timestamp tracking in export state management scenarios where REST API access is preferred over PowerShell module operations.

### Modern Alternatives
Consider using `Set-AzTableStorageData` for more flexible property management and better integration with the existing module architecture.

# Storage Utility Functions

## Overview

The storage utility functions provide Azure Table Storage integration for maintaining export state and configuration data. These functions are currently used for legacy compatibility but may be superseded by Event Hub-based state management in future versions.

---

## Get-AzTableStorageData

### Purpose
Retrieves specific property values from Azure Table Storage with automatic table creation and initialization.

### Parameters
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `TableName` | String | Yes | Name of the Azure Storage Table |
| `StorageContext` | IStorageContext | Yes | Azure Storage context for authentication |
| `PartitionKey` | String | Yes | Table partition key for the row |
| `RowKey` | String | Yes | Table row key for the specific row |
| `PropertyName` | String | Yes | Name of the property to retrieve |

### Return Value
Returns the property value as a string, or `$null` if not found.

### Usage Examples
```powershell
# Retrieve last export timestamp
$lastRun = Get-AzTableStorageData -TableName "ExportState" -StorageContext $storageContext -PartitionKey "exports" -RowKey "lastrun" -PropertyName "timestamp"

# Check if property exists
if ($null -eq $lastRun) {
    Write-Host "No previous export timestamp found"
} else {
    Write-Host "Last export: $lastRun"
}
```

---

## Set-AzTableStorageData

### Purpose
Creates or updates rows in Azure Table Storage with comprehensive property management and automatic table creation.

### Parameters
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `TableName` | String | Yes | Name of the Azure Storage Table |
| `StorageContext` | IStorageContext | Yes | Azure Storage context for authentication |
| `PartitionKey` | String | Yes | Table partition key for the row |
| `RowKey` | String | Yes | Table row key for the specific row |
| `Properties` | Hashtable | Yes | Properties to set or update in the row |
| `CreateIfNotExists` | Switch | No | Create table if it doesn't exist |

### Return Value
Returns the created or updated table row object.

### Usage Examples
```powershell
# Update export state
$properties = @{
    lastExportTime = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    recordCount = 1250
    status = "completed"
}

$row = Set-AzTableStorageData -TableName "ExportState" -StorageContext $storageContext -PartitionKey "exports" -RowKey "latest" -Properties $properties -CreateIfNotExists

Write-Host "Updated export state: $($row.lastExportTime)"
```

---

## Get-StorageTableValue

### Purpose
Retrieves timestamp values from Azure Storage Tables with automatic initialization and retry logic.

### Parameters
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `StorageTable` | Object | Yes | - | Storage table object for operations |
| `TableName` | String | Yes | - | Name of the table to query |
| `PartitionKey` | String | No | "part1" | Partition key for the row |
| `RowKey` | String | No | "1" | Row key for the specific row |
| `DefaultStartTime` | String | No | Current UTC time | Default timestamp if none exists |

### Return Value
Returns the timestamp string value or the default if no value exists.

### Usage Examples
```powershell
# Get last export start time
$lastStartTime = Get-StorageTableValue -StorageTable $storageTable -TableName "ExportTimestamps"

# With custom defaults
$customStartTime = Get-StorageTableValue -StorageTable $storageTable -TableName "ExportTimestamps" -DefaultStartTime "2025-01-01T00:00:00.000Z"
```

---

## Push-StorageTableValue

### Purpose
Updates timestamp values in Azure Storage Tables using REST API with managed identity authentication.

### Parameters
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `ClientId` | String | Yes | - | Managed identity client ID for authentication |
| `StorageAccountName` | String | Yes | - | Name of the Azure Storage Account |
| `TableName` | String | Yes | - | Name of the table to update |
| `DateTimeValue` | DateTime | No | 1 hour ago | Timestamp value to store |

### Usage Examples
```powershell
# Update last export time
Push-StorageTableValue -ClientId $env:CLIENTID -StorageAccountName "mystorageaccount" -TableName "ExportState" -DateTimeValue (Get-Date)
```

---

## Get-Events (Legacy Function)

### Purpose
**Note**: This appears to be a legacy Okta integration function that may not be relevant to the current AAD export architecture.

### Status
This function contains Okta-specific logic and should be reviewed for removal or refactoring as it doesn't align with the Azure AD export purpose.

---

## Refactoring Recommendations for HelperFunctions.ps1

Based on the analysis, HelperFunctions.ps1 contains three functions that should be separated into individual files following the "one function per file" architecture:

### Required Refactoring

#### 1. Create Get-ErrorType.ps1
```powershell
# Move Get-ErrorType function from HelperFunctions.ps1 to:
# modules/public/Get-ErrorType.ps1
```

#### 2. Create Get-HttpStatusCode.ps1  
```powershell
# Move Get-HttpStatusCode function from HelperFunctions.ps1 to:
# modules/public/Get-HttpStatusCode.ps1
```

#### 3. Create Test-ShouldRetry.ps1
```powershell
# Move Test-ShouldRetry function from HelperFunctions.ps1 to:
# modules/public/Test-ShouldRetry.ps1
```

### Post-Refactoring Actions

#### Update AADExporter.psm1
```powershell
# Add new functions to export list in AADExporter.psd1:
'Get-ErrorType',
'Get-HttpStatusCode', 
'Test-ShouldRetry'

# Remove HelperFunctions.ps1 import if it becomes empty
```

#### Update Dependencies
Ensure all functions that currently reference HelperFunctions.ps1 can access the newly separated functions through the module export system.

#### Testing Requirements
- Verify all error handling functions work correctly after separation
- Test retry logic with various error scenarios
- Validate telemetry integration remains intact
- Confirm no breaking changes in calling functions

### Architecture Compliance
After refactoring, the module structure will follow the established pattern:
- **One function per file** for maintainability
- **Clear function responsibilities** for easier testing
- **Consistent naming conventions** across all files
- **Improved modularity** for selective function imports

### Migration Strategy
1. **Create individual function files** with proper headers and documentation
2. **Update module manifest** to export new functions
3. **Test function availability** in development environment
4. **Remove HelperFunctions.ps1** after successful migration
5. **Update all documentation** to reflect new file structure

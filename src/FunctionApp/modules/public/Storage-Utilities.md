# Storage Utility Functions

## Overview

The storage utility functions provide Azure Table Storage integration for maintaining export state and configuration data. These functions are currently used for legacy compatibility but may be superseded by Event Hub-based state management in future versions.

---

## Get-AzTableStorageData

### Purpose

Retrieves specific property values from Azure Table Storage with automatic table creation and initialization.

### Parameters

| Parameter        | Type            | Required | Description                              |
| ---------------- | --------------- | -------- | ---------------------------------------- |
| `TableName`      | String          | Yes      | Name of the Azure Storage Table          |
| `StorageContext` | IStorageContext | Yes      | Azure Storage context for authentication |
| `PartitionKey`   | String          | Yes      | Table partition key for the row          |
| `RowKey`         | String          | Yes      | Table row key for the specific row       |
| `PropertyName`   | String          | Yes      | Name of the property to retrieve         |

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

| Parameter           | Type            | Required | Description                              |
| ------------------- | --------------- | -------- | ---------------------------------------- |
| `TableName`         | String          | Yes      | Name of the Azure Storage Table          |
| `StorageContext`    | IStorageContext | Yes      | Azure Storage context for authentication |
| `PartitionKey`      | String          | Yes      | Table partition key for the row          |
| `RowKey`            | String          | Yes      | Table row key for the specific row       |
| `Properties`        | Hashtable       | Yes      | Properties to set or update in the row   |
| `CreateIfNotExists` | Switch          | No       | Create table if it doesn't exist         |

### Return Value

Returns the created or updated table row object.

---

## Refactoring Recommendations for HelperFunctions.ps1

Based on the analysis, HelperFunctions.ps1 contains three functions that should be separated into individual files following the "one function per file" architecture:

### Required Refactoring

#### 1. Create Get-ErrorType.ps1

Move Get-ErrorType function from HelperFunctions.ps1 to individual file

#### 2. Create Get-HttpStatusCode.ps1

Move Get-HttpStatusCode function from HelperFunctions.ps1 to individual file

#### 3. Create Test-ShouldRetry.ps1

Move Test-ShouldRetry function from HelperFunctions.ps1 to individual file

### Post-Refactoring Actions

1. **Update AADExporter.psd1** to export the new functions
2. **Remove HelperFunctions.ps1** after successful migration  
3. **Test function availability** in development environment
4. **Update documentation** to reflect new file structure

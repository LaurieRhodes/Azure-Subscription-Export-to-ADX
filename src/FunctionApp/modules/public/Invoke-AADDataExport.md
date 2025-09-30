# Invoke-AADDataExport

## Purpose

Main orchestration function that coordinates the complete Azure AD data export process. This function serves as the central coordinator for exporting Users, Groups, and Group Memberships from Azure AD to Azure Data Explorer via Event Hub.

## Key Concepts

### Modular Architecture

The function orchestrates three distinct export stages in sequence:

1. **Authentication**: Acquire Microsoft Graph token via Managed Identity
2. **Users Export**: Retrieve all users with core and optional extended properties
3. **Groups Export**: Retrieve all groups and collect Group IDs for membership processing
4. **Memberships Export**: Process group memberships for collected Group IDs

### Correlation Context

Each export operation is tracked with a unique correlation ID for end-to-end traceability across all stages and external dependencies.

### Performance Monitoring

Comprehensive timing and metrics collection across all stages with structured telemetry integration.

## Parameters

| Parameter                       | Type   | Required | Default   | Description                                                                            |
| ------------------------------- | ------ | -------- | --------- | -------------------------------------------------------------------------------------- |
| `TriggerContext`                | String | No       | "Unknown" | Context information from calling trigger (e.g., "HttpTrigger", "TimerTrigger")         |
| `IncludeExtendedUserProperties` | Switch | No       | $false    | Enable extended user properties that require individual API calls (performance impact) |

## Return Value

Returns a comprehensive result object:

```powershell
@{
    Success = $true/$false              # Overall operation success
    ExportId = "guid-string"            # Unique correlation ID
    Statistics = @{
        Users = 1250                    # Number of users exported
        UsersExtended = 800             # Number of users with extended properties
        Groups = 150                    # Number of groups exported
        Memberships = 3500              # Number of group memberships exported
        TotalRecords = 4900             # Sum of all exported records
        EventHubBatches = 12            # Number of Event Hub batches sent
        Duration = 3.45                 # Total execution time in minutes
        GroupSuccessRate = 97.5         # Percentage of groups successfully processed
        FailedGroups = 3                # Number of groups that failed processing
        Performance = @{
            RecordsPerMinute = 1421     # Overall throughput
            EventHubBatchesPerMinute = 3.5
        }
        StageTimings = @{               # Individual stage performance (seconds)
            Authentication = 2.1
            UsersExport = 45.3
            GroupsExport = 12.7
            MembershipsExport = 89.2
        }
    }
    StartTime = [DateTime]              # Export start timestamp
    EndTime = [DateTime]                # Export completion timestamp
    ModularArchitecture = $true         # Architecture indicator
    GraphApiVersion = "v1.0"            # Graph API version used
}
```

## Usage Examples

### Basic Export (Recommended)

```powershell
# Standard export with core properties only (best performance)
$result = Invoke-AADDataExport -TriggerContext "HttpTrigger"

if ($result.Success) {
    Write-Host "✅ Export completed successfully"
    Write-Host "   Records: $($result.Statistics.TotalRecords)"
    Write-Host "   Duration: $($result.Statistics.Duration) minutes"
    Write-Host "   Export ID: $($result.ExportId)"
} else {
    Write-Error "❌ Export failed: $($result.Error.ErrorMessage)"
}
```

### Extended Properties Export

```powershell
# Export with extended user properties (slower due to individual API calls)
$result = Invoke-AADDataExport -TriggerContext "TimerTrigger" -IncludeExtendedUserProperties

Write-Host "Core users: $($result.Statistics.Users)"
Write-Host "Extended users: $($result.Statistics.UsersExtended)"
```

### Timer Trigger Usage

```powershell
# Called from TimerTriggerFunction/run.ps1
$exportResult = Invoke-AADDataExport -TriggerContext "TimerTrigger"

if (-not $exportResult.Success) {
    # Re-throw to ensure function shows as failed in Azure monitoring
    throw "AAD Data Export failed: $($exportResult.Error.ErrorMessage)"
}
```

## Error Handling

### Single-Level Error Pattern

The function implements v3.0 single-level error handling without nested catch blocks:

```powershell
try {
    # All export operations
    $result = Export-Operation
} catch {
    # Single-level error handling
    $errorDetails = @{
        ErrorMessage = $_.Exception.Message
        ErrorType = Get-ErrorType -Exception $_
        Timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    }
    Write-CustomTelemetry -EventName "OperationFailed" -Properties $errorDetails
    return @{ Success = $false; Error = $errorDetails }
}
```

### Error Recovery

- **Authentication failures**: Permanent failure (no retry)
- **Graph API rate limits**: Automatic retry with exponential backoff
- **Event Hub issues**: Detailed diagnostics with configuration guidance
- **Partial failures**: Continues processing and reports partial statistics

## Performance Considerations

### Execution Time Expectations

- **Small tenant** (<1000 users, <100 groups): 1-2 minutes
- **Medium tenant** (1000-5000 users, 100-500 groups): 3-5 minutes
- **Large tenant** (5000+ users, 500+ groups): 5-10 minutes

### Performance Impact of Extended Properties

- **Core properties only**: ~1200 users/minute
- **With extended properties**: ~400 users/minute (due to individual API calls)

### Memory Usage

- Typical memory usage: 200-400MB
- Monitor for memory pressure in large tenants
- Automatic batch processing prevents memory accumulation

## Dependencies

### Required Functions

- `Get-AzureADToken`: Authentication token acquisition
- `Export-AADUsers`: Users data export
- `Export-AADGroups`: Groups data export  
- `Export-AADGroupMemberships`: Group memberships export
- `Write-CustomTelemetry`: Telemetry logging
- `New-CorrelationContext`: Correlation tracking

### Required Environment Variables

- `CLIENTID`: User-Assigned Managed Identity Client ID
- `EVENTHUBNAMESPACE`: Event Hub Namespace name
- `EVENTHUBNAME`: Target Event Hub name

### External Dependencies

- Microsoft Graph API v1.0 (https://graph.microsoft.com)
- Azure Event Hub (for data transmission)
- Application Insights (for telemetry)

## Telemetry Events

The function generates these telemetry events for monitoring:

| Event                | Purpose                       | Key Properties                               |
| -------------------- | ----------------------------- | -------------------------------------------- |
| `AADExportStarted`   | Export initiation tracking    | ExportId, TriggerContext, ExtendedProperties |
| `AADExportCompleted` | Successful completion metrics | UserCount, GroupCount, Duration, Performance |
| `AADExportFailed`    | Failure analysis              | ErrorMessage, ErrorType, PartialStatistics   |

# 

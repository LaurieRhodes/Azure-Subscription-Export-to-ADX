# Export-AADGroups

## Purpose

Exports Azure AD groups with comprehensive property retrieval to Event Hub for ADX ingestion. This function retrieves all organizational groups and collects Group IDs for subsequent membership processing using Microsoft Graph API v1.0 production endpoints.

## Key Concepts

### Group Data Collection

Retrieves comprehensive group information including security groups, Microsoft 365 groups, distribution lists, and mail-enabled security groups with full property sets.

### Group ID Harvesting

Collects all group IDs during export for efficient downstream membership processing, enabling the three-stage export architecture (Users → Groups → Memberships).

### Production API Usage

Uses stable `https://graph.microsoft.com/v1.0/groups` endpoint with maximum pagination (999 groups per call) for optimal performance and reliability.

## Parameters

| Parameter            | Type      | Required | Default | Description                                                            |
| -------------------- | --------- | -------- | ------- | ---------------------------------------------------------------------- |
| `AuthHeader`         | Hashtable | Yes      | -       | Authentication headers containing Bearer token for Microsoft Graph API |
| `CorrelationContext` | Hashtable | Yes      | -       | Correlation context with OperationId and tracking information          |

## Return Value

```powershell
@{
    Success = $true/$false              # Operation success indicator
    GroupCount = 150                    # Total groups processed and exported
    AllGroupIDs = @("guid1", "guid2")   # Array of all group IDs for membership processing
    BatchCount = 3                      # Number of Event Hub batches sent
    DurationMs = 12700                  # Total execution time in milliseconds
}
```

## Properties Retrieved (25+ Properties)

### Core Group Identity

```
id, displayName, description, mailNickname, mail
```

### Group Classification and Types

```
groupTypes, securityEnabled, mailEnabled, classification, visibility
```

### Membership and Rules

```
membershipRule, membershipRuleProcessingState, isAssignableToRole
```

### Lifecycle Management

```
createdDateTime, deletedDateTime, expirationDateTime, renewedDateTime
```

### Integration Properties

```
creationOptions, resourceBehaviorOptions, resourceProvisioningOptions, 
preferredDataLocation, preferredLanguage, theme, writebackConfiguration
```

### On-Premises Integration

```
onPremisesDomainName, onPremisesLastSyncDateTime, onPremisesNetBiosName,
onPremisesSamAccountName, onPremisesSecurityIdentifier, onPremisesSyncEnabled
```

### Communication and Collaboration

```
proxyAddresses, securityIdentifier
```

## Usage Examples

### Standard Groups Export

```powershell
# Typical usage from main orchestration function
$authHeader = @{ 
    'Authorization' = "Bearer $token"
    'ConsistencyLevel' = 'eventual'
}
$correlationContext = @{ 
    OperationId = [guid]::NewGuid().ToString()
    StartTime = Get-Date 
}

$result = Export-AADGroups -AuthHeader $authHeader -CorrelationContext $correlationContext

if ($result.Success) {
    Write-Host "✅ Groups export completed"
    Write-Host "   Groups processed: $($result.GroupCount)"
    Write-Host "   Group IDs collected: $($result.AllGroupIDs.Count)"
    Write-Host "   Duration: $([Math]::Round($result.DurationMs/1000, 2)) seconds"

    # Use collected Group IDs for membership processing
    $membershipsResult = Export-AADGroupMemberships -AuthHeader $authHeader -GroupIDs $result.AllGroupIDs -CorrelationContext $correlationContext
}
```

### Performance Monitoring

```powershell
# Calculate and display performance metrics
$groupsPerMinute = [Math]::Round($result.GroupCount / ($result.DurationMs/60000), 0)
Write-Host "Throughput: $groupsPerMinute groups/minute"

# Check for performance degradation
if ($groupsPerMinute -lt 200) {
    Write-Warning "⚠️ Group export performance below baseline (target: >300 groups/minute)"
}
```

### Error Handling Example

```powershell
try {
    $groupsResult = Export-AADGroups -AuthHeader $authHeader -CorrelationContext $correlationContext

    if (-not $groupsResult.Success) {
        throw "Groups export failed: $($groupsResult.Error.ErrorMessage)"
    }

    # Validate Group ID collection
    if ($groupsResult.AllGroupIDs.Count -ne $groupsResult.GroupCount) {
        Write-Warning "Group ID collection mismatch: $($groupsResult.GroupCount) groups vs $($groupsResult.AllGroupIDs.Count) IDs"
    }

} catch {
    Write-Error "Critical error in groups export: $($_.Exception.Message)"
    throw
}
```

## Performance Characteristics

### Throughput Expectations

- **Small organizations** (<100 groups): <30 seconds
- **Medium organizations** (100-500 groups): 1-3 minutes  
- **Large organizations** (500+ groups): 3-5 minutes
- **Target performance**: >300 groups/minute

### Graph API Efficiency

- **Pagination**: 999 groups per API call (maximum allowed)
- **Property selection**: 25+ properties in single API call
- **Connection reuse**: Efficient HTTP connection management
- **Rate limiting**: Automatic retry with exponential backoff

### Memory Usage

- **Batch processing**: Prevents memory accumulation
- **Automatic clearing**: Event Hub batches cleared after transmission
- **Group ID collection**: Lightweight string array storage

## Data Schema

### Output Record Structure

```json
{
    "OdataContext": "groups",
    "ExportId": "12345678-1234-1234-1234-123456789012",
    "ExportTimestamp": "2025-09-01T09:22:18.000Z",
    "Data": {
        "id": "group-guid",
        "displayName": "Engineering Team",
        "description": "Software engineering team group",
        "groupTypes": ["Unified"],
        "securityEnabled": true,
        "mailEnabled": true,
        "mail": "engineering@company.com",
        "membershipRule": null,
        "isAssignableToRole": false,
        "createdDateTime": "2024-01-15T10:30:00Z",
        "visibility": "Private",
        // ... additional 15+ properties
    }
}
```

## Error Handling

### Single-Level Error Pattern (v3.0)

```powershell
try {
    # All groups export logic
    $groupsResult = Export-GroupsWithPagination
} catch {
    # Single-level error handling - no nested catch blocks
    $errorDetails = @{
        ExportId = $CorrelationContext.OperationId
        Stage = 'GroupsExport'
        ErrorMessage = $_.Exception.Message
        ErrorType = Get-ErrorType -Exception $_.Exception
        ProcessedGroups = $groupCount
    }

    Write-CustomTelemetry -EventName "GroupsExportFailed" -Properties $errorDetails
    throw $_
}
```

### Retry Logic

- **Graph API rate limits (429)**: Automatic retry with exponential backoff
- **Server errors (500-503)**: Retry with increasing delays
- **Authentication errors (401)**: No retry - permanent failure
- **Network timeouts**: Retry with connection reset

### Progress Reporting

- **Progress updates**: Every 500 groups processed
- **Performance monitoring**: Groups per minute calculation
- **Memory tracking**: Batch size monitoring

## Dependencies

### Required Functions

- `Invoke-GraphAPIWithRetry`: Graph API calls with retry logic
- `Send-EventsToEventHub`: Event Hub data transmission
- `Write-CustomTelemetry`: Telemetry logging
- `Write-ExportProgress`: Progress reporting
- `Get-ErrorType`: Error classification

### External Dependencies

- **Microsoft Graph API v1.0**: `https://graph.microsoft.com/v1.0/groups`
- **Azure Event Hub**: Data destination via `Send-EventsToEventHub`
- **Application Insights**: Performance and error telemetry

## Telemetry Events

| Event                   | Purpose           | Key Properties                                              |
| ----------------------- | ----------------- | ----------------------------------------------------------- |
| `GroupsExportCompleted` | Success metrics   | TotalGroups, GroupIDsCollected, DurationMs, GroupsPerMinute |
| `GroupsExportFailed`    | Failure analysis  | ErrorMessage, ErrorType, ProcessedGroups                    |
| `ExportProgress`        | Progress tracking | Stage="Groups", ProcessedCount, PercentComplete             |

## Integration Points

### With Main Orchestration

```powershell
# Called from Invoke-AADDataExport after users export
$groupsResult = Export-AADGroups -AuthHeader $authHeader -CorrelationContext $correlationContext

# Group IDs passed to membership export
$membershipsResult = Export-AADGroupMemberships -AuthHeader $authHeader -GroupIDs $groupsResult.AllGroupIDs
```

### Event Hub Data Flow

- **Data type**: "Groups"
- **Batch optimization**: Automatic chunking for 1MB limit
- **JSON depth**: 50 levels for complex nested properties
- **Retry strategy**: 3 attempts with exponential backoff

# 

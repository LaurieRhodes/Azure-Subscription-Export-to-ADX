# Export-AADGroupMemberships

## Purpose

Exports Azure AD group memberships with optimized batch processing to Event Hub for ADX ingestion. This function processes group memberships efficiently using v1.0 production endpoints, implements intelligent batching for Event Hub limits, and provides resilient error handling for individual group failures.

## Key Concepts

### Resilient Group Processing

Processes each group individually with error isolation - if one group fails, processing continues for remaining groups. This ensures maximum data collection even with partial permission issues.

### Intelligent Batching Strategy

- **Batch size optimization**: 2000 membership records per Event Hub batch
- **1MB payload management**: Automatic chunking to respect Event Hub limits
- **Memory efficiency**: Batches cleared after transmission to prevent accumulation

### Member Detail Enhancement

Retrieves comprehensive member information including display names, UPNs, and user types for rich relationship data.

## Parameters

| Parameter            | Type      | Required | Default | Description                                                            |
| -------------------- | --------- | -------- | ------- | ---------------------------------------------------------------------- |
| `AuthHeader`         | Hashtable | Yes      | -       | Authentication headers containing Bearer token for Microsoft Graph API |
| `GroupIDs`           | Array     | Yes      | -       | Array of Group IDs from Export-AADGroups for membership processing     |
| `CorrelationContext` | Hashtable | Yes      | -       | Correlation context with OperationId and tracking information          |

## Return Value

```powershell
@{
    Success = $true/$false              # Overall operation success
    MembershipCount = 3500              # Total membership relationships processed
    ProcessedGroups = 148               # Number of groups attempted
    SuccessfulGroups = 145              # Number of groups successfully processed
    FailedGroups = 3                    # Number of groups that failed processing
    GroupSuccessRate = 97.97            # Percentage of groups successfully processed
    BatchCount = 8                      # Number of Event Hub batches sent
    DurationMs = 89200                  # Total execution time in milliseconds
}
```

## Member Properties Retrieved

### Member Identity

```
id, displayName, userPrincipalName, userType
```

### Output Record Structure

```json
{
    "OdataContext": "GroupMembers",
    "ExportId": "12345678-1234-1234-1234-123456789012",
    "ExportTimestamp": "2025-09-01T09:22:18.000Z",
    "GroupID": "group-guid",
    "Data": {
        "MemberId": "member-guid",
        "MemberDisplayName": "John Doe",
        "MemberUserPrincipalName": "john.doe@company.com",
        "MemberType": "Member"
    }
}
```

## Usage Examples

### Standard Membership Export

```powershell
# Called after successful groups export
$groupsResult = Export-AADGroups -AuthHeader $authHeader -CorrelationContext $correlationContext
$groupIDs = $groupsResult.AllGroupIDs

$membershipsResult = Export-AADGroupMemberships -AuthHeader $authHeader -GroupIDs $groupIDs -CorrelationContext $correlationContext

if ($membershipsResult.Success) {
    Write-Host "✅ Group memberships export completed"
    Write-Host "   Total memberships: $($membershipsResult.MembershipCount)"
    Write-Host "   Groups processed: $($membershipsResult.ProcessedGroups)"
    Write-Host "   Success rate: $($membershipsResult.GroupSuccessRate)%"
    Write-Host "   Failed groups: $($membershipsResult.FailedGroups)"
    Write-Host "   Duration: $([Math]::Round($membershipsResult.DurationMs/1000, 2)) seconds"
}
```

### Error Analysis Example

```powershell
$result = Export-AADGroupMemberships -AuthHeader $authHeader -GroupIDs $groupIDs -CorrelationContext $correlationContext

# Analyze partial failures
if ($result.FailedGroups -gt 0) {
    $failureRate = ($result.FailedGroups / $result.ProcessedGroups) * 100
    Write-Warning "⚠️ $($result.FailedGroups) groups failed processing ($failureRate% failure rate)"

    # Check Application Insights for detailed error analysis
    Write-Host "Check Application Insights with correlation ID: $($correlationContext.OperationId)"
}

# Performance validation
$membershipsPerMinute = [Math]::Round($result.MembershipCount / ($result.DurationMs/60000), 0)
if ($membershipsPerMinute -lt 1500) {
    Write-Warning "⚠️ Membership export performance below baseline (target: >2000/minute)"
}
```

### Large Group Handling

```powershell
# For organizations with very large groups (1000+ members each)
$largeGroupThreshold = 500
$largeGroups = $groupIDs | Where-Object { 
    # Pre-filter for known large groups if needed
    $_ -in $knownLargeGroupIds 
}

if ($largeGroups.Count -gt $largeGroupThreshold) {
    Write-Warning "Processing $($largeGroups.Count) potentially large groups - expect longer execution time"

    # Consider processing in smaller batches for very large tenants
    $batchSize = 100
    for ($i = 0; $i -lt $groupIDs.Count; $i += $batchSize) {
        $groupBatch = $groupIDs[$i..([Math]::Min($i + $batchSize - 1, $groupIDs.Count - 1))]
        $batchResult = Export-AADGroupMemberships -AuthHeader $authHeader -GroupIDs $groupBatch -CorrelationContext $correlationContext
    }
}
```

## Performance Characteristics

### Throughput Expectations

- **Small groups** (<50 members avg): 2000-3000 memberships/minute
- **Medium groups** (50-200 members avg): 1500-2500 memberships/minute
- **Large groups** (200+ members avg): 1000-2000 memberships/minute

### Processing Strategy

- **Sequential group processing**: One group at a time for error isolation
- **Pagination per group**: Handles groups with 1000+ members
- **Rate limiting with jitter**: 1-2 second delays between groups to avoid throttling
- **Intelligent batching**: 2000 memberships per Event Hub batch (optimal for 1MB limit)

### Memory Management

```powershell
# Batch clearing strategy
$membershipBatch = @()
if ($membershipBatch.Count -ge $batchSizeLimit) {
    Send-EventsToEventHub -payload (ConvertTo-Json -InputObject $membershipBatch -Depth 50)
    $membershipBatch = @()  # Clear to prevent memory accumulation
}
```

## Error Handling

### Individual Group Failure Strategy

```powershell
foreach ($GroupID in $GroupIDs) {
    try {
        # Process individual group memberships
        $membersResponse = Invoke-GraphAPIWithRetry -Uri $membersApiUrl
        # Process members...
    } catch {
        # Log group-specific error but continue processing
        Write-Warning "Failed to get members for group $GroupID: $($_.Exception.Message)"
        $failedGroups += $GroupID
        continue  # Continue with next group
    }
}
```

### Common Error Scenarios

- **Permission denied for specific groups**: Continue processing, log failure
- **Large group timeouts**: Retry with exponential backoff
- **Event Hub batch failures**: Retry batch transmission
- **Graph API rate limiting**: Automatic backoff across all groups

## Performance Monitoring

### Application Insights Queries

```kusto
// Group membership processing performance
customEvents
| where name == "GroupMembershipsExportCompleted"
| extend 
    MembershipCount = toint(customDimensions.TotalMemberships),
    ProcessedGroups = toint(customDimensions.ProcessedGroups),
    Duration = todouble(customDimensions.DurationMs) / 1000,
    SuccessRate = todouble(customDimensions.GroupSuccessRate)
| extend 
    MembershipsPerMinute = MembershipCount / (Duration / 60),
    GroupsPerMinute = ProcessedGroups / (Duration / 60)
| project timestamp, MembershipCount, ProcessedGroups, SuccessRate, MembershipsPerMinute, GroupsPerMinute
| render timechart

// Group failure analysis
customEvents
| where name == "GroupMembershipError"
| extend GroupID = tostring(customDimensions.GroupID), ErrorType = tostring(customDimensions.ErrorType)
| summarize FailureCount = count() by ErrorType, bin(timestamp, 1h)
| render columnchart
```

### Performance Baselines

- **Target throughput**: >2000 memberships/minute
- **Acceptable success rate**: >95% groups processed successfully
- **Memory usage**: <300MB during processing
- **Event Hub batch efficiency**: 5-10 batches per 1000 memberships

## Dependencies

### Required Functions

- `Invoke-GraphAPIWithRetry`: Graph API calls with retry logic
- `Send-EventsToEventHub`: Event Hub data transmission
- `Write-CustomTelemetry`: Telemetry logging
- `Write-ExportProgress`: Progress reporting
- `Get-ErrorType`: Error classification

### Required Input Data

- **Group IDs array**: From successful Export-AADGroups execution
- **Authentication headers**: Valid Microsoft Graph Bearer token
- **Correlation context**: For tracking and telemetry correlation

### External Dependencies

- **Microsoft Graph API v1.0**: `https://graph.microsoft.com/v1.0/groups/{id}/members`
- **Azure Event Hub**: Batch data transmission
- **Application Insights**: Error and performance telemetry

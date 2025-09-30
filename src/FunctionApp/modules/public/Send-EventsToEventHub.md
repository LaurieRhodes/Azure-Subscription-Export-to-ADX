# Send-EventsToEventHub

## Purpose

Transmits JSON payload to Azure Event Hub with intelligent chunking for 1MB payload limits. This function handles the final stage of the data pipeline, ensuring reliable delivery of AAD export data to Event Hub for Azure Data Explorer ingestion.

## Key Concepts

### Intelligent Payload Chunking

Automatically splits large JSON payloads into chunks that respect Event Hub's 1MB message size limit, ensuring reliable transmission without data loss.

### Comprehensive Error Diagnostics

Provides detailed error analysis and configuration guidance for common Event Hub issues, including permission problems and connectivity issues.

### Managed Identity Authentication

Uses User-Assigned Managed Identity for secure, credential-less authentication to Event Hub services.

## Parameters

| Parameter | Type   | Required | Default | Description                                          |
| --------- | ------ | -------- | ------- | ---------------------------------------------------- |
| `Payload` | String | Yes      | -       | JSON string containing the data to send to Event Hub |

## Environment Variables Required

| Variable            | Description                              | Example                                |
| ------------------- | ---------------------------------------- | -------------------------------------- |
| `EVENTHUBNAMESPACE` | Event Hub Namespace name                 | `my-eventhub-ns`                       |
| `EVENTHUBNAME`      | Target Event Hub name                    | `aad-export-hub`                       |
| `CLIENTID`          | User-Assigned Managed Identity Client ID | `12345678-1234-1234-1234-123456789012` |

## Return Value

```powershell
@{
    ChunksSent = 5                      # Number of chunks successfully transmitted
    TotalChunks = 5                     # Total number of chunks created
    Success = $true/$false              # Overall transmission success
    EventHubUri = "https://..."         # Complete Event Hub endpoint URI
}
```

## Usage Examples

### Standard Event Hub Transmission

```powershell
# Prepare data for transmission
$userData = @(
    @{ id = "user1"; displayName = "John Doe" },
    @{ id = "user2"; displayName = "Jane Smith" }
)
$jsonPayload = ConvertTo-Json -InputObject $userData -Depth 50

# Send to Event Hub
try {
    $result = Send-EventsToEventHub -payload $jsonPayload

    if ($result.Success) {
        Write-Host "✅ Successfully sent $($result.ChunksSent) chunks to Event Hub"
        Write-Host "   Event Hub: $($result.EventHubUri)"
    } else {
        Write-Error "❌ Event Hub transmission failed"
    }
} catch {
    Write-Error "Critical Event Hub error: $($_.Exception.Message)"
    throw
}
```

### Large Payload Handling

```powershell
# Example with large dataset that will be automatically chunked
$largeDataset = @()
for ($i = 1; $i -le 5000; $i++) {
    $largeDataset += @{ 
        id = "user$i"
        displayName = "User $i"
        # Additional properties...
    }
}

$jsonPayload = ConvertTo-Json -InputObject $largeDataset -Depth 50
Write-Host "Payload size: $([Math]::Round([System.Text.Encoding]::UTF8.GetByteCount($jsonPayload)/1MB, 2)) MB"

# Automatic chunking will split this into multiple Event Hub messages
$result = Send-EventsToEventHub -payload $jsonPayload
Write-Host "Split into $($result.TotalChunks) chunks for transmission"
```

### Error Handling with Diagnostics

```powershell
try {
    $result = Send-EventsToEventHub -payload $jsonPayload
} catch [System.Security.Authentication.AuthenticationException] {
    Write-Error "❌ AUTHENTICATION ERROR - Check managed identity permissions"
    Write-Error "Required: 'Azure Event Hubs Data Sender' role on Event Hub Namespace"
    throw
} catch [System.UnauthorizedAccessException] {
    Write-Error "❌ AUTHORIZATION ERROR - Insufficient permissions"
    throw
} catch [System.ArgumentException] {
    Write-Error "❌ CONFIGURATION ERROR - Event Hub not found"
    Write-Error "Check EVENTHUBNAMESPACE and EVENTHUBNAME environment variables"
    throw
} catch {
    Write-Error "❌ COMMUNICATION ERROR: $($_.Exception.Message)"
    throw
}
```

## Chunking Algorithm

### Payload Size Management

```powershell
$maxPayloadSize = 900KB  # Safe margin under Event Hub 1MB limit

# Chunking logic
$chunk = @()
$currentSize = 0

foreach ($record in $PayloadObject) {
    $recordJson = ConvertTo-Json -InputObject $record -Depth 50
    $recordSize = [System.Text.Encoding]::UTF8.GetByteCount($recordJson)

    if (($currentSize + $recordSize) -ge $maxPayloadSize) {
        # Send current chunk and start new one
        $messages += ,@($chunk)
        $chunk = @()
        $currentSize = 0
    }

    $chunk += $record
    $currentSize += $recordSize
}
```

### Chunk Processing Strategy

- **Record-level chunking**: Ensures no individual records are split
- **Size calculation**: UTF-8 byte count for accurate size management
- **Optimal utilization**: Maximizes chunk size while staying under limits
- **Final chunk handling**: Processes remaining records in final transmission

## Error Handling

### Comprehensive Error Diagnostics

#### Permission Errors (HTTP 401)

```powershell
if ($exceptionMessage -match "401|unauthorized") {
    Write-Error "EVENT HUB PERMISSION ERROR - This is a FATAL configuration issue"
    Write-Error "1. Managed Identity '$($env:CLIENTID)' needs 'Azure Event Hubs Data Sender' role"
    Write-Error "2. Role assignment on Event Hub Namespace: '$($env:EVENTHUBNAMESPACE)'"
    Write-Error "3. Target Event Hub: '$($env:EVENTHUBNAME)'"
    Write-Error "4. NOTE: Managed identity permissions can take up to 24 hours to propagate"
    Write-Error "5. RECOMMENDATION: Wait 24 hours after role assignment or use alternative authentication"
}
```

#### Configuration Errors (HTTP 404)

```powershell
if ($exceptionMessage -match "404|not found") {
    Write-Error "EVENT HUB NOT FOUND - Check namespace and Event Hub names"
    Write-Error "Namespace: '$($env:EVENTHUBNAMESPACE)'"
    Write-Error "Event Hub: '$($env:EVENTHUBNAME)'"
}
```

#### Authorization Errors (HTTP 403)

```powershell
if ($exceptionMessage -match "403|forbidden") {
    Write-Error "EVENT HUB AUTHORIZATION ERROR - Managed identity has insufficient permissions"
}
```

### Retry Strategy

- **Transient errors**: Retry with exponential backoff
- **Authentication errors**: No retry - permanent failure requiring configuration fix
- **Rate limiting**: Retry with extended delays
- **Network errors**: Retry with connection reset

## Performance Characteristics

### Transmission Speed

- **Small payloads** (<100KB): 1-2 seconds per transmission
- **Medium payloads** (100KB-900KB): 2-5 seconds per transmission
- **Large payloads** (requiring chunking): 5-15 seconds total

### Chunking Efficiency

- **Optimal chunk size**: 900KB (safe margin under 1MB limit)
- **Chunking overhead**: Minimal - record-level granularity
- **Memory management**: Chunks processed sequentially to minimize memory usage

### Throughput Monitoring

```kusto
// Application Insights query for Event Hub performance
dependencies
| where name == "Event Hub"
| extend ChunkCount = toint(customDimensions.TotalChunks)
| summarize 
    AvgDuration = avg(duration),
    AvgChunksPerTransmission = avg(ChunkCount),
    SuccessRate = avg(iff(success, 1.0, 0.0))
by bin(timestamp, 1h)
| render timechart
```

## Dependencies

### Required Functions

- `Get-AzureADToken`: Event Hub authentication token acquisition

### Required Environment Variables

- `EVENTHUBNAMESPACE`: Event Hub Namespace name
- `EVENTHUBNAME`: Target Event Hub name  
- `CLIENTID`: User-Assigned Managed Identity Client ID

### External Dependencies

- **Azure Event Hub**: Target data destination
- **User-Assigned Managed Identity**: Authentication provider
- **Azure Identity Endpoint**: Token acquisition service

## Data Flow Integration

### Within Export Pipeline

```powershell
# Called from each export function
$eventHubScriptBlock = {
    Send-EventsToEventHub -payload (ConvertTo-Json -InputObject $batch -Depth 50)
}

# Wrapped with retry logic
Invoke-WithRetry -ScriptBlock $eventHubScriptBlock -MaxRetryCount 3 -OperationName "SendToEventHub"
```

### Batch Processing Pattern

- **Users export**: Multiple batches during pagination
- **Groups export**: Batched transmission of group records
- **Memberships export**: Large batches optimized for 1MB limits

# 

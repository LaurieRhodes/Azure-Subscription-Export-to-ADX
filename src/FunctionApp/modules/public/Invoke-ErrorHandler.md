# Invoke-ErrorHandler Functions

## Purpose

Provides comprehensive error handling functions for AAD Export operations with Application Insights integration. This module implements enterprise-grade error handling patterns using single-level error handling without nested catch blocks for cleaner, more maintainable code.

## Key Concepts

### Single-Level Error Handling (v3.0)

All error handling uses a single try-catch level with error processing outside the catch block to eliminate nested complexity and improve maintainability.

### Intelligent Retry Logic

Implements sophisticated retry strategies with exponential backoff, error type classification, and telemetry integration for production-grade resilience.

### Comprehensive Telemetry

Every operation includes structured telemetry with correlation tracking, performance metrics, and error classification for operational visibility.

---

## Invoke-WithRetry

### Purpose

Executes operations with exponential backoff retry logic and comprehensive telemetry tracking.

### Parameters

| Parameter             | Type        | Required | Default   | Description                                |
| --------------------- | ----------- | -------- | --------- | ------------------------------------------ |
| `ScriptBlock`         | ScriptBlock | Yes      | -         | The operation to execute with retry logic  |
| `MaxRetryCount`       | Int32       | No       | 3         | Maximum number of retry attempts           |
| `InitialDelaySeconds` | Int32       | No       | 2         | Initial delay before first retry           |
| `OperationName`       | String      | No       | "Unknown" | Operation name for telemetry and logging   |
| `TelemetryProperties` | Hashtable   | No       | @{}       | Additional properties for telemetry events |

### Return Value

Returns the result of the successful ScriptBlock execution, or throws the final exception if all retries fail.

### Usage Examples

```powershell
# Standard retry usage
$result = Invoke-WithRetry -ScriptBlock {
    Invoke-RestMethod -Uri $uri -Headers $headers
} -MaxRetryCount 3 -OperationName "GraphAPICall" -TelemetryProperties @{
    Endpoint = "Users"
    PageSize = 999
}

# Custom retry configuration
$result = Invoke-WithRetry -ScriptBlock {
    Send-EventsToEventHub -payload $jsonData
} -MaxRetryCount 5 -InitialDelaySeconds 1 -OperationName "EventHubTransmission"
```

### Retry Strategy

- **Exponential backoff**: Delay = 2^(attempt-1) * InitialDelaySeconds
- **Maximum delay**: Capped at 60 seconds
- **Intelligent retry decision**: Based on error type classification
- **Telemetry logging**: Every attempt logged with timing and results

---

## Invoke-GraphAPIWithRetry

### Purpose

Specialized Graph API calls with dependency telemetry and retry logic, optimized for Microsoft Graph API patterns.

### Parameters

| Parameter            | Type      | Required | Default | Description                              |
| -------------------- | --------- | -------- | ------- | ---------------------------------------- |
| `Uri`                | String    | Yes      | -       | Microsoft Graph API endpoint URL         |
| `Headers`            | Hashtable | Yes      | -       | Authentication headers with Bearer token |
| `Method`             | String    | No       | "GET"   | HTTP method for the API call             |
| `CorrelationContext` | Hashtable | No       | @{}     | Correlation context for telemetry        |
| `MaxRetryCount`      | Int32     | No       | 3       | Maximum retry attempts                   |

### Return Value

Returns the Graph API response object or throws exception if all retries fail.

### Usage Examples

```powershell
# Standard Graph API call
$response = Invoke-GraphAPIWithRetry -Uri "https://graph.microsoft.com/v1.0/users" -Headers $authHeader -CorrelationContext $context -MaxRetryCount 5

# With correlation context
$context = @{
    OperationId = $exportId
    Stage = "UsersExport"
    PageNumber = 1
}
$response = Invoke-GraphAPIWithRetry -Uri $usersApiUrl -Headers $authHeader -CorrelationContext $context
```

### Features

- **Dependency tracking**: Automatic Application Insights dependency telemetry
- **Performance timing**: Precise duration measurement for all calls
- **Graph-specific error handling**: Optimized for Graph API error patterns
- **Correlation propagation**: Maintains correlation context across calls

---

## Write-CustomTelemetry

### Purpose

Logs structured events to Application Insights with properties and metrics for operational monitoring.

### Parameters

| Parameter    | Type      | Required | Default | Description                     |
| ------------ | --------- | -------- | ------- | ------------------------------- |
| `EventName`  | String    | Yes      | -       | Name of the telemetry event     |
| `Properties` | Hashtable | No       | @{}     | Custom properties for the event |
| `Metrics`    | Hashtable | No       | @{}     | Numeric metrics for the event   |

### Usage Examples

```powershell
# Success event logging
Write-CustomTelemetry -EventName "UsersExportCompleted" -Properties @{
    ExportId = $correlationId
    UserCount = 1250
    DurationMs = 45300
} -Metrics @{
    UsersPerMinute = 1421
    BatchesCreated = 8
}

# Error event logging
Write-CustomTelemetry -EventName "GraphAPIError" -Properties @{
    ErrorType = "RateLimit"
    HttpStatusCode = 429
    Endpoint = "Users"
    RetryAttempt = 2
}
```

### Standard Event Names

- `AADExportStarted`, `AADExportCompleted`, `AADExportFailed`
- `UsersExportCompleted`, `GroupsExportCompleted`, `GroupMembershipsExportCompleted`
- `OperationSuccess`, `OperationRetry`, `OperationFailure`
- `GraphAPIError`, `EventHubError`, `AuthenticationError`

---

## Write-DependencyTelemetry

### Purpose

Tracks external dependency calls (Graph API, Event Hub) with timing and success metrics for Application Insights dependency tracking.

### Parameters

| Parameter        | Type      | Required | Default | Description                                   |
| ---------------- | --------- | -------- | ------- | --------------------------------------------- |
| `DependencyName` | String    | Yes      | -       | Name of the external dependency               |
| `Target`         | String    | Yes      | -       | Target URL or identifier                      |
| `DurationMs`     | Long      | Yes      | -       | Operation duration in milliseconds            |
| `Success`        | Bool      | Yes      | -       | Whether the dependency call succeeded         |
| `Properties`     | Hashtable | No       | @{}     | Additional properties for the dependency call |

### Usage Examples

```powershell
# Graph API dependency tracking
Write-DependencyTelemetry -DependencyName "Microsoft Graph API" -Target $uri -DurationMs $duration -Success $true -Properties @{
    HttpStatusCode = 200
    RecordsReturned = 999
    ApiVersion = "v1.0"
}

# Event Hub dependency tracking
Write-DependencyTelemetry -DependencyName "Azure Event Hub" -Target $eventHubUri -DurationMs $duration -Success $false -Properties @{
    ErrorType = "Authentication"
    ChunkNumber = 3
    PayloadSizeKB = 850
}
```

---

## New-CorrelationContext

### Purpose

Creates correlation context for tracking operations across all stages and external dependencies.

### Parameters

| Parameter       | Type   | Required | Default         | Description                         |
| --------------- | ------ | -------- | --------------- | ----------------------------------- |
| `OperationId`   | String | No       | New GUID        | Unique identifier for the operation |
| `OperationName` | String | No       | "AADDataExport" | Name of the operation for telemetry |

### Return Value

```powershell
@{
    OperationId = "12345678-1234-1234-1234-123456789012"
    OperationName = "AADDataExport"
    ParentId = $null
    StartTime = [DateTime]
}
```

### Usage Examples

```powershell
# Create correlation context for new export
$correlationContext = New-CorrelationContext -OperationName "AADDataExport"

# Create context with specific ID
$correlationContext = New-CorrelationContext -OperationId "custom-guid" -OperationName "TestExport"

# Use in telemetry
$telemetryProps = $correlationContext.Clone()
$telemetryProps['Stage'] = 'UsersExport'
Write-CustomTelemetry -EventName "StageStarted" -Properties $telemetryProps
```

---

## Write-ExportProgress

### Purpose

Logs progress updates during long-running export operations with percentage calculations and telemetry integration.

### Parameters

| Parameter            | Type      | Required | Default | Description                                         |
| -------------------- | --------- | -------- | ------- | --------------------------------------------------- |
| `Stage`              | String    | Yes      | -       | Current export stage name                           |
| `ProcessedCount`     | Int32     | Yes      | -       | Number of items processed so far                    |
| `TotalCount`         | Int32     | No       | 0       | Total items to process (for percentage calculation) |
| `CorrelationContext` | Hashtable | No       | @{}     | Correlation context for telemetry                   |

### Usage Examples

```powershell
# Progress with percentage calculation
Write-ExportProgress -Stage "GroupMemberships" -ProcessedCount 750 -TotalCount 1000 -CorrelationContext $context
# Output: "GroupMemberships - Progress: 750 of 1000 (75%)"

# Progress without total count
Write-ExportProgress -Stage "Users" -ProcessedCount 1250 -CorrelationContext $context
# Output: "Users - Processed: 1250 records"
```

---

## Error Classification Functions

### Get-ErrorType

### Purpose

Classifies exceptions into actionable error types for intelligent retry logic and error handling.

### Parameters

| Parameter   | Type                  | Required | Description                                     |
| ----------- | --------------------- | -------- | ----------------------------------------------- |
| `Exception` | ErrorRecord/Exception | Yes      | PowerShell ErrorRecord or .NET Exception object |

### Return Value

Returns a classified error type string for retry decision making.

### Error Classifications

- `RateLimit (HTTP 429)`: Always retry with backoff
- `ServerError (HTTP 500)`: Retry for transient issues  
- `Network`: Retry for connectivity issues
- `Authentication (HTTP 401)`: No retry - requires token refresh
- `Authorization (HTTP 403)`: No retry - insufficient permissions
- `EventHub`: No retry - configuration issue

### Usage Examples

```powershell
try {
    $result = Invoke-RestMethod -Uri $uri -Headers $headers
} catch {
    $errorType = Get-ErrorType -Exception $_

    if ($errorType -match "RateLimit") {
        Write-Warning "Rate limit encountered - will retry with backoff"
    } elseif ($errorType -match "Authentication") {
        Write-Error "Authentication failed - check token and permissions"
        throw
    }
}
```

---

## Get-HttpStatusCode

### Purpose

Extracts HTTP status codes from exceptions for detailed error analysis and classification.

### Parameters

| Parameter   | Type                  | Required | Description                                     |
| ----------- | --------------------- | -------- | ----------------------------------------------- |
| `Exception` | ErrorRecord/Exception | Yes      | PowerShell ErrorRecord or .NET Exception object |

### Return Value

Returns integer HTTP status code or `$null` if no status code found.

### Usage Examples

```powershell
try {
    $response = Invoke-RestMethod -Uri $uri -Headers $headers
} catch {
    $statusCode = Get-HttpStatusCode -Exception $_
    $errorType = Get-ErrorType -Exception $_

    Write-CustomTelemetry -EventName "APIError" -Properties @{
        HttpStatusCode = $statusCode
        ErrorType = $errorType
        Endpoint = $uri
    }

    switch ($statusCode) {
        401 { Write-Error "Authentication required" }
        403 { Write-Error "Access forbidden" }
        429 { Write-Warning "Rate limited - will retry" }
        { $_ -ge 500 } { Write-Warning "Server error - will retry" }
    }
}
```

---

## Test-ShouldRetry

### Purpose

Determines if an operation should be retried based on error type and context, preventing unnecessary retries for permanent failures.

### Parameters

| Parameter   | Type                  | Required | Description                              |
| ----------- | --------------------- | -------- | ---------------------------------------- |
| `Exception` | ErrorRecord/Exception | Yes      | The exception that occurred              |
| `ErrorType` | String                | Yes      | Classified error type from Get-ErrorType |

### Return Value

Returns `$true` if the operation should be retried, `$false` for permanent failures.

### Retry Decision Logic

```powershell
# Retryable errors
$retryableErrors = @(
    "RateLimit",           # 429 - Always retry with backoff
    "ServerError",         # 500 - Temporary server issues
    "BadGateway",          # 502 - Proxy/gateway issues
    "ServiceUnavailable",  # 503 - Service temporarily down
    "Timeout",             # 504 - Request timeout
    "Network",             # Network connectivity issues
    "Connection",          # Connection failures
    "DNS"                  # DNS resolution failures
)

# Non-retryable errors (fail fast)
$nonRetryableErrors = @(
    "Authentication",      # 401 - Need new token or permissions
    "Authorization",       # 403 - Insufficient permissions
    "TokenError",          # Token format or validation issues
    "EventHub"            # Event Hub specific errors often need configuration fixes
)
```

### Usage Examples

```powershell
try {
    $result = Invoke-RestMethod -Uri $uri -Headers $headers
} catch {
    $errorType = Get-ErrorType -Exception $_
    $shouldRetry = Test-ShouldRetry -Exception $_ -ErrorType $errorType

    if ($shouldRetry) {
        Write-Warning "Retryable error detected: $errorType"
        # Implement retry logic
    } else {
        Write-Error "Permanent failure detected: $errorType"
        throw  # Don't retry
    }
}
```

## Integration with Main Export Functions

### Retry Wrapper Pattern

```powershell
# Used throughout export functions
$authScriptBlock = {
    Get-AzureADToken -resource "https://graph.microsoft.com" -clientId $env:ClientId
}

$token = Invoke-WithRetry -ScriptBlock $authScriptBlock -MaxRetryCount 2 -OperationName "GetGraphToken"
```

### Telemetry Integration

```powershell
# Automatic telemetry for all retry operations
$telemetryProps = @{
    OperationName = "GraphAPICall"
    Endpoint = "Users"
    PageSize = 999
}

$result = Invoke-WithRetry -ScriptBlock $operation -TelemetryProperties $telemetryProps
# Generates: OperationSuccess, OperationRetry, or OperationFailure events
```

## Error Classification Examples

### Graph API Errors

```powershell
# Rate limiting
Get-ErrorType -Exception $graphRateLimitError
# Returns: "WebException (HTTP 429)"

# Authentication failure  
Get-ErrorType -Exception $authError
# Returns: "AuthenticationException (Authentication)"
```

### Event Hub Errors

```powershell
# Permission denied
Get-ErrorType -Exception $eventHubAuthError
# Returns: "UnauthorizedAccessException (EventHub)"

# Network connectivity
Get-ErrorType -Exception $networkError  
# Returns: "WebException (Network)"
```

## Dependencies

### Required Functions

- `Get-ErrorType`: Error classification
- `Get-HttpStatusCode`: HTTP status extraction
- `Test-ShouldRetry`: Retry decision logic
- `Write-CustomTelemetry`: Telemetry logging
- `Write-DependencyTelemetry`: Dependency tracking

### External Dependencies

- **Application Insights**: Telemetry destination
- **Azure Functions runtime**: For structured logging integration

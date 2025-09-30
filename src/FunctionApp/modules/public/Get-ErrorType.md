# Get-ErrorType

## Purpose

Classifies exceptions into actionable error types for intelligent retry logic and error handling. This function provides standardized error categorization that drives retry decisions throughout the AAD export pipeline.

## Key Concepts

### Exception Type Handling

Handles both PowerShell ErrorRecord objects and .NET Exception objects, providing consistent error classification regardless of the error source.

### HTTP Status Code Recognition

Automatically extracts and incorporates HTTP status codes from web exceptions for precise error classification.

### Context-Aware Classification

Analyzes error messages and exception types to provide contextual error categories (Network, Authentication, EventHub, etc.).

## Parameters

| Parameter   | Type                  | Required | Description                                                 |
| ----------- | --------------------- | -------- | ----------------------------------------------------------- |
| `Exception` | ErrorRecord/Exception | Yes      | PowerShell ErrorRecord or .NET Exception object to classify |

## Return Value

Returns a string containing the classified error type, often with additional context:

```powershell
# Examples of return values
"WebException (HTTP 429)"           # Rate limiting
"AuthenticationException (Authentication)"  # Auth failure
"UnauthorizedAccessException (EventHub)"   # Event Hub permissions
"HttpRequestException (Network)"           # Network connectivity
"ArgumentException"                        # Generic argument error
```

## Error Classification Categories

### HTTP-Based Classifications

- `ErrorType (HTTP 400)`: Bad Request
- `ErrorType (HTTP 401)`: Unauthorized  
- `ErrorType (HTTP 403)`: Forbidden
- `ErrorType (HTTP 429)`: Too Many Requests (Rate Limit)
- `ErrorType (HTTP 500)`: Internal Server Error
- `ErrorType (HTTP 502)`: Bad Gateway
- `ErrorType (HTTP 503)`: Service Unavailable

### Context-Based Classifications

- `ErrorType (Network)`: Socket, connection, timeout issues
- `ErrorType (Authentication)`: Auth, token, unauthorized issues
- `ErrorType (EventHub)`: Event Hub or Service Bus specific errors

## Usage Examples

### Standard Error Classification

```powershell
try {
    $response = Invoke-RestMethod -Uri $uri -Headers $headers
} catch {
    $errorType = Get-ErrorType -Exception $_

    Write-Host "Error classification: $errorType"

    # Use classification for retry logic
    $shouldRetry = Test-ShouldRetry -Exception $_ -ErrorType $errorType
}
```

### Integration with Retry Logic

```powershell
# Used within Invoke-WithRetry function
catch {
    $operationFailed = $true
    $errorType = Get-ErrorType -Exception $_
    $shouldRetry = $attempt -lt ($MaxRetryCount + 1) -and (Test-ShouldRetry -Exception $_ -ErrorType $errorType)
}
```

### Telemetry Integration

```powershell
# Error classification for structured logging
try {
    $result = Invoke-Operation
} catch {
    $errorProps = @{
        ErrorType = Get-ErrorType -Exception $_
        ErrorMessage = $_.Exception.Message
        HttpStatusCode = Get-HttpStatusCode -Exception $_
        OperationName = "GraphAPICall"
    }

    Write-CustomTelemetry -EventName "OperationError" -Properties $errorProps
}
```

## Classification Logic

### HTTP Status Code Extraction

```powershell
# Regex pattern matching for HTTP codes
if ($actualException.Message -match "(\d{3})") {
    $httpCode = $Matches[1]
    return "$errorType (HTTP $httpCode)"
}
```

### Message Pattern Analysis

```powershell
# Network-related errors
if ($errorMessage -match "socket|network|connection|timeout") {
    return "$errorType (Network)"
}

# Authentication-related errors
if ($errorMessage -match "auth|token|unauthorized|forbidden") {
    return "$errorType (Authentication)"
}

# Event Hub specific errors
if ($errorMessage -match "eventhub|servicebus") {
    return "$errorType (EventHub)"
}
```

### PowerShell vs .NET Exception Handling

```powershell
# Handles both PowerShell ErrorRecord and .NET Exception
$actualException = if ($Exception -is [System.Management.Automation.ErrorRecord]) {
    $Exception.Exception
} else {
    $Exception
}
```

## Dependencies

### Required Functions

None - this is a foundational utility function.

### Exception Types Handled

- `System.Net.WebException`: HTTP-related errors
- `System.Security.Authentication.AuthenticationException`: Authentication failures
- `System.UnauthorizedAccessException`: Permission errors
- `System.ArgumentException`: Configuration errors
- `System.Net.Http.HttpRequestException`: HTTP client errors
- `System.Management.Automation.ErrorRecord`: PowerShell errors

## Integration Points

### With Retry Logic

```powershell
# Primary integration point
$errorType = Get-ErrorType -Exception $_
$shouldRetry = Test-ShouldRetry -Exception $_ -ErrorType $errorType
```

### With Telemetry

```powershell
# Error telemetry enhancement
$errorDetails = @{
    ErrorType = Get-ErrorType -Exception $_
    HttpStatusCode = Get-HttpStatusCode -Exception $_
    Timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
}
```

### With Progress Reporting

```powershell
# Error context in progress reports
Write-ExportProgress -Stage "Users" -ProcessedCount $count -CorrelationContext @{
    LastErrorType = Get-ErrorType -Exception $lastError
}
```

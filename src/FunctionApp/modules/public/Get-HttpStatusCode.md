# Get-HttpStatusCode

## Purpose

Extracts HTTP status codes from exceptions for detailed error analysis and classification. This function provides precise HTTP status code identification from various exception types for accurate error handling and telemetry.

## Key Concepts

### Exception Type Agnostic

Handles both PowerShell ErrorRecord objects and .NET Exception objects, extracting HTTP status codes regardless of the error source.

### Multiple Extraction Methods

Uses multiple strategies to extract HTTP status codes: regex pattern matching from error messages and direct property access from web exception objects.

### Integration with Error Classification

Works closely with `Get-ErrorType` and `Test-ShouldRetry` to provide comprehensive error analysis for retry logic.

## Parameters

| Parameter   | Type                  | Required | Description                                                |
| ----------- | --------------------- | -------- | ---------------------------------------------------------- |
| `Exception` | ErrorRecord/Exception | Yes      | PowerShell ErrorRecord or .NET Exception object to analyze |

## Return Value

Returns an integer HTTP status code or `$null` if no status code can be extracted.

```powershell
# Example return values
200, 401, 403, 429, 500, 502, 503, 504, $null
```

## Usage Examples

### Standard HTTP Status Extraction

```powershell
try {
    $response = Invoke-RestMethod -Uri $uri -Headers $headers
} catch {
    $statusCode = Get-HttpStatusCode -Exception $_

    switch ($statusCode) {
        401 { 
            Write-Error "Authentication required - check token validity"
            # Don't retry - permanent failure
        }
        403 { 
            Write-Error "Access forbidden - check permissions"
            # Don't retry - permanent failure
        }
        429 { 
            Write-Warning "Rate limited - will retry with backoff"
            # Retry with exponential backoff
        }
        { $_ -ge 500 } { 
            Write-Warning "Server error ($statusCode) - will retry"
            # Retry for server errors
        }
        $null { 
            Write-Warning "No HTTP status code available - analyzing error type"
            # Fall back to error type analysis
        }
    }
}
```

### Integration with Telemetry

```powershell
# Enhanced error telemetry with HTTP status codes
try {
    $result = Invoke-GraphAPIWithRetry -Uri $uri -Headers $headers
} catch {
    $errorDetails = @{
        ErrorType = Get-ErrorType -Exception $_
        HttpStatusCode = Get-HttpStatusCode -Exception $_
        ErrorMessage = $_.Exception.Message
        Endpoint = $uri
        Timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    }

    Write-CustomTelemetry -EventName "GraphAPIError" -Properties $errorDetails
    throw
}
```

### Retry Decision Enhancement

```powershell
# Used in conjunction with error type for retry decisions
$errorType = Get-ErrorType -Exception $_
$statusCode = Get-HttpStatusCode -Exception $_

# Enhanced retry logic based on both error type and status code
$shouldRetry = switch ($statusCode) {
    401 { $false }  # Authentication - don't retry
    403 { $false }  # Authorization - don't retry  
    429 { $true }   # Rate limit - always retry
    { $_ -ge 500 } { $true }  # Server errors - retry
    default { Test-ShouldRetry -Exception $_ -ErrorType $errorType }
}
```

## HTTP Status Code Categories

### Success Codes (2xx)

- `200`: OK - Operation successful
- `201`: Created - Resource created successfully
- `202`: Accepted - Request accepted for processing

### Client Error Codes (4xx)

- `400`: Bad Request - Invalid request syntax
- `401`: Unauthorized - Authentication required
- `403`: Forbidden - Access denied
- `404`: Not Found - Resource not found
- `429`: Too Many Requests - Rate limit exceeded

### Server Error Codes (5xx)

- `500`: Internal Server Error - Server encountered error
- `502`: Bad Gateway - Gateway/proxy error
- `503`: Service Unavailable - Service temporarily down
- `504`: Gateway Timeout - Gateway timeout

## Extraction Methods

### Regex Pattern Matching

```powershell
# Extract from error message text
if ($actualException.Message -match "(\d{3})") {
    return [int]$Matches[1]
}
```

### WebException Property Access

```powershell
# Direct property access for WebException
if ($actualException -is [System.Net.WebException]) {
    $webException = [System.Net.WebException]$actualException
    if ($webException.Response -and $webException.Response -is [System.Net.HttpWebResponse]) {
        return [int]$webException.Response.StatusCode
    }
}
```

### PowerShell ErrorRecord Handling

```powershell
# Handle PowerShell ErrorRecord vs .NET Exception
$actualException = if ($Exception -is [System.Management.Automation.ErrorRecord]) {
    $Exception.Exception
} else {
    $Exception
}
```

## Performance Characteristics

### Execution Speed

- **Regex matching**: Sub-millisecond execution
- **Property access**: Direct object property lookup
- **Memory usage**: Minimal - no object creation or caching

### Error Message Patterns

```powershell
# Common patterns recognized
"The remote server returned an error: (401) Unauthorized"      # Returns: 401
"HTTP 429 Too Many Requests"                                   # Returns: 429  
"Server Error 500 - Internal Server Error"                    # Returns: 500
"Network connection timeout"                                   # Returns: $null
```

## Dependencies

### Required Functions

None - this is a foundational utility function.

### Exception Types Supported

- `System.Net.WebException`: Primary web exception type
- `System.Net.Http.HttpRequestException`: HTTP client exceptions
- `System.Management.Automation.ErrorRecord`: PowerShell error wrapper
- `System.Exception`: Base exception type

## Integration Points

### With Error Classification

```powershell
# Used together for comprehensive error analysis
$errorType = Get-ErrorType -Exception $_
$statusCode = Get-HttpStatusCode -Exception $_

# Combined analysis
$errorClassification = if ($statusCode) {
    "$errorType (HTTP $statusCode)"
} else {
    $errorType
}
```

### With Monitoring Queries

```kusto
// Application Insights error analysis by status code
customEvents
| where name contains "Error" or name contains "Failed"
| extend HttpStatusCode = toint(customDimensions.HttpStatusCode)
| where isnotnull(HttpStatusCode)
| summarize ErrorCount = count() by HttpStatusCode, bin(timestamp, 1h)
| render columnchart
```

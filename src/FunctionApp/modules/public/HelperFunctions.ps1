function Get-ErrorType {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $Exception  # Changed from [System.Exception] to accept both ErrorRecord and Exception
    )
    
    # Handle PowerShell ErrorRecord vs .NET Exception
    $actualException = if ($Exception -is [System.Management.Automation.ErrorRecord]) {
        $Exception.Exception
    } else {
        $Exception
    }
    
    $errorType = $actualException.GetType().Name
    $errorMessage = $actualException.Message.ToLower()
    
    # Check for common HTTP errors
    if ($actualException.Message -match "(\d{3})") {
        $httpCode = $Matches[1]
        return "$errorType (HTTP $httpCode)"
    }
    
    # Check for common network errors
    if ($errorMessage -match "socket|network|connection|timeout") {
        return "$errorType (Network)"
    }
    
    # Check for authentication errors
    if ($errorMessage -match "auth|token|unauthorized|forbidden") {
        return "$errorType (Authentication)"
    }
    
    # Check for Event Hub specific errors
    if ($errorMessage -match "eventhub|servicebus") {
        return "$errorType (EventHub)"
    }
    
    return $errorType
}

function Get-HttpStatusCode {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $Exception  # Changed from [System.Exception] to accept both ErrorRecord and Exception
    )
    
    # Handle PowerShell ErrorRecord vs .NET Exception
    $actualException = if ($Exception -is [System.Management.Automation.ErrorRecord]) {
        $Exception.Exception
    } else {
        $Exception
    }
    
    # Try to extract HTTP status code from exception message
    if ($actualException.Message -match "(\d{3})") {
        return [int]$Matches[1]
    }
    
    # Check exception type for common HTTP exceptions
    if ($actualException -is [System.Net.WebException]) {
        $webException = [System.Net.WebException]$actualException
        if ($webException.Response -and $webException.Response -is [System.Net.HttpWebResponse]) {
            return [int]$webException.Response.StatusCode
        }
    }
    
    return $null
}

function Test-ShouldRetry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $Exception,  # Changed from [System.Exception] to accept both ErrorRecord and Exception
        
        [Parameter(Mandatory = $true)]
        [string]$ErrorType
    )
    
    # Handle PowerShell ErrorRecord vs .NET Exception
    $actualException = if ($Exception -is [System.Management.Automation.ErrorRecord]) {
        $Exception.Exception
    } else {
        $Exception
    }
    
    # Define retryable error types
    $retryableErrors = @(
        "RateLimit",      # 429 - Always retry with backoff
        "ServerError",    # 500 - Temporary server issues
        "BadGateway",     # 502 - Proxy/gateway issues
        "ServiceUnavailable", # 503 - Service temporarily down
        "Timeout",        # 504 - Request timeout
        "Network",        # Network connectivity issues
        "Connection",     # Connection failures
        "DNS"            # DNS resolution failures
    )
    
    # Non-retryable errors (fail fast)
    $nonRetryableErrors = @(
        "Authentication", # 401 - Need new token or permissions
        "Authorization",  # 403 - Insufficient permissions
        "TokenError",     # Token format or validation issues
        "EventHub"       # Event Hub specific errors often need configuration fixes
    )
    
    if ($ErrorType -in $nonRetryableErrors) {
        return $false
    }
    
    if ($ErrorType -in $retryableErrors) {
        return $true
    }
    
    # For Event Hub 401 errors, don't retry as it's likely a permission issue
    if ($actualException.Message -match "401.*eventhub|401.*servicebus") {
        return $false
    }
    
    # For unknown errors, default to retry (conservative approach)
    return $true
}
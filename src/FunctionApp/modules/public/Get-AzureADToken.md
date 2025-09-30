# Get-AzureADToken

## Purpose

Acquires Azure AD access tokens using User-Assigned Managed Identity for secure, credential-less authentication. This function provides the foundation for all authenticated API calls to Microsoft Graph, Event Hub, and other Azure resources.

## Key Concepts

### Managed Identity Authentication

Uses Azure's Identity endpoint to acquire tokens without storing credentials or secrets in code. This provides enterprise-grade security with automatic token lifecycle management.

### Multi-Resource Support

Supports token acquisition for different Azure services by specifying the appropriate resource identifier.

### Production-Ready Token Management

Implements robust error handling and validation for token acquisition with detailed diagnostics for troubleshooting authentication issues.

## Parameters

| Parameter    | Type   | Required | Default      | Description                                                                                    |
| ------------ | ------ | -------- | ------------ | ---------------------------------------------------------------------------------------------- |
| `resource`   | String | Yes      | -            | The resource identifier for which the token is requested (e.g., "https://graph.microsoft.com") |
| `apiVersion` | String | No       | "2019-08-01" | The Azure Identity API version to use for the request                                          |
| `clientId`   | String | Yes      | -            | The Client ID of the User-Assigned Managed Identity                                            |

## Return Value

Returns a string containing the JWT Bearer token for the specified resource.

```powershell
# Example token (truncated)
"eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6..."
```

## Supported Resources

### Microsoft Graph API

```powershell
$graphToken = Get-AzureADToken -resource "https://graph.microsoft.com" -clientId $env:CLIENTID
```

### Azure Event Hub

```powershell
$eventHubToken = Get-AzureADToken -resource "https://eventhubs.azure.net" -clientId $env:CLIENTID
```

### Azure Storage

```powershell
$storageToken = Get-AzureADToken -resource "https://storage.azure.com/" -clientId $env:CLIENTID
```

### Azure Key Vault

```powershell
$keyVaultToken = Get-AzureADToken -resource "https://vault.azure.net" -clientId $env:CLIENTID
```

## Usage Examples

### Standard Graph API Authentication

```powershell
try {
    # Acquire token for Microsoft Graph
    $token = Get-AzureADToken -resource "https://graph.microsoft.com" -clientId $env:CLIENTID

    # Create authentication headers
    $authHeaders = @{
        'Authorization' = "Bearer $token"
        'ConsistencyLevel' = 'eventual'  # Required for advanced Graph queries
    }

    # Make authenticated Graph API call
    $users = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users" -Headers $authHeaders

} catch {
    Write-Error "Authentication failed: $($_.Exception.Message)"
    throw
}
```

### Event Hub Authentication

```powershell
try {
    # Acquire token for Event Hub
    $ehToken = Get-AzureADToken -resource "https://eventhubs.azure.net" -clientId $env:CLIENTID

    # Create Event Hub headers
    $ehHeaders = @{
        'Authorization' = "Bearer $ehToken"
        'Content-Type' = 'application/json'
    }

    # Send data to Event Hub
    $eventHubUri = "https://$($env:EVENTHUBNAMESPACE).servicebus.windows.net/$($env:EVENTHUBNAME)/messages"
    Invoke-RestMethod -Uri $eventHubUri -Headers $ehHeaders -Method Post -Body $jsonPayload

} catch {
    Write-Error "Event Hub authentication failed: $($_.Exception.Message)"
    throw
}
```

### Token Validation Example

```powershell
# Validate token acquisition
$token = Get-AzureADToken -resource "https://graph.microsoft.com" -clientId $env:CLIENTID

if ([string]::IsNullOrWhiteSpace($token)) {
    throw [System.Security.Authentication.AuthenticationException]::new("Token acquisition returned empty token")
}

# Validate token format (basic JWT structure check)
if (-not ($token -match '^eyJ[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+$')) {
    Write-Warning "Token format validation failed - may not be a valid JWT"
}

Write-Host "✅ Token acquired successfully (length: $($token.Length) characters)"
```

## Error Handling

### Common Authentication Errors

#### Missing Environment Variables

```powershell
# Function validates required environment variables
if (-not $env:IDENTITY_ENDPOINT) {
    throw "IDENTITY_ENDPOINT environment variable not found - not running in Azure Functions context"
}

if (-not $env:IDENTITY_HEADER) {
    throw "IDENTITY_HEADER environment variable not found - managed identity not configured"
}
```

#### Managed Identity Configuration Issues

```powershell
# Common error patterns and diagnostics
try {
    $token = Get-AzureADToken -resource "https://graph.microsoft.com" -clientId $env:CLIENTID
} catch {
    if ($_.Exception.Message -match "400|Bad Request") {
        Write-Error "❌ MANAGED IDENTITY CONFIGURATION ERROR"
        Write-Error "1. Verify User-Assigned Managed Identity is assigned to Function App"
        Write-Error "2. Check CLIENTID environment variable matches identity Client ID"
        Write-Error "3. Ensure identity has required permissions on target resource"
    }
    elseif ($_.Exception.Message -match "404|Not Found") {
        Write-Error "❌ MANAGED IDENTITY NOT FOUND"
        Write-Error "1. Managed Identity with Client ID '$($env:CLIENTID)' does not exist"
        Write-Error "2. Check Client ID spelling and format"
        Write-Error "3. Verify identity exists in the same subscription"
    }
    elseif ($_.Exception.Message -match "403|Forbidden") {
        Write-Error "❌ INSUFFICIENT PERMISSIONS"
        Write-Error "1. Managed Identity lacks permissions for resource: $resource"
        Write-Error "2. Review and assign required API permissions"
        Write-Error "3. For Graph API: User.Read.All and Group.Read.All"
        Write-Error "4. For Event Hub: Azure Event Hubs Data Sender"
    }

    throw
}
```

## Security Considerations

### Token Security

- **No token storage**: Tokens acquired on-demand and not persisted
- **Automatic expiration**: Tokens have built-in expiration (typically 1 hour)
- **Scope limitation**: Tokens are scoped to specific resources only
- **No credential exposure**: No secrets or keys in code or configuration

### Managed Identity Benefits

- **Azure AD integration**: Native Azure security with no external dependencies
- **Automatic rotation**: Azure handles credential lifecycle
- **Audit logging**: All token acquisitions logged in Azure AD audit logs
- **Least privilege**: Assign only required permissions per resource

### Permission Requirements by Resource

#### Microsoft Graph API

```
Required Permissions:
✅ User.Read.All (Application) - Read all user profiles
✅ Group.Read.All (Application) - Read all group information
```

#### Azure Event Hub

```
Required Permissions:
✅ Azure Event Hubs Data Sender (on Event Hub Namespace)
```

## Performance Characteristics

### Token Acquisition Speed

- **Typical response time**: 100-500ms
- **Network dependency**: Requires connectivity to Azure Identity endpoint
- **Caching strategy**: Tokens can be cached for up to 50% of their lifetime
- **Rate limits**: Azure Identity service has generous limits for token requests

### Integration with Retry Logic

```powershell
# Example integration with retry mechanism
$authScriptBlock = {
    Get-AzureADToken -resource "https://graph.microsoft.com" -clientId $env:CLIENTID
}

$token = Invoke-WithRetry -ScriptBlock $authScriptBlock -MaxRetryCount 2 -OperationName "GetGraphToken"
```

## Dependencies

### Required Environment Variables

- `IDENTITY_ENDPOINT`: Provided automatically by Azure Functions runtime
- `IDENTITY_HEADER`: Provided automatically by Azure Functions runtime  
- `CLIENTID`: Must be configured in Function App application settings

### Required .NET Assemblies

```powershell
Add-Type -AssemblyName 'System.Net.Http'
Add-Type -AssemblyName 'System.Net'
Add-Type -AssemblyName 'System.Net.Primitives'
```

### Azure Resources

- **User-Assigned Managed Identity**: With appropriate permissions
- **Azure Function App**: With managed identity assignment
- **Target resources**: With permission grants to the managed identity

## 

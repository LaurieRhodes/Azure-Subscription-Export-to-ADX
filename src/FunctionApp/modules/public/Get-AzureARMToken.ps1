<#
.SYNOPSIS
    Gets an Azure Resource Manager authentication token using Managed Identity.

.DESCRIPTION
    This function acquires an access token for Azure Resource Manager API calls using the 
    Function App's Managed Identity. It handles authentication errors appropriately,
    treating 403 Forbidden as a fatal permissions error rather than a retryable failure.

.PARAMETER Resource
    The Azure resource URI to authenticate against. Defaults to ARM API.

.PARAMETER ClientId
    The client ID of the managed identity. If not provided, uses system-assigned identity.

.NOTES
    Author: Laurie Rhodes
    Version: 1.1 - ENHANCED ERROR HANDLING
    Last Modified: 2025-09-27
    
    ENHANCED: Proper handling of 403 Forbidden as fatal permission error
#>

function Get-AzureARMToken {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Resource = "https://management.azure.com",
        
        [Parameter(Mandatory = $false)]
        [string]$ClientId = $env:CLIENTID
    )

    Write-Information "Acquiring Azure Resource Manager token..."
    Write-Debug "Resource: $Resource"
    Write-Debug "Client ID: $($ClientId -replace '.', '*')"
    
    try {
        # Check if we're running in Azure Functions environment
        if (-not $env:MSI_ENDPOINT) {
            throw "Managed Identity endpoint not available. This function must run in Azure Functions with Managed Identity enabled."
        }
        
        # Construct the token request
        $tokenEndpoint = $env:MSI_ENDPOINT
        $headers = @{
            'Metadata' = 'true'
        }
        
        # Build the query parameters
        $queryParams = @{
            'api-version' = '2019-08-01'
            'resource' = $Resource
        }
        
        # Add client ID if specified (for user-assigned identity)
        if ($ClientId) {
            $queryParams['client_id'] = $ClientId
            Write-Debug "Using user-assigned managed identity"
        } else {
            Write-Debug "Using system-assigned managed identity"
        }
        
        # Construct the full URI
        $queryString = ($queryParams.GetEnumerator() | ForEach-Object { "$($_.Key)=$([System.Web.HttpUtility]::UrlEncode($_.Value))" }) -join '&'
        $uri = "$tokenEndpoint/?$queryString"
        
        Write-Debug "Token endpoint URI constructed"
        
        # Make the token request with intelligent retry logic
        $maxRetries = 3
        $retryDelay = 1
        
        for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
            try {
                Write-Debug "Token request attempt $attempt of $maxRetries"
                
                $response = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -TimeoutSec 30
                
                if ($response.access_token) {
                    Write-Information "Successfully acquired ARM token"
                    Write-Debug "Token expires: $([DateTimeOffset]::FromUnixTimeSeconds($response.expires_on).ToString('yyyy-MM-dd HH:mm:ss UTC'))"
                    return $response.access_token
                } else {
                    throw "Token response did not contain access_token"
                }
            }
            catch [System.Net.WebException] {
                $statusCode = $null
                if ($_.Exception.Response) {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                }
                
                # Handle specific HTTP status codes
                switch ($statusCode) {
                    403 {
                        # 403 Forbidden - This is a permissions/RBAC issue, not a transient error
                        $errorMessage = "RBAC Permission Error (403 Forbidden): The Managed Identity does not have sufficient permissions to access the subscription. "
                        $errorMessage += "Please ensure the User-Assigned Managed Identity has been granted at least 'Reader' role on the target subscription. "
                        $errorMessage += "Note: RBAC permission changes can take up to 24 hours to propagate in Azure."
                        
                        Write-Error $errorMessage
                        Write-Information "This is a fatal permission error - no retry will be attempted."
                        
                        # Throw a custom exception type to indicate this is a permission error
                        throw [System.UnauthorizedAccessException]::new($errorMessage)
                    }
                    
                    401 {
                        # 401 Unauthorized - Authentication configuration issue
                        $errorMessage = "Authentication Error (401 Unauthorized): The Managed Identity configuration is invalid or the identity does not exist. "
                        $errorMessage += "Please verify the User-Assigned Managed Identity is properly configured and exists."
                        
                        Write-Error $errorMessage
                        Write-Information "This is a fatal authentication configuration error - no retry will be attempted."
                        
                        throw [System.UnauthorizedAccessException]::new($errorMessage)
                    }
                    
                    404 {
                        # 404 Not Found - Resource or endpoint not found
                        $errorMessage = "Resource Error (404 Not Found): The Managed Identity endpoint or resource is not available. "
                        $errorMessage += "This may indicate a configuration issue with the Function App or Azure environment."
                        
                        Write-Error $errorMessage
                        Write-Information "This is a fatal configuration error - no retry will be attempted."
                        
                        throw [System.ArgumentException]::new($errorMessage)
                    }
                    
                    default {
                        # Other HTTP errors - may be transient, allow retry
                        Write-Warning "Token request attempt $attempt failed with HTTP $statusCode`: $($_.Exception.Message)"
                        
                        if ($attempt -eq $maxRetries) {
                            throw "Failed to acquire ARM token after $maxRetries attempts. Last error: HTTP $statusCode - $($_.Exception.Message)"
                        }
                    }
                }
            }
            catch [System.UnauthorizedAccessException] {
                # Re-throw permission errors immediately without retry
                throw
            }
            catch [System.ArgumentException] {
                # Re-throw configuration errors immediately without retry
                throw
            }
            catch {
                # Other exceptions - log and retry if not final attempt
                Write-Warning "Token request attempt $attempt failed: $($_.Exception.Message)"
                
                if ($attempt -eq $maxRetries) {
                    throw "Failed to acquire ARM token after $maxRetries attempts. Last error: $($_.Exception.Message)"
                }
            }
            
            # Only sleep if we're going to retry
            if ($attempt -lt $maxRetries) {
                Write-Debug "Waiting $retryDelay seconds before retry..."
                Start-Sleep -Seconds $retryDelay
                $retryDelay = $retryDelay * 2  # Exponential backoff
            }
        }
    }
    catch [System.UnauthorizedAccessException] {
        # Permission errors - don't wrap, just re-throw with context
        Write-Error "FATAL: $($_.Exception.Message)"
        throw
    }
    catch [System.ArgumentException] {
        # Configuration errors - don't wrap, just re-throw with context
        Write-Error "FATAL: $($_.Exception.Message)"
        throw
    }
    catch {
        $errorMessage = "ARM token acquisition failed: $($_.Exception.Message)"
        Write-Error $errorMessage
        
        # Log additional context for troubleshooting
        Write-Debug "Environment variables check:"
        Write-Debug "  MSI_ENDPOINT: $($env:MSI_ENDPOINT -replace '.', '*')"
        Write-Debug "  CLIENTID: $($env:CLIENTID -replace '.', '*')"
        Write-Debug "  WEBSITE_SITE_NAME: $($env:WEBSITE_SITE_NAME)"
        
        throw $errorMessage
    }
}
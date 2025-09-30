<#
.SYNOPSIS
    Discovers and returns current Azure API versions for all resource providers.

.DESCRIPTION
    This function queries Azure Resource Manager to get the latest API versions for all 
    resource providers in the subscription. This ensures we use the most current API 
    versions for resource queries rather than hardcoding potentially outdated versions.
    
    Based on the proven approach from the 5+ year successful backup script.

.PARAMETER AuthHeader
    Authentication header containing Bearer token for ARM API calls.

.PARAMETER SubscriptionId
    The subscription ID to query for resource providers. If not provided, uses current subscription.

.NOTES
    Author: Laurie Rhodes
    Version: 1.0
    Last Modified: 2025-01-31
    
    Returns a hashtable with ResourceProvider/ResourceType as keys and latest API version as values.
    Example: "Microsoft.Storage/storageAccounts" -> "2023-01-01"
#>

function Get-AzureAPIVersions {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$AuthHeader,
        
        [Parameter(Mandatory = $false)]
        [string]$SubscriptionId = $env:SUBSCRIPTION_ID
    )

    Write-Information "Discovering Azure API versions for subscription: $SubscriptionId"
    
    if (-not $SubscriptionId) {
        throw "SubscriptionId is required but not provided and SUBSCRIPTION_ID environment variable is not set"
    }
    
    $apiVersionDict = @{}
    
    try {
        # Query Azure ARM for all resource providers
        $uri = "https://management.azure.com/subscriptions/$SubscriptionId/providers/?api-version=2021-04-01"
        
        Write-Debug "Querying resource providers: $uri"
        
        $response = Invoke-RestMethod -Uri $uri -Method GET -Headers $AuthHeader -TimeoutSec 120
        
        if (-not $response.value) {
            throw "No resource providers returned from Azure ARM API"
        }
        
        Write-Information "Processing $($response.value.Count) resource providers"
        
        # Process each namespace and its resource types
        foreach ($namespace in $response.value) {
            $namespacePrefix = $namespace.namespace
            
            Write-Debug "Processing namespace: $namespacePrefix"
            
            if (-not $namespace.resourceTypes) {
                Write-Debug "No resource types found for namespace: $namespacePrefix"
                continue
            }
            
            foreach ($resourceType in $namespace.resourceTypes) {
                $resourceTypeName = $resourceType.resourceType
                $fullResourceType = "$namespacePrefix/$resourceTypeName"
                
                # Get the latest API version for this resource type
                if ($resourceType.apiVersions -and $resourceType.apiVersions.Count -gt 0) {
                    # API versions are typically returned in descending order (latest first)
                    # But we'll explicitly get the latest to be safe
                    $latestVersion = Get-LatestAPIVersion -ApiVersions $resourceType.apiVersions
                    
                    $apiVersionDict[$fullResourceType] = $latestVersion
                    Write-Debug "Added: $fullResourceType -> $latestVersion"
                } else {
                    Write-Warning "No API versions found for resource type: $fullResourceType"
                }
            }
        }
        
        Write-Information "API version discovery completed. Found $($apiVersionDict.Count) resource type mappings"
        
        # Log some sample mappings for verification
        $sampleMappings = $apiVersionDict.GetEnumerator() | Select-Object -First 5
        foreach ($mapping in $sampleMappings) {
            Write-Debug "Sample mapping: $($mapping.Key) -> $($mapping.Value)"
        }
        
        return $apiVersionDict
        
    }
    catch {
        $errorMessage = "Failed to discover Azure API versions: $($_.Exception.Message)"
        Write-Error $errorMessage
        
        # Provide troubleshooting information
        Write-Debug "Troubleshooting information:"
        Write-Debug "  Subscription ID: $SubscriptionId"
        Write-Debug "  Auth header keys: $($AuthHeader.Keys -join ', ')"
        
        throw $errorMessage
    }
}

# Helper function to determine the latest API version from a list
function Get-LatestAPIVersion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$ApiVersions
    )
    
    if ($ApiVersions.Count -eq 0) {
        throw "No API versions provided"
    }
    
    if ($ApiVersions.Count -eq 1) {
        return $ApiVersions[0]
    }
    
    # Sort API versions in descending order to get the latest
    # API versions follow the format YYYY-MM-DD or YYYY-MM-DD-preview
    # We want the latest stable version, falling back to preview if no stable version exists
    
    $stableVersions = $ApiVersions | Where-Object { $_ -notmatch '-preview|-beta|-alpha' }
    $previewVersions = $ApiVersions | Where-Object { $_ -match '-preview|-beta|-alpha' }
    
    # Prefer stable versions over preview versions
    if ($stableVersions.Count -gt 0) {
        $sortedVersions = $stableVersions | Sort-Object -Descending
        $latestVersion = $sortedVersions[0]
        Write-Debug "Selected latest stable version: $latestVersion from $($stableVersions.Count) stable versions"
    } else {
        $sortedVersions = $previewVersions | Sort-Object -Descending
        $latestVersion = $sortedVersions[0]
        Write-Debug "No stable versions available, selected latest preview version: $latestVersion"
    }
    
    return $latestVersion
}
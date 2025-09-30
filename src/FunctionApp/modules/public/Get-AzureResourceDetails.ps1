# Helper function to get detailed resource information with enhanced error handling
function Get-AzureResourceDetails {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceId,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$AuthHeader,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$AzAPIVersions
    )
    
    try {
        # Handle Resource Groups separately (they don't follow the provider pattern)
        if ($ResourceId -match '/subscriptions/[^/]+/resourceGroups/[^/]+$') {
            Write-Debug "Detected Resource Group: $ResourceId"
            
            # Resource Groups use a fixed API version
            $apiVersion = "2021-04-01"
            $queryUri = "https://management.azure.com$ResourceId" + "?api-version=$apiVersion"
            
            Write-Debug "Getting resource group details: $queryUri"
            
            $resource = Invoke-RestMethod -Uri $queryUri -Method GET -Headers $AuthHeader -TimeoutSec 60
            
            return $resource
        }
        
        # Extract resource type from resource ID for regular resources
        $resourceIdParts = $ResourceId.Split('/')
        $providerIndex = -1
        
        # Find the last 'providers' element in the resource ID
        for ($i = 0; $i -lt $resourceIdParts.Length; $i++) {
            if ($resourceIdParts[$i] -eq 'providers') {
                $providerIndex = $i
            }
        }
        
        if ($providerIndex -eq -1) {
            throw "Could not find provider in resource ID: $ResourceId"
        }
        
        # Construct resource type
        $resourceType = "$($resourceIdParts[$providerIndex + 1])/$($resourceIdParts[$providerIndex + 2])"
        
        # Special handling for resource types that need specific API versions
        $specialApiVersions = @{
            "Microsoft.Web/connections" = @("2016-06-01", "2018-07-01-preview", "2015-08-01-preview")
            "Microsoft.Logic/workflows" = @("2019-05-01", "2016-06-01")
            "Microsoft.SecurityInsights/alertRules" = @("2023-02-01-preview", "2022-11-01-preview", "2021-10-01-preview")
            "Microsoft.SecurityInsights/dataConnectors" = @("2023-02-01-preview", "2022-11-01-preview", "2021-10-01-preview")
            "Microsoft.SecurityInsights/automationRules" = @("2023-02-01-preview", "2022-11-01-preview")
            "Microsoft.OperationalInsights/queryPacks" = @("2019-09-01", "2019-09-01-preview")
        }
        
        if ($specialApiVersions.ContainsKey($resourceType)) {
            Write-Debug "Using special API version handling for $resourceType"
            
            foreach ($testVersion in $specialApiVersions[$resourceType]) {
                try {
                    $queryUri = "https://management.azure.com$ResourceId" + "?api-version=$testVersion"
                    Write-Debug "Testing API version $testVersion for $resourceType : $queryUri"
                    
                    $resource = Invoke-RestMethod -Uri $queryUri -Method GET -Headers $AuthHeader -TimeoutSec 60
                    
                    Write-Debug "SUCCESS: API version $testVersion worked for $resourceType"
                    return $resource
                }
                catch {
                    Write-Debug "FAILED: API version $testVersion failed for $resourceType : $($_.Exception.Message)"
                    continue
                }
            }
            
            # If all special versions failed, try the standard lookup
            Write-Warning "All special API versions failed for $resourceType, trying standard lookup"
        }
        
        # Get API version for this resource type from the standard lookup
        if ($AzAPIVersions.ContainsKey($resourceType)) {
            $apiVersion = $AzAPIVersions[$resourceType]
        } else {
            # Fallback to a common API version
            $apiVersion = "2021-04-01"
            Write-Warning "No specific API version found for $resourceType, using fallback: $apiVersion"
        }
        
        # Construct query URI
        $queryUri = "https://management.azure.com$ResourceId" + "?api-version=$apiVersion"
        
        Write-Debug "Getting resource details: $queryUri"
        
        $resource = Invoke-RestMethod -Uri $queryUri -Method GET -Headers $AuthHeader -TimeoutSec 60
        
        return $resource
        
    }
    catch {
        # Enhanced error reporting for troubleshooting
        $errorDetails = @{
            ResourceId = $ResourceId
            ResourceType = if ($resourceType) { $resourceType } else { "Unknown" }
            ApiVersion = if ($apiVersion) { $apiVersion } else { "Unknown" }
            QueryUri = if ($queryUri) { $queryUri } else { "Unknown" }
            ErrorMessage = $_.Exception.Message
            StatusCode = if ($_.Exception.Response) { $_.Exception.Response.StatusCode } else { "Unknown" }
        }
        
        Write-Warning "Failed to get details for resource $ResourceId"
        Write-Warning "  Resource Type: $($errorDetails.ResourceType)"
        Write-Warning "  API Version: $($errorDetails.ApiVersion)" 
        Write-Warning "  Query URI: $($errorDetails.QueryUri)"
        Write-Warning "  Error: $($errorDetails.ErrorMessage)"
        Write-Warning "  Status Code: $($errorDetails.StatusCode)"
        
        return $null
    }
}
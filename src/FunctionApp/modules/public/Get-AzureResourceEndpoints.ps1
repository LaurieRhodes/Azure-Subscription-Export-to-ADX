<#
.SYNOPSIS
    Generates Azure Resource Manager API query endpoints based on export configuration.

.DESCRIPTION
    This function creates the appropriate REST API endpoints for querying Azure resources
    based on the export configuration settings. It supports both subscription-wide and
    resource group-scoped queries.
    
    Based on the proven endpoint generation logic from the 5+ year successful backup script.

.PARAMETER SubscriptionId
    The Azure subscription ID to query.

.PARAMETER ExportConfiguration
    Hashtable specifying which types of objects to export.

.PARAMETER ResourceGroupFilter
    Optional array of resource group names to limit export scope.

.NOTES
    Author: Laurie Rhodes
    Version: 1.0
    Last Modified: 2025-01-31
#>

function Get-AzureResourceEndpoints {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$ExportConfiguration,
        
        [Parameter(Mandatory = $false)]
        [string[]]$ResourceGroupFilter = @()
    )

    Write-Information "Generating Azure resource query endpoints"
    Write-Debug "Subscription ID: $SubscriptionId"
    Write-Debug "Export Configuration: $($ExportConfiguration | ConvertTo-Json -Compress)"
    Write-Debug "Resource Group Filter: $($ResourceGroupFilter -join ', ')"
    
    $endpoints = @()
    
    try {
        # If ResourceGroupFilter is specified, scope queries to those resource groups
        if ($ResourceGroupFilter.Count -gt 0) {
            Write-Information "Generating resource group scoped endpoints for $($ResourceGroupFilter.Count) resource groups"
            
            foreach ($resourceGroup in $ResourceGroupFilter) {
                if ($ExportConfiguration.SubscriptionObjects) {
                    $rgEndpoint = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$resourceGroup/resources?api-version=2021-04-01"
                    $endpoints += $rgEndpoint
                    Write-Debug "Added RG scoped endpoint: $rgEndpoint"
                }
            }
        } else {
            Write-Information "Generating subscription-wide endpoints"
            
            # Subscription-wide resource queries
            if ($ExportConfiguration.SubscriptionObjects) {
                $subscriptionEndpoint = "https://management.azure.com/subscriptions/$SubscriptionId/resources?api-version=2021-04-01"
                $endpoints += $subscriptionEndpoint
                Write-Debug "Added subscription resources endpoint: $subscriptionEndpoint"
            }
        }
        
        # Authorization-related endpoints (always subscription-scoped)
        if ($ExportConfiguration.RoleDefinitions) {
            $roleDefEndpoint = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-05-01-preview"
            $endpoints += $roleDefEndpoint
            Write-Debug "Added role definitions endpoint: $roleDefEndpoint"
        }
        
        if ($ExportConfiguration.RoleAssignments) {
            $roleAssignEndpoint = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01"
            $endpoints += $roleAssignEndpoint
            Write-Debug "Added role assignments endpoint: $roleAssignEndpoint"
        }
        
        # Policy-related endpoints
        if ($ExportConfiguration.PolicyDefinitions) {
            $policyDefEndpoint = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/policyDefinitions?api-version=2021-06-01"
            $endpoints += $policyDefEndpoint
            Write-Debug "Added policy definitions endpoint: $policyDefEndpoint"
        }
        
        if ($ExportConfiguration.PolicySetDefinitions) {
            $policySetDefEndpoint = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/policySetDefinitions?api-version=2021-06-01"
            $endpoints += $policySetDefEndpoint
            Write-Debug "Added policy set definitions endpoint: $policySetDefEndpoint"
        }
        
        if ($ExportConfiguration.PolicyAssignments) {
            $policyAssignEndpoint = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/policyAssignments?api-version=2022-06-01"
            $endpoints += $policyAssignEndpoint
            Write-Debug "Added policy assignments endpoint: $policyAssignEndpoint"
        }
        
        if ($ExportConfiguration.PolicyExemptions) {
            $policyExemptEndpoint = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/policyExemptions?api-version=2022-07-01-preview"
            $endpoints += $policyExemptEndpoint
            Write-Debug "Added policy exemptions endpoint: $policyExemptEndpoint"
        }
        
        # Security Center endpoints
        if ($ExportConfiguration.SecurityCenterSubscriptions) {
            $securityCenterEndpoint = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.Security/pricings?api-version=2022-03-01"
            $endpoints += $securityCenterEndpoint
            Write-Debug "Added Security Center subscriptions endpoint: $securityCenterEndpoint"
        }
        
        # Resource Group details endpoint (if not already filtered)
        if ($ExportConfiguration.ResourceGroupDetails -and $ResourceGroupFilter.Count -eq 0) {
            $rgDetailsEndpoint = "https://management.azure.com/subscriptions/$SubscriptionId/resourcegroups?api-version=2021-04-01"
            $endpoints += $rgDetailsEndpoint
            Write-Debug "Added resource group details endpoint: $rgDetailsEndpoint"
        } elseif ($ExportConfiguration.ResourceGroupDetails -and $ResourceGroupFilter.Count -gt 0) {
            # Add specific resource group detail endpoints
            foreach ($resourceGroup in $ResourceGroupFilter) {
                $rgDetailEndpoint = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$resourceGroup?api-version=2021-04-01"
                $endpoints += $rgDetailEndpoint
                Write-Debug "Added specific RG details endpoint: $rgDetailEndpoint"
            }
        }
        
        Write-Information "Generated $($endpoints.Count) query endpoints"
        
        # Log endpoint summary for debugging
        $endpointSummary = @{}
        foreach ($endpoint in $endpoints) {
            $apiCall = ($endpoint -split '\?')[0] -replace "https://management.azure.com/subscriptions/$SubscriptionId/", ""
            if ($endpointSummary.ContainsKey($apiCall)) {
                $endpointSummary[$apiCall]++
            } else {
                $endpointSummary[$apiCall] = 1
            }
        }
        
        Write-Debug "Endpoint summary:"
        $endpointSummary.GetEnumerator() | ForEach-Object {
            Write-Debug "  $($_.Key): $($_.Value) endpoint(s)"
        }
        
        return $endpoints
        
    }
    catch {
        $errorMessage = "Failed to generate Azure resource endpoints: $($_.Exception.Message)"
        Write-Error $errorMessage
        throw $errorMessage
    }
}
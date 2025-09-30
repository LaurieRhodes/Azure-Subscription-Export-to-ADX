<#
.SYNOPSIS
    Exports Azure resource groups to Event Hub for ADX ingestion.

.DESCRIPTION
    This function discovers and exports Azure resource group details and metadata.
    It provides comprehensive resource group information including tags, location,
    and properties.

.PARAMETER AuthHeader
    Authentication header containing Bearer token for ARM API calls.

.PARAMETER CorrelationContext
    Correlation context for tracking and telemetry.

.PARAMETER ResourceGroupFilter
    Optional array of resource group names to limit export scope.

.PARAMETER AzAPIVersions
    Hashtable of resource type to API version mappings.

.NOTES
    Author: Laurie Rhodes
    Version: 1.1 - FIXED EVENT HUB PARAMETER
    Last Modified: 2025-09-27
    
    FIXED: Corrected Send-EventsToEventHub parameter from -Events to -Payload
#>

function Export-AzureResourceGroups {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$AuthHeader,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$CorrelationContext,
        
        [Parameter(Mandatory = $false)]
        [string[]]$ResourceGroupFilter = @(),
        
        [Parameter(Mandatory = $true)]
        [hashtable]$AzAPIVersions
    )

    $exportStartTime = Get-Date
    $subscriptionId = $env:SUBSCRIPTION_ID
    
    # Initialize metrics
    $metrics = @{
        ResourceGroupCount = 0
        BatchCount = 0
        FailedResourceGroups = 0
    }
    
    Write-Information "Starting Azure resource groups export"
    Write-Information "Subscription ID: $subscriptionId"
    Write-Information "Resource Group Filter: $($ResourceGroupFilter -join ', ')"
    
    try {
        # Step 1: Get resource groups
        $resourceGroups = @()
        
        if ($ResourceGroupFilter.Count -gt 0) {
            # Get specific resource groups
            Write-Information "Fetching $($ResourceGroupFilter.Count) specific resource groups"
            
            foreach ($rgName in $ResourceGroupFilter) {
                try {
                    $queryUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$rgName" + "?api-version=2021-04-01"
                    $resourceGroup = Invoke-RestMethod -Uri $queryUri -Method GET -Headers $AuthHeader -TimeoutSec 60
                    $resourceGroups += $resourceGroup
                    Write-Debug "Retrieved resource group: $rgName"
                }
                catch {
                    Write-Warning "Failed to retrieve resource group $rgName : $($_.Exception.Message)"
                    $metrics.FailedResourceGroups++
                }
            }
        } else {
            # Get all resource groups in subscription
            Write-Information "Fetching all resource groups in subscription"
            
            $queryUri = "https://management.azure.com/subscriptions/$subscriptionId/resourcegroups?api-version=2021-04-01"
            $response = Invoke-RestMethod -Uri $queryUri -Method GET -Headers $AuthHeader -TimeoutSec 120
            $resourceGroups = $response.value
        }
        
        Write-Information "Discovered $($resourceGroups.Count) resource groups"
        
        if ($resourceGroups.Count -eq 0) {
            Write-Warning "No resource groups found to export"
            return @{
                Success = $true
                ResourceGroupCount = 0
                BatchCount = 0
                DurationMs = ((Get-Date) - $exportStartTime).TotalMilliseconds
            }
        }
        
        # Step 2: Process and export resource groups in batches
        $batchSize = 25
        $processedResourceGroups = @()
        
        for ($i = 0; $i -lt $resourceGroups.Count; $i += $batchSize) {
            $batchEndIndex = [Math]::Min($i + $batchSize - 1, $resourceGroups.Count - 1)
            $batch = $resourceGroups[$i..$batchEndIndex]
            
            Write-Debug "Processing resource group batch $($i / $batchSize + 1): resource groups $($i + 1) to $($batchEndIndex + 1)"
            
            $batchEvents = @()
            
            foreach ($resourceGroup in $batch) {
                try {
                    # Clean the resource group object
                    $cleanedResourceGroup = Clean-ResourceGroupObject -ResourceGroup $resourceGroup
                    
                    # Create event for Event Hub
                    $event = @{
                        OdataContext = "resource-groups"
                        ResourceGroupName = $resourceGroup.name
                        Location = $resourceGroup.location
                        SubscriptionId = $subscriptionId
                        ExportId = $CorrelationContext.OperationId
                        Timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                        Data = $cleanedResourceGroup
                    }
                    
                    $batchEvents += $event
                    $processedResourceGroups += $cleanedResourceGroup
                    $metrics.ResourceGroupCount++
                }
                catch {
                    Write-Warning "Failed to process resource group $($resourceGroup.name): $($_.Exception.Message)"
                    $metrics.FailedResourceGroups++
                }
            }
            
            # Send batch to Event Hub if we have events
            if ($batchEvents.Count -gt 0) {
                try {
                    # FIXED: Convert events array to JSON payload for Send-EventsToEventHub
                    $jsonPayload = ConvertTo-Json -InputObject $batchEvents -Depth 50
                    $eventHubResult = Send-EventsToEventHub -Payload $jsonPayload
                    
                    if ($eventHubResult.Success) {
                        $metrics.BatchCount++
                        Write-Debug "Successfully sent resource group batch $($metrics.BatchCount) with $($batchEvents.Count) events to Event Hub"
                    } else {
                        Write-Warning "Failed to send resource group batch to Event Hub: $($eventHubResult.ErrorMessage)"
                    }
                }
                catch {
                    Write-Warning "Exception sending resource group batch to Event Hub: $($_.Exception.Message)"
                }
            }
            
            # Progress reporting
            Write-ExportProgress -Current ($batchEndIndex + 1) -Total $resourceGroups.Count -OperationType "Resource Groups"
        }
        
        # Step 3: Log completion statistics
        $exportDuration = (Get-Date) - $exportStartTime
        
        Write-Information "Resource groups export completed successfully"
        Write-Information "  Resource groups processed: $($metrics.ResourceGroupCount)"
        Write-Information "  Batches sent: $($metrics.BatchCount)"
        Write-Information "  Failed resource groups: $($metrics.FailedResourceGroups)"
        Write-Information "  Duration: $($exportDuration.ToString('hh\:mm\:ss'))"
        
        return @{
            Success = $true
            ResourceGroupCount = $metrics.ResourceGroupCount
            BatchCount = $metrics.BatchCount
            DurationMs = $exportDuration.TotalMilliseconds
            ProcessedResourceGroups = $processedResourceGroups
            FailedResourceGroups = $metrics.FailedResourceGroups
        }
        
    }
    catch {
        $exportDuration = (Get-Date) - $exportStartTime
        $errorMessage = $_.Exception.Message
        
        Write-Error "Resource groups export failed: $errorMessage"
        
        return @{
            Success = $false
            ResourceGroupCount = $metrics.ResourceGroupCount
            BatchCount = $metrics.BatchCount
            DurationMs = $exportDuration.TotalMilliseconds
            Error = @{
                ErrorMessage = $errorMessage
                ErrorType = Get-ErrorType -Exception $_
                PartialMetrics = $metrics
            }
        }
    }
}

# Helper function to clean resource group objects
function Clean-ResourceGroupObject {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ResourceGroup
    )
    
    try {
        # Clone the object to avoid modifying the original
        $cleanedResourceGroup = $ResourceGroup | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        
        # Remove common read-only properties for resource groups
        if ($cleanedResourceGroup.properties) {
            Remove-PropertySafely -Object $cleanedResourceGroup.properties -PropertyName 'provisioningState'
        }
        
        # Resource groups typically don't have many read-only properties to clean
        # But we ensure consistency with the cleaning pattern
        
        Write-Debug "Cleaned resource group: $($cleanedResourceGroup.name)"
        
        return $cleanedResourceGroup
        
    }
    catch {
        Write-Warning "Failed to clean resource group object: $($_.Exception.Message)"
        return $ResourceGroup
    }
}
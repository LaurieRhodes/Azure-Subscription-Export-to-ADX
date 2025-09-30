<#
.SYNOPSIS
    Exports Azure child resources to Event Hub for ADX ingestion.

.DESCRIPTION
    This function discovers and exports child resources for Azure resources that have
    nested or dependent resources. Examples include Event Hub namespaces containing
    event hubs, storage accounts containing containers, etc.
    
    Based on the proven child resource discovery logic from the backup script.

.PARAMETER AuthHeader
    Authentication header containing Bearer token for ARM API calls.

.PARAMETER ParentResources
    Array of parent resource objects to discover child resources for.

.PARAMETER CorrelationContext
    Correlation context for tracking and telemetry.

.PARAMETER AzAPIVersions
    Hashtable of resource type to API version mappings.

.NOTES
    Author: Laurie Rhodes
    Version: 1.1 - Fixed Event Hub parameter
    Last Modified: 2025-09-28
    
    FIXED: Corrected Send-EventsToEventHub parameter from -Events to -Payload
#>

function Export-AzureChildResources {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$AuthHeader,
        
        [Parameter(Mandatory = $true)]
        [array]$ParentResources,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$CorrelationContext,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$AzAPIVersions
    )

    $exportStartTime = Get-Date
    
    # Initialize metrics
    $metrics = @{
        ChildResourceCount = 0
        BatchCount = 0
        ProcessedParents = 0
        FailedParents = 0
        ResourceTypeBreakdown = @{}
    }
    
    Write-Information "Starting Azure child resources export"
    Write-Information "Parent resources to process: $($ParentResources.Count)"
    
    try {
        $allChildResources = @()
        
        foreach ($parentResource in $ParentResources) {
            try {
                $metrics.ProcessedParents++
                
                Write-Debug "Processing parent resource: $($parentResource.type) - $($parentResource.id)"
                
                # Get child resources based on parent resource type
                $childResources = Get-ChildResourcesByType -ParentResource $parentResource -AuthHeader $AuthHeader -AzAPIVersions $AzAPIVersions
                
                if ($childResources.Count -gt 0) {
                    Write-Debug "Found $($childResources.Count) child resources for $($parentResource.type)"
                    $allChildResources += $childResources
                }
                
                # Progress reporting every 50 parent resources
                if ($metrics.ProcessedParents % 50 -eq 0) {
                    Write-ExportProgress -Current $metrics.ProcessedParents -Total $ParentResources.Count -OperationType "Parent Resources (Child Discovery)"
                }
            }
            catch {
                Write-Warning "Failed to process parent resource $($parentResource.id): $($_.Exception.Message)"
                $metrics.FailedParents++
            }
        }
        
        Write-Information "Discovered $($allChildResources.Count) total child resources"
        
        if ($allChildResources.Count -eq 0) {
            Write-Information "No child resources found to export"
            return @{
                Success = $true
                ChildResourceCount = 0
                BatchCount = 0
                DurationMs = ((Get-Date) - $exportStartTime).TotalMilliseconds
            }
        }
        
        # Step 2: Process and export child resources in batches
        $batchSize = 30
        
        for ($i = 0; $i -lt $allChildResources.Count; $i += $batchSize) {
            $batchEndIndex = [Math]::Min($i + $batchSize - 1, $allChildResources.Count - 1)
            $batch = $allChildResources[$i..$batchEndIndex]
            
            Write-Debug "Processing child resource batch $($i / $batchSize + 1): resources $($i + 1) to $($batchEndIndex + 1)"
            
            $batchEvents = @()
            
            foreach ($childResource in $batch) {
                try {
                    # Clean the child resource object
                    $cleanedChildResource = Clean-AzureResourceObject -AzureObject $childResource -AuthHeader $AuthHeader -CorrelationContext $CorrelationContext
                    
                    # Create event for Event Hub
                    $event = @{
                        OdataContext = "child-resources"
                        ResourceType = $childResource.type
                        ParentResourceId = $childResource.parentResourceId
                        SubscriptionId = $env:SUBSCRIPTION_ID
                        ExportId = $CorrelationContext.OperationId
                        Timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                        Data = $cleanedChildResource
                    }
                    
                    $batchEvents += $event
                    
                    # Track resource types
                    if ($metrics.ResourceTypeBreakdown.ContainsKey($childResource.type)) {
                        $metrics.ResourceTypeBreakdown[$childResource.type]++
                    } else {
                        $metrics.ResourceTypeBreakdown[$childResource.type] = 1
                    }
                    
                    $metrics.ChildResourceCount++
                }
                catch {
                    Write-Warning "Failed to process child resource $($childResource.id): $($_.Exception.Message)"
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
                        Write-Debug "Successfully sent child resource batch $($metrics.BatchCount) with $($batchEvents.Count) events to Event Hub"
                    } else {
                        Write-Warning "Failed to send child resource batch to Event Hub"
                        
                        # Log details about failed chunks if available
                        if ($eventHubResult.FailedChunks -and $eventHubResult.FailedChunks.Count -gt 0) {
                            foreach ($failedChunk in $eventHubResult.FailedChunks) {
                                Write-Warning "  Failed chunk: $($failedChunk.Error) (Size: $($failedChunk.SizeKB) KB)"
                            }
                        }
                    }
                }
                catch {
                    Write-Warning "Exception sending child resource batch to Event Hub: $($_.Exception.Message)"
                }
            }
        }
        
        # Step 3: Log completion statistics
        $exportDuration = (Get-Date) - $exportStartTime
        
        Write-Information "Child resources export completed successfully"
        Write-Information "  Child resources processed: $($metrics.ChildResourceCount)"
        Write-Information "  Parent resources processed: $($metrics.ProcessedParents)"
        Write-Information "  Failed parent resources: $($metrics.FailedParents)"
        Write-Information "  Batches sent: $($metrics.BatchCount)"
        Write-Information "  Duration: $($exportDuration.ToString('hh\:mm\:ss'))"
        
        # Log child resource type breakdown
        Write-Information "Child resource type breakdown:"
        $metrics.ResourceTypeBreakdown.GetEnumerator() | 
            Sort-Object Value -Descending | 
            Select-Object -First 10 | 
            ForEach-Object { Write-Information "  $($_.Key): $($_.Value)" }
        
        return @{
            Success = $true
            ChildResourceCount = $metrics.ChildResourceCount
            BatchCount = $metrics.BatchCount
            DurationMs = $exportDuration.TotalMilliseconds
            ProcessedParents = $metrics.ProcessedParents
            FailedParents = $metrics.FailedParents
            ResourceTypeBreakdown = $metrics.ResourceTypeBreakdown
        }
        
    }
    catch {
        $exportDuration = (Get-Date) - $exportStartTime
        $errorMessage = $_.Exception.Message
        
        Write-Error "Child resources export failed: $errorMessage"
        
        return @{
            Success = $false
            ChildResourceCount = $metrics.ChildResourceCount
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

# Helper function to get child resources based on parent resource type
function Get-ChildResourcesByType {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ParentResource,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$AuthHeader,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$AzAPIVersions
    )
    
    $childResources = @()
    
    try {
        switch ($ParentResource.type) {
            "Microsoft.EventHub/namespaces" {
                # Get Event Hubs in the namespace
                $childEndpoints = @(
                    "/eventhubs",
                    "/consumergroups"
                )
                
                foreach ($endpoint in $childEndpoints) {
                    $apiVersion = Get-APIVersionForResource -ResourceType "Microsoft.EventHub/namespaces$endpoint" -AzAPIVersions $AzAPIVersions -FallbackVersion "2024-01-01"
                    $queryUri = "https://management.azure.com$($ParentResource.id)$endpoint" + "?api-version=$apiVersion"
                    
                    try {
                        $response = Invoke-RestMethod -Uri $queryUri -Method GET -Headers $AuthHeader -TimeoutSec 60
                        if ($response.value) {
                            foreach ($child in $response.value) {
                                $child | Add-Member -NotePropertyName "parentResourceId" -NotePropertyValue $ParentResource.id
                                $childResources += $child
                            }
                        }
                    }
                    catch {
                        Write-Debug "Failed to get $endpoint for $($ParentResource.id): $($_.Exception.Message)"
                    }
                }
            }
            
            "Microsoft.Kusto/clusters" {
                # Get databases and data connections
                $childEndpoints = @(
                    "/databases"
                )
                
                foreach ($endpoint in $childEndpoints) {
                    $apiVersion = Get-APIVersionForResource -ResourceType "Microsoft.Kusto/clusters$endpoint" -AzAPIVersions $AzAPIVersions -FallbackVersion "2023-08-15"
                    $queryUri = "https://management.azure.com$($ParentResource.id)$endpoint" + "?api-version=$apiVersion"
                    
                    try {
                        $response = Invoke-RestMethod -Uri $queryUri -Method GET -Headers $AuthHeader -TimeoutSec 60
                        if ($response.value) {
                            foreach ($child in $response.value) {
                                $child | Add-Member -NotePropertyName "parentResourceId" -NotePropertyValue $ParentResource.id
                                $childResources += $child
                                
                                # Get data connections for each database
                                if ($child.type -eq "Microsoft.Kusto/clusters/databases") {
                                    $dcApiVersion = Get-APIVersionForResource -ResourceType "Microsoft.Kusto/clusters/databases/dataConnections" -AzAPIVersions $AzAPIVersions -FallbackVersion "2023-08-15"
                                    $dcQueryUri = "https://management.azure.com$($child.id)/dataConnections" + "?api-version=$dcApiVersion"
                                    
                                    try {
                                        $dcResponse = Invoke-RestMethod -Uri $dcQueryUri -Method GET -Headers $AuthHeader -TimeoutSec 60
                                        if ($dcResponse.value) {
                                            foreach ($dataConnection in $dcResponse.value) {
                                                $dataConnection | Add-Member -NotePropertyName "parentResourceId" -NotePropertyValue $child.id
                                                $childResources += $dataConnection
                                            }
                                        }
                                    }
                                    catch {
                                        Write-Debug "Failed to get data connections for $($child.id): $($_.Exception.Message)"
                                    }
                                }
                            }
                        }
                    }
                    catch {
                        Write-Debug "Failed to get $endpoint for $($ParentResource.id): $($_.Exception.Message)"
                    }
                }
            }
            
            "Microsoft.Storage/storageAccounts" {
                # Get blob, file, queue, and table services
                $serviceEndpoints = @(
                    "/blobServices/default",
                    "/fileServices/default",
                    "/queueServices/default",
                    "/tableServices/default"
                )
                
                foreach ($endpoint in $serviceEndpoints) {
                    $apiVersion = Get-APIVersionForResource -ResourceType "Microsoft.Storage/storageAccounts$endpoint" -AzAPIVersions $AzAPIVersions -FallbackVersion "2023-01-01"
                    $queryUri = "https://management.azure.com$($ParentResource.id)$endpoint" + "?api-version=$apiVersion"
                    
                    try {
                        $response = Invoke-RestMethod -Uri $queryUri -Method GET -Headers $AuthHeader -TimeoutSec 60
                        if ($response) {
                            $response | Add-Member -NotePropertyName "parentResourceId" -NotePropertyValue $ParentResource.id
                            $childResources += $response
                        }
                    }
                    catch {
                        Write-Debug "Failed to get $endpoint for $($ParentResource.id): $($_.Exception.Message)"
                    }
                }
            }
            
            "Microsoft.Network/virtualNetworks" {
                # Get subnets and peerings
                $childEndpoints = @(
                    "/subnets",
                    "/virtualNetworkPeerings"
                )
                
                foreach ($endpoint in $childEndpoints) {
                    $apiVersion = Get-APIVersionForResource -ResourceType "Microsoft.Network/virtualNetworks$endpoint" -AzAPIVersions $AzAPIVersions -FallbackVersion "2023-11-01"
                    $queryUri = "https://management.azure.com$($ParentResource.id)$endpoint" + "?api-version=$apiVersion"
                    
                    try {
                        $response = Invoke-RestMethod -Uri $queryUri -Method GET -Headers $AuthHeader -TimeoutSec 60
                        if ($response.value) {
                            foreach ($child in $response.value) {
                                $child | Add-Member -NotePropertyName "parentResourceId" -NotePropertyValue $ParentResource.id
                                $childResources += $child
                            }
                        }
                    }
                    catch {
                        Write-Debug "Failed to get $endpoint for $($ParentResource.id): $($_.Exception.Message)"
                    }
                }
            }
            
            "Microsoft.OperationalInsights/workspaces" {
                # Get saved searches and other workspace children
                $childEndpoints = @(
                    "/savedSearches"
                )
                
                foreach ($endpoint in $childEndpoints) {
                    $apiVersion = Get-APIVersionForResource -ResourceType "Microsoft.OperationalInsights/workspaces$endpoint" -AzAPIVersions $AzAPIVersions -FallbackVersion "2020-08-01"
                    $queryUri = "https://management.azure.com$($ParentResource.id)$endpoint" + "?api-version=$apiVersion"
                    
                    try {
                        $response = Invoke-RestMethod -Uri $queryUri -Method GET -Headers $AuthHeader -TimeoutSec 60
                        if ($response.value) {
                            foreach ($child in $response.value) {
                                $child | Add-Member -NotePropertyName "parentResourceId" -NotePropertyValue $ParentResource.id
                                $childResources += $child
                            }
                        }
                    }
                    catch {
                        Write-Debug "Failed to get $endpoint for $($ParentResource.id): $($_.Exception.Message)"
                    }
                }
            }
            
            default {
                # No specific child resource handling for this resource type
                Write-Debug "No child resource handling defined for resource type: $($ParentResource.type)"
            }
        }
        
        return $childResources
        
    }
    catch {
        Write-Warning "Failed to get child resources for $($ParentResource.id): $($_.Exception.Message)"
        return @()
    }
}

# Helper function to get API version for a resource type
function Get-APIVersionForResource {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceType,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$AzAPIVersions,
        
        [Parameter(Mandatory = $true)]
        [string]$FallbackVersion
    )
    
    if ($AzAPIVersions.ContainsKey($ResourceType)) {
        return $AzAPIVersions[$ResourceType]
    } else {
        Write-Debug "No API version found for $ResourceType, using fallback: $FallbackVersion"
        return $FallbackVersion
    }
}
<#
.SYNOPSIS
    Exports Azure subscription resources to Event Hub for ADX ingestion.

.DESCRIPTION
    This function discovers and exports Azure subscription resources based on the provided
    configuration. It handles pagination, batching, and intelligent object cleaning.
    
    Based on the proven discovery logic from the 5+ year successful backup script,
    modernized for Event Hub streaming to ADX.

.PARAMETER AuthHeader
    Authentication header containing Bearer token for ARM API calls.

.PARAMETER CorrelationContext
    Correlation context for tracking and telemetry.

.PARAMETER ExportConfiguration
    Hashtable specifying which types of objects to export.

.PARAMETER ResourceGroupFilter
    Optional array of resource group names to limit export scope.

.PARAMETER AzAPIVersions
    Hashtable of resource type to API version mappings.

.NOTES
    Author: Laurie Rhodes
    Version: 1.6 - Payload-based batching for optimal Event Hub utilization
    Last Modified: 2025-09-28
    
    OPTIMIZED: Changed from event-count batching to payload-size batching for efficiency
#>

function Export-AzureSubscriptionResources {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$AuthHeader,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$CorrelationContext,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$ExportConfiguration,
        
        [Parameter(Mandatory = $false)]
        [string[]]$ResourceGroupFilter = @(),
        
        [Parameter(Mandatory = $true)]
        [hashtable]$AzAPIVersions
    )

    $exportStartTime = Get-Date
    $subscriptionId = $env:SUBSCRIPTION_ID
    
    # Initialize metrics
    $metrics = @{
        ResourceCount = 0
        BatchCount = 0
        ProcessedResourceTypes = @{}
        FailedResources = 0
        OversizedResources = @()
        LargeResources = @()
        TotalPayloadKB = 0
        AverageResourceSizeKB = 0
    }
    
    Write-Information "Starting Azure subscription resources export (Payload-based batching for Basic SKU)"
    Write-Information "Subscription ID: $subscriptionId"
    Write-Information "Resource Group Filter: $($ResourceGroupFilter -join ', ')"
    
    try {
        # Step 1: Get resource query endpoints based on configuration
        $queryEndpoints = Get-AzureResourceEndpoints -SubscriptionId $subscriptionId -ExportConfiguration $ExportConfiguration -ResourceGroupFilter $ResourceGroupFilter
        
        Write-Information "Generated $($queryEndpoints.Count) query endpoints"
        
        # Step 2: Collect all subscription resources
        $allResources = @()
        
        foreach ($queryUri in $queryEndpoints) {
            Write-Debug "Querying endpoint: $queryUri"
            
            try {
                # Get resources with pagination support
                $resources = Get-PaginatedAzureResources -QueryUri $queryUri -AuthHeader $AuthHeader
                $allResources += $resources
                
                Write-Debug "Retrieved $($resources.Count) resources from endpoint"
            }
            catch {
                Write-Warning "Failed to query endpoint $queryUri : $($_.Exception.Message)"
                $metrics.FailedResources++
            }
        }
        
        Write-Information "Discovered $($allResources.Count) total resources"
        
        if ($allResources.Count -eq 0) {
            Write-Warning "No resources found to export"
            return @{
                Success = $true
                ResourceCount = 0
                BatchCount = 0
                DurationMs = ((Get-Date) - $exportStartTime).TotalMilliseconds
                AllResources = @()
            }
        }
        
        # Step 3: Process and export resources with payload-based batching
        $targetBatchSizeKB = 220    # Target 220KB per batch (under 256KB Basic SKU limit)
        $maxBatchSizeKB = 230       # Hard limit before forcing batch send
        $minBatchSizeKB = 50        # Minimum batch size before adding more events
        $processedResources = @()
        
        $currentBatch = @()
        $currentBatchSizeKB = 0
        
        Write-Information "Using payload-based batching: Target $targetBatchSizeKB KB, Max $maxBatchSizeKB KB per batch"
        
        for ($i = 0; $i -lt $allResources.Count; $i++) {
            $resource = $allResources[$i]
            
            Write-Debug "Processing resource $($i + 1) of $($allResources.Count): $($resource.id)"
            
            try {
                # Get detailed resource information using the improved function
                $detailedResource = Get-AzureResourceDetails -ResourceId $resource.id -AuthHeader $AuthHeader -AzAPIVersions $AzAPIVersions
                
                if ($detailedResource) {
                    # Clean the resource object
                    $cleanedResource = Clean-AzureResourceObject -AzureObject $detailedResource -AuthHeader $AuthHeader -CorrelationContext $CorrelationContext
                    
                    # Create event for Event Hub
                    $event = @{
                        OdataContext = "subscription-resources"
                        ResourceType = $resource.type
                        ResourceGroup = $resource.resourceGroup
                        SubscriptionId = $subscriptionId
                        ExportId = $CorrelationContext.OperationId
                        Timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                        Data = $cleanedResource
                    }
                    
                    # Calculate event size
                    $eventJson = ConvertTo-Json -InputObject $event -Depth 50
                    $eventSizeKB = [Math]::Round([System.Text.Encoding]::UTF8.GetByteCount($eventJson)/1024, 2)
                    
                    # Track metrics
                    $metrics.TotalPayloadKB += $eventSizeKB
                    
                    # Track large resources for monitoring
                    if ($eventSizeKB -gt 80) {
                        $metrics.LargeResources += @{
                            ResourceId = $resource.id
                            ResourceType = $resource.type
                            SizeKB = $eventSizeKB
                        }
                        Write-Information "Large resource detected: $($resource.type) - $($resource.id) ($eventSizeKB KB)"
                    }
                    
                    # Intelligent payload-based batching logic
                    $projectedBatchSize = $currentBatchSizeKB + $eventSizeKB
                    
                    # Send batch if:
                    # 1. Adding this event would exceed max limit, OR
                    # 2. We've reached target size and have at least 1 event, OR  
                    # 3. This single event is huge (>150KB) and we have other events in batch
                    if (($projectedBatchSize -gt $maxBatchSizeKB) -or
                        ($projectedBatchSize -gt $targetBatchSizeKB -and $currentBatch.Count -gt 0) -or
                        ($eventSizeKB -gt 150 -and $currentBatch.Count -gt 0)) {
                        
                        # Send current batch if it has events
                        if ($currentBatch.Count -gt 0) {
                            Send-ResourceBatch -Events $currentBatch -BatchNumber ($metrics.BatchCount + 1) -BatchSizeKB $currentBatchSizeKB -Metrics $metrics
                        }
                        
                        # Reset batch
                        $currentBatch = @()
                        $currentBatchSizeKB = 0
                    }
                    
                    # Add event to current batch
                    $currentBatch += $event
                    $currentBatchSizeKB += $eventSizeKB
                    $processedResources += $cleanedResource
                    
                    # Track resource types
                    if ($metrics.ProcessedResourceTypes.ContainsKey($resource.type)) {
                        $metrics.ProcessedResourceTypes[$resource.type]++
                    } else {
                        $metrics.ProcessedResourceTypes[$resource.type] = 1
                    }
                    
                    $metrics.ResourceCount++
                }
            }
            catch {
                Write-Warning "Failed to process resource $($resource.id): $($_.Exception.Message)"
                $metrics.FailedResources++
            }
            
            # Progress reporting
            if ($i % 100 -eq 0 -or $i -eq ($allResources.Count - 1)) {
                Write-ExportProgress -Current ($i + 1) -Total $allResources.Count -OperationType "Resources"
            }
        }
        
        # Send final batch if it has events
        if ($currentBatch.Count -gt 0) {
            Send-ResourceBatch -Events $currentBatch -BatchNumber ($metrics.BatchCount + 1) -BatchSizeKB $currentBatchSizeKB -Metrics $metrics
        }
        
        # Calculate final metrics
        $exportDuration = (Get-Date) - $exportStartTime
        $metrics.AverageResourceSizeKB = if ($metrics.ResourceCount -gt 0) { 
            [Math]::Round($metrics.TotalPayloadKB / $metrics.ResourceCount, 2) 
        } else { 0 }
        
        Write-Information "Resource export completed successfully"
        Write-Information "  Resources processed: $($metrics.ResourceCount)"
        Write-Information "  Batches sent: $($metrics.BatchCount)"
        Write-Information "  Failed resources: $($metrics.FailedResources)"
        Write-Information "  Total payload: $([Math]::Round($metrics.TotalPayloadKB, 2)) KB"
        Write-Information "  Average resource size: $($metrics.AverageResourceSizeKB) KB"
        Write-Information "  Large resources (>80KB): $($metrics.LargeResources.Count)"
        Write-Information "  Duration: $($exportDuration.ToString('hh\:mm\:ss'))"
        
        # Log resource type breakdown
        Write-Information "Resource type breakdown:"
        $metrics.ProcessedResourceTypes.GetEnumerator() | 
            Sort-Object Value -Descending | 
            Select-Object -First 10 | 
            ForEach-Object { Write-Information "  $($_.Key): $($_.Value)" }
        
        # Log large resource details
        if ($metrics.LargeResources.Count -gt 0) {
            Write-Information "Large resources detected:"
            $metrics.LargeResources | 
                Sort-Object SizeKB -Descending | 
                Select-Object -First 5 | 
                ForEach-Object { 
                    Write-Information "  $($_.ResourceType): $($_.SizeKB) KB - $($_.ResourceId)" 
                }
        }
        
        return @{
            Success = $true
            ResourceCount = $metrics.ResourceCount
            BatchCount = $metrics.BatchCount
            DurationMs = $exportDuration.TotalMilliseconds
            AllResources = $processedResources
            ResourceTypeBreakdown = $metrics.ProcessedResourceTypes
            FailedResources = $metrics.FailedResources
            LargeResources = $metrics.LargeResources
            OversizedResources = $metrics.OversizedResources
            TotalPayloadKB = $metrics.TotalPayloadKB
            AverageResourceSizeKB = $metrics.AverageResourceSizeKB
        }
        
    }
    catch {
        $exportDuration = (Get-Date) - $exportStartTime
        $errorMessage = $_.Exception.Message
        
        Write-Error "Resource export failed: $errorMessage"
        
        return @{
            Success = $false
            ResourceCount = $metrics.ResourceCount
            BatchCount = $metrics.BatchCount
            DurationMs = $exportDuration.TotalMilliseconds
            AllResources = @()
            Error = @{
                ErrorMessage = $errorMessage
                ErrorType = Get-ErrorType -Exception $_
                PartialMetrics = $metrics
            }
        }
    }
}

# Helper function to send a batch of events to Event Hub with enhanced metrics
function Send-ResourceBatch {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [array]$Events,
        
        [Parameter(Mandatory = $true)]
        [int]$BatchNumber,
        
        [Parameter(Mandatory = $true)]
        [double]$BatchSizeKB,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Metrics
    )
    
    try {
        # Convert events array to JSON payload for Send-EventsToEventHub
        $jsonPayload = ConvertTo-Json -InputObject $Events -Depth 50
        $actualPayloadSizeKB = [Math]::Round([System.Text.Encoding]::UTF8.GetByteCount($jsonPayload)/1024, 2)
        
        Write-Information "Sending batch $BatchNumber with $($Events.Count) events ($actualPayloadSizeKB KB payload)"
        
        $eventHubResult = Send-EventsToEventHub -Payload $jsonPayload
        
        if ($eventHubResult.Success) {
            $Metrics.BatchCount++
            Write-Debug "Successfully sent batch $BatchNumber with $($Events.Count) events ($actualPayloadSizeKB KB) to Event Hub"
        } else {
            Write-Warning "Failed to send batch $BatchNumber to Event Hub"
            
            # Log details about failed chunks if available
            if ($eventHubResult.FailedChunks -and $eventHubResult.FailedChunks.Count -gt 0) {
                foreach ($failedChunk in $eventHubResult.FailedChunks) {
                    Write-Warning "  Failed chunk: $($failedChunk.Error) (Size: $($failedChunk.SizeKB) KB)"
                }
            }
            
            # Track oversized resources
            if ($eventHubResult.OversizedResources -and $eventHubResult.OversizedResources.Count -gt 0) {
                $Metrics.OversizedResources += $eventHubResult.OversizedResources
            }
            
            # Show SKU recommendation if available
            if ($eventHubResult.SKURecommendation) {
                Write-Warning "RECOMMENDATION: $($eventHubResult.SKURecommendation)"
            }
        }
    }
    catch {
        Write-Warning "Exception sending batch $BatchNumber to Event Hub: $($_.Exception.Message)"
    }
}

# Helper function to get paginated resources from Azure
function Get-PaginatedAzureResources {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$QueryUri,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$AuthHeader
    )
    
    $allResources = @()
    $currentUri = $QueryUri
    
    do {
        Write-Debug "Fetching page: $currentUri"
        
        $response = Invoke-RestMethod -Uri $currentUri -Method GET -Headers $AuthHeader -TimeoutSec 120
        
        if ($response.value) {
            $allResources += $response.value
            Write-Debug "Retrieved $($response.value.Count) resources from current page"
        }
        
        # Check for next page
        $currentUri = $response.nextLink
        
    } while ($currentUri)
    
    return $allResources
}
# Multi-Subscription Support Functions
# Add these functions to your SubscriptionExporter module

<#
.SYNOPSIS
    Gets the list of subscription IDs to process based on environment variables and parameters.

.DESCRIPTION
    This function determines which subscriptions to export by checking environment variables
    and function parameters. It supports both single and multi-subscription scenarios.

.PARAMETER SubscriptionFilter
    Optional array of subscription IDs from function parameters.

.NOTES
    Environment Variables Checked:
    - SUBSCRIPTION_ID: Primary/default subscription
    - ALL_SUBSCRIPTION_IDS: Comma-separated list of all subscriptions to process
    - ADDITIONAL_SUBSCRIPTION_IDS: Additional subscriptions beyond the primary
#>

function Get-SubscriptionsToProcess {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string[]]$SubscriptionFilter = @()
    )
    
    Write-Information "Determining subscriptions to process..."
    
    $subscriptionsToProcess = @()
    
    # Priority 1: Use function parameter if provided
    if ($SubscriptionFilter.Count -gt 0) {
        $subscriptionsToProcess = $SubscriptionFilter
        Write-Information "Using subscription filter from parameter: $($SubscriptionFilter -join ', ')"
    }
    # Priority 2: Check for ALL_SUBSCRIPTION_IDS environment variable
    elseif ($env:ALL_SUBSCRIPTION_IDS) {
        $subscriptionsToProcess = $env:ALL_SUBSCRIPTION_IDS -split ','
        $subscriptionsToProcess = $subscriptionsToProcess | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        Write-Information "Using ALL_SUBSCRIPTION_IDS environment variable: $($subscriptionsToProcess -join ', ')"
    }
    # Priority 3: Combine primary + additional subscriptions
    else {
        if ($env:SUBSCRIPTION_ID) {
            $subscriptionsToProcess += $env:SUBSCRIPTION_ID
            Write-Information "Added primary subscription: $($env:SUBSCRIPTION_ID)"
        }
        
        if ($env:ADDITIONAL_SUBSCRIPTION_IDS) {
            $additionalSubs = $env:ADDITIONAL_SUBSCRIPTION_IDS -split ','
            $additionalSubs = $additionalSubs | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
            $subscriptionsToProcess += $additionalSubs
            Write-Information "Added additional subscriptions: $($additionalSubs -join ', ')"
        }
    }
    
    # Remove duplicates and validate
    $subscriptionsToProcess = $subscriptionsToProcess | Select-Object -Unique | Where-Object { 
        $_ -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' 
    }
    
    if ($subscriptionsToProcess.Count -eq 0) {
        throw "No valid subscription IDs found. Please set SUBSCRIPTION_ID or ALL_SUBSCRIPTION_IDS environment variables."
    }
    
    Write-Information "Final subscription list ($($subscriptionsToProcess.Count) subscriptions):"
    $subscriptionsToProcess | ForEach-Object { Write-Information "  - $_" }
    
    return $subscriptionsToProcess
}

<#
.SYNOPSIS
    Orchestrates multi-subscription Azure data export process.

.DESCRIPTION
    Enhanced version of Invoke-SubscriptionDataExport that supports multiple subscriptions.
    Processes each subscription independently and aggregates results.
#>

function Invoke-MultiSubscriptionDataExport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$TriggerContext = "Unknown",
        
        [Parameter(Mandatory = $false)]
        [hashtable]$ExportConfiguration = @{
            SubscriptionObjects = $true
            RoleDefinitions = $false
            ResourceGroupDetails = $true
            RoleAssignments = $true
            PolicyDefinitions = $false
            PolicyAssignments = $false
            PolicyExemptions = $false
            SecurityCenterSubscriptions = $false
            IncludeChildResources = $true
        },
        
        [Parameter(Mandatory = $false)]
        [string[]]$SubscriptionFilter = @(),
        
        [Parameter(Mandatory = $false)]
        [string[]]$ResourceGroupFilter = @()
    )

    # Initialize execution tracking
    $correlationContext = New-CorrelationContext -OperationName "MultiSubscriptionDataExport"
    $exportStartTime = Get-Date
    
    Write-Information "=== Multi-Subscription Azure Data Export Started ==="
    Write-Information "Export ID: $($correlationContext.OperationId)"
    Write-Information "Trigger Context: $TriggerContext"
    
    try {
        # Get list of subscriptions to process
        $subscriptionsToProcess = Get-SubscriptionsToProcess -SubscriptionFilter $SubscriptionFilter
        
        # Initialize aggregate metrics
        $aggregateMetrics = @{
            SubscriptionsProcessed = 0
            SubscriptionsFailed = 0
            TotalResources = 0
            TotalResourceGroups = 0
            TotalChildResources = 0
            TotalEventHubBatches = 0
            SubscriptionResults = @()
            FailedSubscriptions = @()
        }
        
        # Process each subscription
        foreach ($subscriptionId in $subscriptionsToProcess) {
            Write-Information "Processing subscription: $subscriptionId"
            
            try {
                # Set current subscription context
                $originalSubscriptionId = $env:SUBSCRIPTION_ID
                $env:SUBSCRIPTION_ID = $subscriptionId
                
                # Export this subscription
                $subscriptionResult = Invoke-SubscriptionDataExport -TriggerContext "$TriggerContext-MultiSub" -ExportConfiguration $ExportConfiguration -ResourceGroupFilter $ResourceGroupFilter
                
                if ($subscriptionResult.Success) {
                    $aggregateMetrics.SubscriptionsProcessed++
                    $aggregateMetrics.TotalResources += $subscriptionResult.Statistics.Resources
                    $aggregateMetrics.TotalResourceGroups += $subscriptionResult.Statistics.ResourceGroups
                    $aggregateMetrics.TotalChildResources += $subscriptionResult.Statistics.ChildResources
                    $aggregateMetrics.TotalEventHubBatches += $subscriptionResult.Statistics.EventHubBatches
                    
                    $aggregateMetrics.SubscriptionResults += @{
                        SubscriptionId = $subscriptionId
                        Success = $true
                        Statistics = $subscriptionResult.Statistics
                    }
                    
                    Write-Information "Subscription $subscriptionId completed successfully"
                } else {
                    $aggregateMetrics.SubscriptionsFailed++
                    $aggregateMetrics.FailedSubscriptions += @{
                        SubscriptionId = $subscriptionId
                        Error = $subscriptionResult.Error
                    }
                    
                    Write-Warning "Subscription $subscriptionId failed: $($subscriptionResult.Error.ErrorMessage)"
                }
                
                # Restore original subscription context
                $env:SUBSCRIPTION_ID = $originalSubscriptionId
                
            } catch {
                $aggregateMetrics.SubscriptionsFailed++
                $aggregateMetrics.FailedSubscriptions += @{
                    SubscriptionId = $subscriptionId
                    Error = @{
                        ErrorMessage = $_.Exception.Message
                        ErrorType = $_.Exception.GetType().Name
                    }
                }
                
                Write-Error "Critical error processing subscription $subscriptionId : $($_.Exception.Message)"
                
                # Restore original subscription context
                $env:SUBSCRIPTION_ID = $originalSubscriptionId
            }
        }
        
        # Calculate final metrics
        $exportEndTime = Get-Date
        $totalExportDuration = $exportEndTime - $exportStartTime
        $totalRecords = $aggregateMetrics.TotalResources + $aggregateMetrics.TotalResourceGroups + $aggregateMetrics.TotalChildResources
        
        # Log completion telemetry
        $completionProps = @{
            ExportId = $correlationContext.OperationId
            TriggerContext = $TriggerContext
            TotalSubscriptions = $subscriptionsToProcess.Count
            SubscriptionsProcessed = $aggregateMetrics.SubscriptionsProcessed
            SubscriptionsFailed = $aggregateMetrics.SubscriptionsFailed
            TotalRecords = $totalRecords
            TotalEventHubBatches = $aggregateMetrics.TotalEventHubBatches
            ExecutionTimeMs = $totalExportDuration.TotalMilliseconds
        }
        
        Write-CustomTelemetry -EventName "MultiSubscriptionExportCompleted" -Properties $completionProps
        
        Write-Information "=== Multi-Subscription Azure Data Export Completed ==="
        Write-Information "Export ID: $($correlationContext.OperationId)"
        Write-Information "Total Subscriptions: $($subscriptionsToProcess.Count)"
        Write-Information "Successfully Processed: $($aggregateMetrics.SubscriptionsProcessed)"
        Write-Information "Failed: $($aggregateMetrics.SubscriptionsFailed)"
        Write-Information "Total Records: $totalRecords"
        Write-Information "Duration: $($totalExportDuration.ToString('hh\:mm\:ss'))"
        
        return @{
            Success = ($aggregateMetrics.SubscriptionsFailed -eq 0)
            ExportId = $correlationContext.OperationId
            MultiSubscription = $true
            SubscriptionsProcessed = $aggregateMetrics.SubscriptionsProcessed
            SubscriptionsFailed = $aggregateMetrics.SubscriptionsFailed
            Statistics = @{
                TotalSubscriptions = $subscriptionsToProcess.Count
                Resources = $aggregateMetrics.TotalResources
                ResourceGroups = $aggregateMetrics.TotalResourceGroups
                ChildResources = $aggregateMetrics.TotalChildResources
                TotalRecords = $totalRecords
                EventHubBatches = $aggregateMetrics.TotalEventHubBatches
                Duration = $totalExportDuration.TotalMinutes
            }
            SubscriptionResults = $aggregateMetrics.SubscriptionResults
            FailedSubscriptions = $aggregateMetrics.FailedSubscriptions
            StartTime = $exportStartTime
            EndTime = $exportEndTime
        }
        
    } catch {
        $exportEndTime = Get-Date
        $failureDuration = $exportEndTime - $exportStartTime
        $errorMessage = $_.Exception.Message
        
        Write-Error "=== Multi-Subscription Export Failed ==="
        Write-Error "Export ID: $($correlationContext.OperationId)"
        Write-Error "Error: $errorMessage"
        
        return @{
            Success = $false
            ExportId = $correlationContext.OperationId
            MultiSubscription = $true
            Error = @{
                ErrorMessage = $errorMessage
                ErrorType = Get-ErrorType -Exception $_
                Timestamp = $exportEndTime.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            }
            PartialStatistics = $aggregateMetrics
        }
    }
}
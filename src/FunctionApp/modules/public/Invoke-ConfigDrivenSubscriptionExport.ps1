<#
.SYNOPSIS
    Orchestrates configuration-driven multi-subscription Azure data export process.

.DESCRIPTION
    Enhanced version that reads subscription lists and export settings from YAML configuration files.
    Supports both file-based and environment variable configuration with automatic fallback.
#>

function Invoke-ConfigDrivenSubscriptionExport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$TriggerContext = "Unknown",
        
        [Parameter(Mandatory = $false)]
        [string]$ConfigFileName = "subscriptions",
        
        [Parameter(Mandatory = $false)]
        [hashtable]$OverrideExportConfiguration = @{},
        
        [Parameter(Mandatory = $false)]
        [string[]]$SubscriptionFilterOverride = @()
    )

    # Initialize execution tracking
    $correlationContext = New-CorrelationContext -OperationName "ConfigDrivenSubscriptionExport"
    $exportStartTime = Get-Date
    
    Write-Information "=== Configuration-Driven Azure Subscription Export Started ==="
    Write-Information "Export ID: $($correlationContext.OperationId)"
    Write-Information "Trigger Context: $TriggerContext"
    Write-Information "Config File: $ConfigFileName.yaml"
    
    try {
        # Step 1: Load configuration
        Write-Information "Loading configuration from file..."
        $config = Get-SubscriptionExportConfig -ConfigFileName $ConfigFileName
        
        if (-not $config) {
            throw "Failed to load configuration"
        }
        
        Write-Information "Configuration loaded successfully"
        Write-Information "  Configuration Source: $($config.Metadata.description)"
        Write-Information "  Available Subscriptions: $($config.Subscriptions.Count)"
        
        # Step 2: Determine subscriptions to process
        $subscriptionsToProcess = @()
        
        if ($SubscriptionFilterOverride.Count -gt 0) {
            # Use override filter
            foreach ($subId in $SubscriptionFilterOverride) {
                $matchingSub = $config.Subscriptions | Where-Object { $_.Id -eq $subId }
                if ($matchingSub) {
                    $subscriptionsToProcess += $matchingSub
                } else {
                    Write-Warning "Subscription ID $subId not found in configuration"
                }
            }
            Write-Information "Using subscription filter override: $($SubscriptionFilterOverride -join ', ')"
        } else {
            # Use all configured subscriptions
            $subscriptionsToProcess = $config.Subscriptions
            Write-Information "Processing all configured subscriptions"
        }
        
        if ($subscriptionsToProcess.Count -eq 0) {
            throw "No subscriptions configured for export"
        }
        
        # Step 3: Prepare export configuration
        $exportConfiguration = $config.ExportSettings.Clone()
        
        # Apply any overrides
        foreach ($key in $OverrideExportConfiguration.Keys) {
            $exportConfiguration[$key] = $OverrideExportConfiguration[$key]
            Write-Information "Override applied: $key = $($OverrideExportConfiguration[$key])"
        }
        
        Write-Information "Export Configuration:"
        $exportConfiguration.GetEnumerator() | ForEach-Object { 
            Write-Information "  $($_.Key): $($_.Value)" 
        }
        
        # Step 4: Initialize aggregate metrics
        $aggregateMetrics = @{
            SubscriptionsProcessed = 0
            SubscriptionsFailed = 0
            TotalResources = 0
            TotalResourceGroups = 0
            TotalChildResources = 0
            TotalEventHubBatches = 0
            SubscriptionResults = @()
            FailedSubscriptions = @()
            ConfigurationSource = $config.Metadata.description
        }
        
        # Step 5: Process each subscription
        Write-Information "Starting subscription processing..."
        
        foreach ($subscription in $subscriptionsToProcess) {
            Write-Information "Processing subscription: $($subscription.Name) ($($subscription.Id))"
            
            try {
                # Set current subscription context
                $originalSubscriptionId = $env:SUBSCRIPTION_ID
                $env:SUBSCRIPTION_ID = $subscription.Id
                
                # Export this subscription
                $subscriptionResult = Invoke-SubscriptionDataExport -TriggerContext "$TriggerContext-Config" -ExportConfiguration $exportConfiguration -ResourceGroupFilter $config.ResourceGroupFilters
                
                if ($subscriptionResult.Success) {
                    $aggregateMetrics.SubscriptionsProcessed++
                    $aggregateMetrics.TotalResources += $subscriptionResult.Statistics.Resources
                    $aggregateMetrics.TotalResourceGroups += $subscriptionResult.Statistics.ResourceGroups
                    $aggregateMetrics.TotalChildResources += $subscriptionResult.Statistics.ChildResources
                    $aggregateMetrics.TotalEventHubBatches += $subscriptionResult.Statistics.EventHubBatches
                    
                    $aggregateMetrics.SubscriptionResults += @{
                        SubscriptionId = $subscription.Id
                        SubscriptionName = $subscription.Name
                        Success = $true
                        Statistics = $subscriptionResult.Statistics
                        Priority = $subscription.Priority
                    }
                    
                    Write-Information "Subscription '$($subscription.Name)' completed successfully"
                    Write-Information "  Resources: $($subscriptionResult.Statistics.Resources)"
                    Write-Information "  Resource Groups: $($subscriptionResult.Statistics.ResourceGroups)"
                    Write-Information "  Child Resources: $($subscriptionResult.Statistics.ChildResources)"
                } else {
                    $aggregateMetrics.SubscriptionsFailed++
                    $aggregateMetrics.FailedSubscriptions += @{
                        SubscriptionId = $subscription.Id
                        SubscriptionName = $subscription.Name
                        Priority = $subscription.Priority
                        Error = $subscriptionResult.Error
                    }
                    
                    Write-Warning "Subscription '$($subscription.Name)' failed: $($subscriptionResult.Error.ErrorMessage)"
                }
                
                # Restore original subscription context
                $env:SUBSCRIPTION_ID = $originalSubscriptionId
                
            } catch {
                $aggregateMetrics.SubscriptionsFailed++
                $aggregateMetrics.FailedSubscriptions += @{
                    SubscriptionId = $subscription.Id
                    SubscriptionName = $subscription.Name
                    Priority = $subscription.Priority
                    Error = @{
                        ErrorMessage = $_.Exception.Message
                        ErrorType = $_.Exception.GetType().Name
                    }
                }
                
                Write-Error "Critical error processing subscription '$($subscription.Name)': $($_.Exception.Message)"
                
                # Restore original subscription context
                $env:SUBSCRIPTION_ID = $originalSubscriptionId
            }
        }
        
        # Step 6: Calculate final metrics
        $exportEndTime = Get-Date
        $totalExportDuration = $exportEndTime - $exportStartTime
        $totalRecords = $aggregateMetrics.TotalResources + $aggregateMetrics.TotalResourceGroups + $aggregateMetrics.TotalChildResources
        
        # Step 7: Log completion telemetry
        $completionProps = @{
            ExportId = $correlationContext.OperationId
            TriggerContext = $TriggerContext
            ConfigurationSource = $config.Metadata.description
            ConfigurationVersion = $config.Metadata.version
            TotalSubscriptions = $subscriptionsToProcess.Count
            SubscriptionsProcessed = $aggregateMetrics.SubscriptionsProcessed
            SubscriptionsFailed = $aggregateMetrics.SubscriptionsFailed
            TotalRecords = $totalRecords
            TotalEventHubBatches = $aggregateMetrics.TotalEventHubBatches
            ExecutionTimeMs = $totalExportDuration.TotalMilliseconds
        }
        
        Write-CustomTelemetry -EventName "ConfigDrivenSubscriptionExportCompleted" -Properties $completionProps
        
        # Step 8: Final reporting
        Write-Information "=== Configuration-Driven Subscription Export Completed ==="
        Write-Information "Export ID: $($correlationContext.OperationId)"
        Write-Information "Configuration: $($config.Metadata.description) v$($config.Metadata.version)"
        Write-Information "Total Subscriptions: $($subscriptionsToProcess.Count)"
        Write-Information "Successfully Processed: $($aggregateMetrics.SubscriptionsProcessed)"
        Write-Information "Failed: $($aggregateMetrics.SubscriptionsFailed)"
        Write-Information "Total Records: $totalRecords"
        Write-Information "Total Event Hub Batches: $($aggregateMetrics.TotalEventHubBatches)"
        Write-Information "Duration: $($totalExportDuration.ToString('hh\:mm\:ss'))"
        
        if ($aggregateMetrics.FailedSubscriptions.Count -gt 0) {
            Write-Information "Failed Subscriptions:"
            $aggregateMetrics.FailedSubscriptions | ForEach-Object {
                Write-Information "  - $($_.SubscriptionName) ($($_.SubscriptionId)): $($_.Error.ErrorMessage)"
            }
        }
        
        return @{
            Success = ($aggregateMetrics.SubscriptionsFailed -eq 0)
            ExportId = $correlationContext.OperationId
            ConfigurationDriven = $true
            ConfigurationSource = $config.Metadata.description
            ConfigurationVersion = $config.Metadata.version
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
            Configuration = $config
            StartTime = $exportStartTime
            EndTime = $exportEndTime
        }
        
    } catch {
        $exportEndTime = Get-Date
        $failureDuration = $exportEndTime - $exportStartTime
        $errorMessage = $_.Exception.Message
        
        Write-Error "=== Configuration-Driven Export Failed ==="
        Write-Error "Export ID: $($correlationContext.OperationId)"
        Write-Error "Error: $errorMessage"
        
        return @{
            Success = $false
            ExportId = $correlationContext.OperationId
            ConfigurationDriven = $true
            Error = @{
                ErrorMessage = $errorMessage
                ErrorType = Get-ErrorType -Exception $_
                Timestamp = $exportEndTime.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            }
            PartialStatistics = if ($aggregateMetrics) { $aggregateMetrics } else { @{} }
        }
    }
}
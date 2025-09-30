param($Timer)

# Enhanced logging and diagnostics
$DebugPreference = "Continue"
$InformationPreference = "Continue"
$VerbosePreference = "Continue"

Write-Host "=========================================="
Write-Host "Timer Trigger Function Started - Config-Driven Mode"
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)"
Write-Host "Execution Policy: $(Get-ExecutionPolicy)"
Write-Host "Current Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"

# Validate Timer object
if ($null -eq $Timer) {
    Write-Error "CRITICAL: Timer parameter is null - binding configuration problem"
    throw "Timer binding failed - check function.json configuration"
}

Write-Host "Timer Object Type: $($Timer.GetType().FullName)"
Write-Host "Timer Properties Available: $($Timer | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name)"

# Safe property access with null checking
$scheduledTime = if ($Timer.PSObject.Properties['ScheduledTime']) { $Timer.ScheduledTime } else { "Not Available" }
$isPastDue = if ($Timer.PSObject.Properties['IsPastDue']) { $Timer.IsPastDue } else { "Not Available" }

Write-Host "Scheduled Time: $scheduledTime"
Write-Host "Is Past Due: $isPastDue"
Write-Host "=========================================="

try {
    # Module availability check with detailed diagnostics
    Write-Host "Checking module availability..."
    
    $configDrivenExportCommand = Get-Command -Name "Invoke-ConfigDrivenSubscriptionExport" -ErrorAction SilentlyContinue
    $subscriptionExportCommand = Get-Command -Name "Invoke-SubscriptionDataExport" -ErrorAction SilentlyContinue
    $multiSubscriptionExportCommand = Get-Command -Name "Invoke-MultiSubscriptionDataExport" -ErrorAction SilentlyContinue
    $configReaderCommand = Get-Command -Name "Get-SubscriptionExportConfig" -ErrorAction SilentlyContinue
    
    if (-not $subscriptionExportCommand) {
        Write-Error "CRITICAL: SubscriptionExporter module not properly loaded"
        Write-Host "Available modules:"
        Get-Module | ForEach-Object { Write-Host "  - $($_.Name) ($($_.Version))" }
        
        Write-Host "Available commands containing 'Subscription':"
        Get-Command -Name "*Subscription*" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  - $($_.Name)" }
        
        throw "SubscriptionExporter module not properly loaded - core functions not available"
    }

    Write-Host "✅ SubscriptionExporter module verified"
    Write-Host "Available export functions:"
    if ($configDrivenExportCommand) { Write-Host "  ✅ Invoke-ConfigDrivenSubscriptionExport (preferred)" }
    if ($multiSubscriptionExportCommand) { Write-Host "  ✅ Invoke-MultiSubscriptionDataExport (fallback)" }
    if ($subscriptionExportCommand) { Write-Host "  ✅ Invoke-SubscriptionDataExport (single subscription)" }
    if ($configReaderCommand) { Write-Host "  ✅ Get-SubscriptionExportConfig (config reader)" }
    
    # Check for configuration file
    $configFileExists = $false
    $configFilePath = ""
    
    try {
        $scriptDirectory = Split-Path $PSScriptRoot -Parent
        $configDirectory = Join-Path $scriptDirectory "config"
        $configFilePath = Join-Path $configDirectory "subscriptions.yaml"
        
        if (Test-Path $configFilePath) {
            $configFileExists = $true
            Write-Host "✅ Configuration file found: $configFilePath"
        } else {
            Write-Host "⚠️  Configuration file not found: $configFilePath"
        }
    } catch {
        Write-Host "⚠️  Error checking for configuration file: $($_.Exception.Message)"
    }
    
    # Determine execution mode
    $executionMode = "Unknown"
    $executionDetails = ""
    
    if ($configFileExists -and $configDrivenExportCommand) {
        $executionMode = "ConfigDriven"
        $executionDetails = "Using YAML configuration file"
    } elseif ($env:ALL_SUBSCRIPTION_IDS -or $env:ADDITIONAL_SUBSCRIPTION_IDS) {
        # Check for multi-subscription environment variables
        if ($env:ALL_SUBSCRIPTION_IDS) {
            $allSubs = $env:ALL_SUBSCRIPTION_IDS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
            $executionMode = "MultiSubscription"
            $executionDetails = "Environment variables: $($allSubs.Count) subscriptions"
        } elseif ($env:ADDITIONAL_SUBSCRIPTION_IDS) {
            $additionalSubs = $env:ADDITIONAL_SUBSCRIPTION_IDS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
            $executionMode = "MultiSubscription"
            $executionDetails = "Environment variables: Primary + $($additionalSubs.Count) additional"
        }
    } else {
        $executionMode = "SingleSubscription"
        $executionDetails = "Single subscription: $($env:SUBSCRIPTION_ID)"
    }
    
    Write-Host "Execution Mode: $executionMode"
    Write-Host "Details: $executionDetails"
    Write-Host "Config File Path: $configFilePath"
    
    # Execute appropriate export function based on available options and configuration
    switch ($executionMode) {
        "ConfigDriven" {
            Write-Host "Starting Configuration-Driven subscription export via Timer trigger..."
            
            $exportResult = Invoke-ConfigDrivenSubscriptionExport -TriggerContext "TimerTrigger"
            
            if ($exportResult -and $exportResult.Success) {
                Write-Host "✅ Configuration-Driven Timer Trigger completed successfully"
                Write-Host "Export Statistics:"
                Write-Host "  - Export ID: $($exportResult.ExportId)"
                Write-Host "  - Configuration: $($exportResult.ConfigurationSource) v$($exportResult.ConfigurationVersion)"
                Write-Host "  - Total Subscriptions: $($exportResult.Statistics.TotalSubscriptions)"
                Write-Host "  - Subscriptions Processed: $($exportResult.SubscriptionsProcessed)"
                Write-Host "  - Subscriptions Failed: $($exportResult.SubscriptionsFailed)"
                Write-Host "  - Total Resources: $($exportResult.Statistics.Resources)"
                Write-Host "  - Total Resource Groups: $($exportResult.Statistics.ResourceGroups)"
                Write-Host "  - Total Child Resources: $($exportResult.Statistics.ChildResources)"
                Write-Host "  - Total Records: $($exportResult.Statistics.TotalRecords)"
                Write-Host "  - Duration: $([Math]::Round($exportResult.Statistics.Duration, 2)) minutes"
                Write-Host "  - Event Hub Batches: $($exportResult.Statistics.EventHubBatches)"
                
                if ($exportResult.FailedSubscriptions.Count -gt 0) {
                    Write-Host "Failed Subscriptions:"
                    $exportResult.FailedSubscriptions | ForEach-Object {
                        Write-Host "  - $($_.SubscriptionName) ($($_.SubscriptionId)): $($_.Error.ErrorMessage)"
                    }
                }
                
                # Display configuration summary
                if ($exportResult.Configuration -and $exportResult.Configuration.Subscriptions) {
                    Write-Host "Configured Subscriptions:"
                    $exportResult.Configuration.Subscriptions | ForEach-Object {
                        Write-Host "  - $($_.Name) ($($_.Id)) [Priority: $($_.Priority)]"
                    }
                }
            } else {
                $errorMessage = "Configuration-Driven Timer Trigger failed"
                if ($exportResult -and $exportResult.ExportId) {
                    $errorMessage += " - Export ID: $($exportResult.ExportId)"
                }
                
                Write-Error $errorMessage
                
                if ($exportResult -and $exportResult.Error) {
                    Write-Error "Error Type: $($exportResult.Error.ErrorType)"
                    Write-Error "Error Message: $($exportResult.Error.ErrorMessage)"
                    throw "Configuration-Driven Data Export failed during scheduled execution: $($exportResult.Error.ErrorMessage)"
                } else {
                    throw "Configuration-Driven Data Export returned unsuccessful result with no error details"
                }
            }
        }
        
        "MultiSubscription" {
            if ($multiSubscriptionExportCommand) {
                Write-Host "Starting Multi-Subscription data export via Timer trigger..."
                
                # Use default export configuration
                $exportConfiguration = @{
                    SubscriptionObjects = $true
                    RoleDefinitions = $false
                    ResourceGroupDetails = $true
                    RoleAssignments = $true
                    PolicyDefinitions = $false
                    PolicyAssignments = $false
                    PolicyExemptions = $false
                    SecurityCenterSubscriptions = $false
                    IncludeChildResources = $true
                }
                
                $exportResult = Invoke-MultiSubscriptionDataExport -TriggerContext "TimerTrigger" -ExportConfiguration $exportConfiguration
                
                if ($exportResult -and $exportResult.Success) {
                    Write-Host "✅ Multi-Subscription Timer Trigger completed successfully"
                    Write-Host "Export Statistics:"
                    Write-Host "  - Export ID: $($exportResult.ExportId)"
                    Write-Host "  - Total Subscriptions: $($exportResult.Statistics.TotalSubscriptions)"
                    Write-Host "  - Subscriptions Processed: $($exportResult.SubscriptionsProcessed)"
                    Write-Host "  - Subscriptions Failed: $($exportResult.SubscriptionsFailed)"
                    Write-Host "  - Total Resources: $($exportResult.Statistics.Resources)"
                    Write-Host "  - Total Resource Groups: $($exportResult.Statistics.ResourceGroups)"
                    Write-Host "  - Total Child Resources: $($exportResult.Statistics.ChildResources)"
                    Write-Host "  - Total Records: $($exportResult.Statistics.TotalRecords)"
                    Write-Host "  - Duration: $([Math]::Round($exportResult.Statistics.Duration, 2)) minutes"
                    Write-Host "  - Event Hub Batches: $($exportResult.Statistics.EventHubBatches)"
                } else {
                    throw "Multi-Subscription Data Export failed during scheduled execution"
                }
            } else {
                throw "Multi-subscription configuration detected but Invoke-MultiSubscriptionDataExport function not available"
            }
        }
        
        "SingleSubscription" {
            Write-Host "Starting single Subscription data export via Timer trigger..."
            
            # Use default export configuration
            $exportConfiguration = @{
                SubscriptionObjects = $true
                RoleDefinitions = $false
                ResourceGroupDetails = $true
                RoleAssignments = $true
                PolicyDefinitions = $false
                PolicyAssignments = $false
                PolicyExemptions = $false
                SecurityCenterSubscriptions = $false
                IncludeChildResources = $true
            }
            
            $exportResult = Invoke-SubscriptionDataExport -TriggerContext "TimerTrigger" -ExportConfiguration $exportConfiguration
            
            if ($exportResult -and $exportResult.Success) {
                Write-Host "✅ Single Subscription Timer Trigger completed successfully"
                Write-Host "Export Statistics:"
                Write-Host "  - Export ID: $($exportResult.ExportId)"
                Write-Host "  - Resources: $($exportResult.Statistics.Resources)"
                Write-Host "  - Resource Groups: $($exportResult.Statistics.ResourceGroups)" 
                Write-Host "  - Child Resources: $($exportResult.Statistics.ChildResources)"
                Write-Host "  - Total Records: $($exportResult.Statistics.TotalRecords)"
                Write-Host "  - Duration: $([Math]::Round($exportResult.Statistics.Duration, 2)) minutes"
                Write-Host "  - Event Hub Batches: $($exportResult.Statistics.EventHubBatches)"
                
                if ($exportResult.Statistics.StageTimings) {
                    Write-Host "Stage Timings:"
                    Write-Host "  - Authentication: $($exportResult.Statistics.StageTimings.Authentication)s"
                    Write-Host "  - API Discovery: $($exportResult.Statistics.StageTimings.APIVersionDiscovery)s"
                    Write-Host "  - Resources Export: $($exportResult.Statistics.StageTimings.ResourcesExport)s"
                    Write-Host "  - Resource Groups Export: $($exportResult.Statistics.StageTimings.ResourceGroupsExport)s"
                    Write-Host "  - Child Resources Export: $($exportResult.Statistics.StageTimings.ChildResourcesExport)s"
                }
            } else {
                throw "Single Subscription Data Export failed during scheduled execution"
            }
        }
        
        default {
            throw "Unable to determine appropriate execution mode. Please check configuration."
        }
    }
    
    if ($scheduledTime -ne "Not Available") {
        Write-Host "Next scheduled run: $(([DateTime]$scheduledTime).AddDays(1))"
    }
    
} catch {
    Write-Error "❌ CRITICAL ERROR in Timer Trigger execution"
    Write-Error "Exception Type: $($_.Exception.GetType().FullName)"
    Write-Error "Exception Message: $($_.Exception.Message)"
    
    if ($_.Exception.InnerException) {
        Write-Error "Inner Exception: $($_.Exception.InnerException.Message)"
    }
    
    Write-Error "Stack Trace: $($_.ScriptStackTrace)"
    
    # Re-throw to ensure function shows as failed in Azure monitoring
    throw $_
}

Write-Host "Timer Trigger Function execution completed"
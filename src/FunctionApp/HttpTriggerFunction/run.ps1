param($httpobj)

# Set up logging preferences
$DebugPreference = "Continue"
$InformationPreference = "Continue"

# Initialize HTTP execution context
$requestId = [System.Guid]::NewGuid().ToString()
Write-Information "=============================================="
Write-Information "HTTP Trigger Function Started - Config-Driven Subscription Export"
Write-Information "Request ID: $requestId"
Write-Information "Method: $($httpobj.Method)"
Write-Information "Current Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"
Write-Information "=============================================="

try {
    # Validate HTTP method
    if ($httpobj.Method -notin @('GET', 'POST')) {
        Write-Warning "Unsupported HTTP method: $($httpobj.Method)"
        
        return @{
            statusCode = 405
            headers = @{
                'Content-Type' = 'application/json'
            }
            body = @{
                error = "Method Not Allowed"
                message = "Only GET and POST methods are supported"
                requestId = $requestId
            } | ConvertTo-Json
        }
    }

    # For GET requests, return status information and configuration preview
    if ($httpobj.Method -eq 'GET') {
        Write-Information "GET request - returning function status and configuration preview"
        
        # Try to load configuration for preview
        $configPreview = @{
            status = "unavailable"
            message = "Configuration file not found or not readable"
        }
        
        try {
            $config = Get-SubscriptionExportConfig -ConfigFileName "subscriptions"
            if ($config) {
                $configPreview = @{
                    status = "available"
                    source = $config.Metadata.description
                    version = $config.Metadata.version
                    subscriptionsCount = $config.Subscriptions.Count
                    subscriptions = $config.Subscriptions | ForEach-Object {
                        @{
                            name = $_.Name
                            id = $_.Id.Substring(0, 8) + "..." # Partial ID for security
                            priority = $_.Priority
                        }
                    }
                    exportSettings = $config.ExportSettings
                    resourceGroupFilters = $config.ResourceGroupFilters
                    hasAdvancedSettings = ($config.Advanced.Keys.Count -gt 0)
                }
            }
        }
        catch {
            Write-Debug "Failed to load configuration for preview: $($_.Exception.Message)"
        }
        
        $statusInfo = @{
            status = "ready"
            message = "HTTP Trigger Function is operational - Configuration-Driven Subscription Export"
            requestId = $requestId
            functionVersion = "1.0-ConfigDriven"
            timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
            mode = "ConfigDrivenSubscriptionExport"
            configuration = $configPreview
            supportedOperations = @{
                "GET /" = "Returns this status information and configuration preview"
                "POST /" = "Executes subscription export using default configuration"
                "POST / with body" = "Executes subscription export with optional overrides"
            }
            requestBodyExample = @{
                configFile = "subscriptions"
                subscriptionFilter = @("sub-id-1", "sub-id-2")
                exportConfigurationOverrides = @{
                    RoleAssignments = $true
                    PolicyDefinitions = $true
                }
            }
        }
        
        return @{
            statusCode = 200
            headers = @{
                'Content-Type' = 'application/json'
            }
            body = ($statusInfo | ConvertTo-Json -Depth 5)
        }
    }
    
    # For POST requests, execute Configuration-Driven Subscription data export
    Write-Information "POST request - invoking Configuration-Driven Subscription Data Export"
    
    # Parse request body for options
    $configFileName = "subscriptions"
    $subscriptionFilterOverride = @()
    $exportConfigurationOverrides = @{}
    
    if ($httpobj.Body) {
        try {
            $requestBody = $httpobj.Body | ConvertFrom-Json
            
            if ($requestBody.configFile) {
                $configFileName = $requestBody.configFile
                Write-Information "Using custom config file: $configFileName"
            }
            
            if ($requestBody.subscriptionFilter -and $requestBody.subscriptionFilter.Count -gt 0) {
                $subscriptionFilterOverride = $requestBody.subscriptionFilter
                Write-Information "Using subscription filter: $($subscriptionFilterOverride -join ', ')"
            }
            
            if ($requestBody.exportConfigurationOverrides) {
                $exportConfigurationOverrides = @{}
                foreach ($key in $requestBody.exportConfigurationOverrides.PSObject.Properties.Name) {
                    $exportConfigurationOverrides[$key] = $requestBody.exportConfigurationOverrides.$key
                }
                Write-Information "Export configuration overrides applied: $($exportConfigurationOverrides.Keys -join ', ')"
            }
        }
        catch {
            Write-Warning "Failed to parse request body, using defaults: $($_.Exception.Message)"
        }
    }
    
    # Execute the Configuration-Driven Subscription data export
    Write-Information "Starting Configuration-Driven Subscription Data Export via HTTP trigger"
    Write-Information "Config File: $configFileName.yaml"
    
    $exportResult = Invoke-ConfigDrivenSubscriptionExport -TriggerContext "HTTPTrigger" -ConfigFileName $configFileName -SubscriptionFilterOverride $subscriptionFilterOverride -OverrideExportConfiguration $exportConfigurationOverrides
    
    if ($exportResult.Success) {
        Write-Information "HTTP Trigger completed successfully"
        
        return @{
            statusCode = 202
            headers = @{
                'Content-Type' = 'application/json'
            }
            body = @{
                status = "success"
                message = "Configuration-Driven Azure Subscription data export completed successfully"
                requestId = $requestId
                exportId = $exportResult.ExportId
                mode = "ConfigDrivenSubscriptionExport"
                configuration = @{
                    source = $exportResult.ConfigurationSource
                    version = $exportResult.ConfigurationVersion
                    configFile = "$configFileName.yaml"
                }
                statistics = @{
                    totalSubscriptions = $exportResult.Statistics.TotalSubscriptions
                    subscriptionsProcessed = $exportResult.SubscriptionsProcessed
                    subscriptionsFailed = $exportResult.SubscriptionsFailed
                    resources = $exportResult.Statistics.Resources
                    resourceGroups = $exportResult.Statistics.ResourceGroups
                    childResources = $exportResult.Statistics.ChildResources
                    totalRecords = $exportResult.Statistics.TotalRecords
                    eventHubBatches = $exportResult.Statistics.EventHubBatches
                    duration = @{
                        totalMinutes = $exportResult.Statistics.Duration
                    }
                }
                subscriptions = @{
                    processed = $exportResult.SubscriptionResults | ForEach-Object {
                        @{
                            subscriptionId = $_.SubscriptionId
                            subscriptionName = $_.SubscriptionName
                            success = $_.Success
                            resources = $_.Statistics.Resources
                            resourceGroups = $_.Statistics.ResourceGroups
                            childResources = $_.Statistics.ChildResources
                        }
                    }
                    failed = $exportResult.FailedSubscriptions | ForEach-Object {
                        @{
                            subscriptionId = $_.SubscriptionId
                            subscriptionName = $_.SubscriptionName
                            error = $_.Error.ErrorMessage
                        }
                    }
                }
                execution = @{
                    startTime = $exportResult.StartTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
                    endTime = $exportResult.EndTime.ToString('yyyy-MM-ddTHH:mm:ssZ')
                    triggerContext = "HTTPTrigger"
                    configurationDriven = $true
                }
                overrides = @{
                    subscriptionFilter = $subscriptionFilterOverride
                    exportConfigurationOverrides = $exportConfigurationOverrides
                }
            } | ConvertTo-Json -Depth 6
        }
        
    } else {
        Write-Error "HTTP Trigger processing failed"
        
        return @{
            statusCode = 500
            headers = @{
                'Content-Type' = 'application/json'
            }
            body = @{
                status = "export_failed"
                message = "Configuration-Driven Subscription data export encountered errors"
                requestId = $requestId
                exportId = $exportResult.ExportId
                mode = "ConfigDrivenSubscriptionExport"
                configuration = @{
                    source = if ($exportResult.ConfigurationSource) { $exportResult.ConfigurationSource } else { "Unknown" }
                    version = if ($exportResult.ConfigurationVersion) { $exportResult.ConfigurationVersion } else { "Unknown" }
                    configFile = "$configFileName.yaml"
                }
                error = @{
                    message = $exportResult.Error.ErrorMessage
                    type = $exportResult.Error.ErrorType
                    timestamp = $exportResult.Error.Timestamp
                }
                partialResults = @{
                    subscriptionsProcessed = $exportResult.SubscriptionsProcessed
                    subscriptionsFailed = $exportResult.SubscriptionsFailed
                    partialStatistics = $exportResult.PartialStatistics
                }
                troubleshooting = @{
                    correlationId = $exportResult.ExportId
                    recommendation = "Check Application Insights for detailed error information"
                    configurationPath = "config/$configFileName.yaml"
                }
            } | ConvertTo-Json -Depth 5
        }
    }
    
} catch {
    Write-Error "Critical error in HTTP Trigger execution: $($_.Exception.Message)"
    
    return @{
        statusCode = 500
        headers = @{
            'Content-Type' = 'application/json'
        }
        body = @{
            status = "critical_error"
            message = "Unhandled exception in configuration-driven HTTP trigger"
            requestId = $requestId
            mode = "ConfigDrivenSubscriptionExport"
            error = @{
                message = $_.Exception.Message
                type = $_.Exception.GetType().Name
                timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
            }
            troubleshooting = @{
                requestId = $requestId
                recommendation = "Check Function App logs for detailed investigation"
                configurationPath = "config/subscriptions.yaml"
            }
        } | ConvertTo-Json -Depth 4
    }
}
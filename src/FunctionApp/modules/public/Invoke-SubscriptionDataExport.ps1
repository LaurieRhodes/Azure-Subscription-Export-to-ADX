<#
.SYNOPSIS
    Orchestrates the complete Azure Subscription data export process using modular components.

.DESCRIPTION
    This function coordinates the export of Azure Subscription data (Resources, Resource Groups, Child Resources) 
    to Azure Data Explorer via Event Hub. Uses the proven Get-AzureADToken module for authentication.
    
    Based on proven architecture from 5+ years of successful subscription backup operations,
    modernized for Function Apps with Managed Identity and enhanced error handling.

.PARAMETER TriggerContext
    Context information from the calling trigger (Timer, HTTP, etc.).

.PARAMETER ExportConfiguration
    Hashtable specifying which types of objects to export.

.PARAMETER SubscriptionFilter
    Optional array of subscription IDs to export. If not specified, exports current subscription.

.PARAMETER ResourceGroupFilter
    Optional array of resource group names to limit export scope.

.NOTES
    Author: Laurie Rhodes
    Version: 1.2 - USING WORKING GET-AZUREADTOKEN
    Last Modified: 2025-09-27
    
    FIXED: Now uses the proven Get-AzureADToken module instead of problematic Get-AzureARMToken
    
    Key Features:
    - Uses working Get-AzureADToken authentication module
    - Enhanced error handling with fatal vs transient error recognition
    - Comprehensive performance monitoring and telemetry
    - Dynamic API version discovery
    - Intelligent child resource handling
#>

function Invoke-SubscriptionDataExport {
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
    $correlationContext = New-CorrelationContext -OperationName "SubscriptionDataExport"
    $exportStartTime = Get-Date
    
    # Initialize performance metrics
    $performanceMetrics = @{
        ResourceCount = 0
        ResourceGroupCount = 0
        ChildResourceCount = 0
        TotalEventHubBatches = 0
        AuthenticationTime = 0
        ResourcesExportTime = 0
        ResourceGroupsExportTime = 0
        ChildResourcesExportTime = 0
        APIVersionDiscoveryTime = 0
    }
    
    # Initialize telemetry properties
    $baseTelemetryProps = @{
        ExportId = $correlationContext.OperationId
        TriggerContext = $TriggerContext
        FunctionVersion = '1.2-WorkingADToken'
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        ARMApiVersion = 'dynamic'
        AuthMethod = 'Get-AzureADToken'
        ExportConfiguration = ($ExportConfiguration | ConvertTo-Json -Compress)
    }
    
    Write-Information "=== Azure Subscription Data Export Started ==="
    Write-Information "Export ID: $($correlationContext.OperationId)"
    Write-Information "Trigger Context: $TriggerContext"
    Write-Information "Authentication Method: Get-AzureADToken (proven working module)"
    Write-Information "Export Configuration: $($ExportConfiguration | ConvertTo-Json)"
    Write-Information "Start Time: $($exportStartTime.ToString('yyyy-MM-dd HH:mm:ss UTC'))"
    
    # Log export start event
    Write-CustomTelemetry -EventName "SubscriptionExportStarted" -Properties $baseTelemetryProps

    try {
        # Step 1: Authentication with Get-AzureADToken (working module)
        Write-Information "Step 1: Authenticating with Azure Resource Manager using Get-AzureADToken..."
        $authResult = Initialize-ARMAuthentication -BaseTelemetryProps $baseTelemetryProps
        
        if (-not $authResult.Success) {
            if ($authResult.IsFatal) {
                # Fatal errors should halt execution immediately
                Write-Error "EXPORT HALTED: Fatal authentication error detected."
                Write-Information "Export cannot proceed due to a fatal authentication error."
                Write-Information "No further processing will be attempted."
                
                # Create a specific fatal error result
                $fatalError = @{
                    ExportId = $correlationContext.OperationId
                    TriggerContext = $TriggerContext
                    ErrorMessage = $authResult.ErrorMessage
                    ErrorType = $authResult.ErrorType
                    IsFatal = $true
                    Timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                    FailureDurationMs = $authResult.DurationMs
                    Stage = "Authentication"
                    AuthMethod = "Get-AzureADToken"
                    RecommendedAction = if ($authResult.ErrorType -eq "PermissionError") {
                        "Grant Reader role to Managed Identity and wait up to 24 hours for RBAC propagation"
                    } else {
                        "Verify Managed Identity configuration and Function App settings"
                    }
                }
                
                Write-CustomTelemetry -EventName "SubscriptionExportFatalError" -Properties $fatalError
                
                return @{
                    Success = $false
                    ExportId = $correlationContext.OperationId
                    Error = $fatalError
                    FatalError = $true
                    Stage = "Authentication"
                    StartTime = $exportStartTime
                    EndTime = Get-Date
                }
            } else {
                # Non-fatal authentication errors
                throw "Authentication failed: $($authResult.ErrorMessage)"
            }
        }
        
        $authHeader = $authResult.AuthHeader
        $performanceMetrics.AuthenticationTime = $authResult.DurationMs
        
        Write-Information "✅ Authentication successful using Get-AzureADToken"

        # Step 2: API Version Discovery
        $apiVersionResult = Initialize-APIVersions -AuthHeader $authHeader -BaseTelemetryProps $baseTelemetryProps
        if (-not $apiVersionResult.Success) {
            throw "API version discovery failed: $($apiVersionResult.ErrorMessage)"
        }
        $azAPIVersions = $apiVersionResult.APIVersions
        $performanceMetrics.APIVersionDiscoveryTime = $apiVersionResult.DurationMs
        
        Write-Information "API version discovery completed - $($azAPIVersions.Count) resource types discovered"

        # Step 3: Resource Groups Export (if enabled)
        if ($ExportConfiguration.ResourceGroupDetails) {
            $resourceGroupsResult = Export-AzureResourceGroups -AuthHeader $authHeader -CorrelationContext $correlationContext -ResourceGroupFilter $ResourceGroupFilter -AzAPIVersions $azAPIVersions
            if (-not $resourceGroupsResult.Success) {
                throw "Resource groups export failed: $($resourceGroupsResult.Error.ErrorMessage)"
            }
            
            $performanceMetrics.ResourceGroupCount = $resourceGroupsResult.ResourceGroupCount
            $performanceMetrics.ResourceGroupsExportTime = $resourceGroupsResult.DurationMs
            $performanceMetrics.TotalEventHubBatches += $resourceGroupsResult.BatchCount
            
            Write-Information "Resource groups export completed - $($resourceGroupsResult.ResourceGroupCount) resource groups processed"
        }

        # Step 4: Subscription Resources Export
        $resourcesResult = Export-AzureSubscriptionResources -AuthHeader $authHeader -CorrelationContext $correlationContext -ExportConfiguration $ExportConfiguration -ResourceGroupFilter $ResourceGroupFilter -AzAPIVersions $azAPIVersions
        if (-not $resourcesResult.Success) {
            throw "Subscription resources export failed: $($resourcesResult.Error.ErrorMessage)"
        }
        
        $performanceMetrics.ResourceCount = $resourcesResult.ResourceCount
        $performanceMetrics.ResourcesExportTime = $resourcesResult.DurationMs
        $performanceMetrics.TotalEventHubBatches += $resourcesResult.BatchCount
        
        Write-Information "Subscription resources export completed - $($resourcesResult.ResourceCount) resources processed"

        # Step 5: Child Resources Export (if enabled and resources were found)
        if ($ExportConfiguration.IncludeChildResources -and $resourcesResult.ResourceCount -gt 0) {
            $childResourcesResult = Export-AzureChildResources -AuthHeader $authHeader -ParentResources $resourcesResult.AllResources -CorrelationContext $correlationContext -AzAPIVersions $azAPIVersions
            if (-not $childResourcesResult.Success) {
                throw "Child resources export failed: $($childResourcesResult.Error.ErrorMessage)"
            }
            
            $performanceMetrics.ChildResourceCount = $childResourcesResult.ChildResourceCount
            $performanceMetrics.ChildResourcesExportTime = $childResourcesResult.DurationMs
            $performanceMetrics.TotalEventHubBatches += $childResourcesResult.BatchCount
            
            Write-Information "Child resources export completed - $($childResourcesResult.ChildResourceCount) child resources processed"
        }

        # Calculate final metrics and log completion
        $exportEndTime = Get-Date
        $totalExportDuration = $exportEndTime - $exportStartTime
        $totalRecords = $performanceMetrics.ResourceCount + $performanceMetrics.ResourceGroupCount + $performanceMetrics.ChildResourceCount
        
        $completionResult = Complete-SubscriptionExport -PerformanceMetrics $performanceMetrics -ExportDuration $totalExportDuration -TotalRecords $totalRecords -BaseTelemetryProps $baseTelemetryProps
        
        Write-Information "=== Azure Subscription Data Export Completed Successfully ==="
        Write-Information "Export ID: $($correlationContext.OperationId)"
        Write-Information "Duration: $($totalExportDuration.ToString('hh\:mm\:ss'))"
        Write-Information "Total Records: $totalRecords"
        
        return @{
            Success = $true
            ExportId = $correlationContext.OperationId
            Statistics = $completionResult.Statistics
            StartTime = $exportStartTime
            EndTime = $exportEndTime
            ModularArchitecture = $true
            ARMApiVersion = "dynamic"
            AuthMethod = "Get-AzureADToken"
        }
        
    }
    catch {
        # Single-level error handling for non-fatal errors
        $exportEndTime = Get-Date
        $failureDuration = $exportEndTime - $exportStartTime
        $errorMessage = $_.Exception.Message
        $errorType = Get-ErrorType -Exception $_
        
        $errorDetails = @{
            ExportId = $correlationContext.OperationId
            TriggerContext = $TriggerContext
            ErrorMessage = $errorMessage
            ErrorType = $errorType
            IsFatal = $false
            Timestamp = $exportEndTime.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            PartialStatistics = $performanceMetrics
            FailureDurationMs = $failureDuration.TotalMilliseconds
            ModularArchitecture = $true
            ARMApiVersion = "dynamic"
            AuthMethod = "Get-AzureADToken"
        }
        
        Write-CustomTelemetry -EventName "SubscriptionExportFailed" -Properties $errorDetails
        
        Write-Error "=== Azure Subscription Data Export Failed ==="
        Write-Error "Export ID: $($correlationContext.OperationId)"
        Write-Error "Error: $errorMessage"
        Write-Error "Duration before failure: $($failureDuration.ToString('hh\:mm\:ss'))"
        
        return @{
            Success = $false
            ExportId = $correlationContext.OperationId
            Error = $errorDetails
            PartialStatistics = $performanceMetrics
            ModularArchitecture = $true
            ARMApiVersion = "dynamic"
            AuthMethod = "Get-AzureADToken"
            StartTime = $exportStartTime
            EndTime = $exportEndTime
        }
    }
}

# Helper function for ARM authentication initialization - USING WORKING GET-AZUREADTOKEN
function Initialize-ARMAuthentication {
    [CmdletBinding()]
    param (
        [hashtable]$BaseTelemetryProps
    )
    
    $authStartTime = Get-Date
    $result = @{ 
        Success = $false
        AuthHeader = $null
        DurationMs = 0
        ErrorMessage = ""
        ErrorType = "Unknown"
        IsFatal = $false
    }
    
    try {
        Write-Information "Acquiring Azure Resource Manager authentication token using Get-AzureADToken..."
        
        $tokenProps = $BaseTelemetryProps.Clone()
        $tokenProps['Resource'] = 'https://management.azure.com'
        $tokenProps['AuthMethod'] = 'Get-AzureADToken'
        
        # Use the known working Get-AzureADToken function instead of Get-AzureARMToken
        Write-Information "Using Get-AzureADToken for ARM authentication..."
        $token = Get-AzureADToken -resource "https://management.azure.com" -clientId $env:ClientId
        
        if (-not $token) {
            throw "Get-AzureADToken returned null or empty token"
        }
        
        $result.AuthHeader = @{
            'Authorization' = "Bearer $token"
            'Content-Type' = 'application/json'
        }
        $result.Success = $true
        $result.DurationMs = ((Get-Date) - $authStartTime).TotalMilliseconds
        
        Write-Information "ARM authentication successful using Get-AzureADToken"
    }
    catch [System.Net.WebException] {
        # Handle web exceptions from Get-AzureADToken
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        
        $result.DurationMs = ((Get-Date) - $authStartTime).TotalMilliseconds
        
        # Handle specific HTTP status codes
        switch ($statusCode) {
            403 {
                # 403 Forbidden - This is a permissions/RBAC issue, not a transient error
                $result.ErrorMessage = "RBAC Permission Error (403 Forbidden): The Managed Identity does not have sufficient permissions to access the subscription. Please ensure the User-Assigned Managed Identity has been granted at least 'Reader' role on the target subscription. Note: RBAC permission changes can take up to 24 hours to propagate in Azure."
                $result.ErrorType = "PermissionError"
                $result.IsFatal = $true
                
                Write-Error "FATAL PERMISSION ERROR: Authentication failed due to insufficient permissions."
                Write-Error "Details: $($_.Exception.Message)"
                Write-Information "=========================================="
                Write-Information "🚨 RBAC PERMISSION ERROR DETECTED 🚨"
                Write-Information "=========================================="
                Write-Information "This is a FATAL error that requires manual intervention."
                Write-Information ""
                Write-Information "CAUSE: The User-Assigned Managed Identity does not have sufficient"
                Write-Information "       permissions to access the target Azure subscription."
                Write-Information ""
                Write-Information "RESOLUTION REQUIRED:"
                Write-Information "1. Grant the Managed Identity 'Reader' role on the subscription"
                Write-Information "2. Wait up to 24 hours for RBAC changes to propagate"
                Write-Information "3. Retry the operation after permissions are active"
                Write-Information ""
                Write-Information "TARGET SUBSCRIPTION: $($env:SUBSCRIPTION_ID)"
                Write-Information "MANAGED IDENTITY: $($env:CLIENTID)"
                Write-Information "=========================================="
                
                # Log specific telemetry for permission errors
                $permissionErrorProps = $BaseTelemetryProps.Clone()
                $permissionErrorProps['ErrorType'] = 'RBACPermissionError'
                $permissionErrorProps['ErrorMessage'] = $result.ErrorMessage
                $permissionErrorProps['IsFatal'] = $true
                $permissionErrorProps['TargetSubscription'] = $env:SUBSCRIPTION_ID
                $permissionErrorProps['ManagedIdentityClientId'] = $env:CLIENTID
                $permissionErrorProps['AuthMethod'] = 'Get-AzureADToken'
                $permissionErrorProps['RecommendedAction'] = 'Grant Reader role to Managed Identity on target subscription'
                $permissionErrorProps['ExpectedResolutionTime'] = 'Up to 24 hours for RBAC propagation'
                
                Write-CustomTelemetry -EventName "AuthenticationPermissionError" -Properties $permissionErrorProps
            }
            
            401 {
                # 401 Unauthorized - Authentication configuration issue
                $result.ErrorMessage = "Authentication Error (401 Unauthorized): The Managed Identity configuration is invalid or the identity does not exist. Please verify the User-Assigned Managed Identity is properly configured and exists."
                $result.ErrorType = "ConfigurationError"
                $result.IsFatal = $true
                
                Write-Error "FATAL CONFIGURATION ERROR: $($result.ErrorMessage)"
                Write-Information "=========================================="
                Write-Information "🚨 CONFIGURATION ERROR DETECTED 🚨"
                Write-Information "=========================================="
                Write-Information "This is a FATAL error that requires manual intervention."
                Write-Information ""
                Write-Information "CAUSE: The Managed Identity or Function App configuration is invalid."
                Write-Information ""
                Write-Information "RESOLUTION REQUIRED:"
                Write-Information "1. Verify the User-Assigned Managed Identity exists"
                Write-Information "2. Check Function App identity configuration"
                Write-Information "3. Verify environment variables are correctly set"
                Write-Information "=========================================="
                
                # Log specific telemetry for configuration errors
                $configErrorProps = $BaseTelemetryProps.Clone()
                $configErrorProps['ErrorType'] = 'ManagedIdentityConfigError'
                $configErrorProps['ErrorMessage'] = $result.ErrorMessage
                $configErrorProps['IsFatal'] = $true
                $configErrorProps['AuthMethod'] = 'Get-AzureADToken'
                $configErrorProps['RecommendedAction'] = 'Verify Managed Identity configuration and Function App settings'
                
                Write-CustomTelemetry -EventName "AuthenticationConfigurationError" -Properties $configErrorProps
            }
            
            default {
                # Other HTTP errors - may be transient, allow retry
                $result.ErrorMessage = "HTTP $statusCode error from Get-AzureADToken: $($_.Exception.Message)"
                $result.ErrorType = "TransientError"
                $result.IsFatal = $false
                
                Write-Warning "Authentication error (potentially transient): $($result.ErrorMessage)"
            }
        }
    }
    catch {
        # Other exceptions from Get-AzureADToken
        $result.ErrorMessage = "Get-AzureADToken failed: $($_.Exception.Message)"
        $result.ErrorType = "AuthenticationError"
        $result.IsFatal = $false  # Assume non-fatal unless we know otherwise
        $result.DurationMs = ((Get-Date) - $authStartTime).TotalMilliseconds
        
        # Check if this looks like a permission error based on message content
        if ($_.Exception.Message -match "403|Forbidden|permission|access.*denied") {
            $result.ErrorType = "PermissionError"
            $result.IsFatal = $true
            $result.ErrorMessage = "Permission Error: $($_.Exception.Message). The Managed Identity may not have sufficient permissions on the target subscription."
            
            Write-Error "FATAL PERMISSION ERROR: $($result.ErrorMessage)"
        } else {
            Write-Warning "Authentication error: $($result.ErrorMessage)"
        }
        
        # Log generic authentication error
        $authErrorProps = $BaseTelemetryProps.Clone()
        $authErrorProps['ErrorType'] = $result.ErrorType
        $authErrorProps['ErrorMessage'] = $result.ErrorMessage
        $authErrorProps['IsFatal'] = $result.IsFatal
        $authErrorProps['AuthMethod'] = 'Get-AzureADToken'
        
        Write-CustomTelemetry -EventName "AuthenticationError" -Properties $authErrorProps
    }
    
    return $result
}

# Helper function for API version discovery initialization
function Initialize-APIVersions {
    [CmdletBinding()]
    param (
        [hashtable]$AuthHeader,
        [hashtable]$BaseTelemetryProps
    )
    
    $apiVersionStartTime = Get-Date
    $result = @{ Success = $false; APIVersions = @{}; DurationMs = 0; ErrorMessage = "" }
    
    try {
        Write-Information "Discovering Azure API versions..."
        
        $versionProps = $BaseTelemetryProps.Clone()
        $versionProps['Operation'] = 'APIVersionDiscovery'
        
        $apiVersionScriptBlock = {
            Get-AzureAPIVersions -AuthHeader $AuthHeader -SubscriptionId $env:SUBSCRIPTION_ID
        }
        
        $result.APIVersions = Invoke-WithRetry -ScriptBlock $apiVersionScriptBlock -MaxRetryCount 2 -OperationName "GetAPIVersions" -TelemetryProperties $versionProps
        $result.Success = $true
        $result.DurationMs = ((Get-Date) - $apiVersionStartTime).TotalMilliseconds
    }
    catch {
        $result.ErrorMessage = $_.Exception.Message
        $result.DurationMs = ((Get-Date) - $apiVersionStartTime).TotalMilliseconds
    }
    
    return $result
}

# Helper function for export completion and metrics
function Complete-SubscriptionExport {
    [CmdletBinding()]
    param (
        [hashtable]$PerformanceMetrics,
        [TimeSpan]$ExportDuration,
        [int]$TotalRecords,
        [hashtable]$BaseTelemetryProps
    )
    
    # Calculate performance metrics
    $completionMetrics = @{
        ExecutionDurationMinutes = [Math]::Round($ExportDuration.TotalMinutes, 2)
        RecordsPerMinute = if ($ExportDuration.TotalMinutes -gt 0) { [Math]::Round($TotalRecords / $ExportDuration.TotalMinutes, 0) } else { 0 }
        EventHubBatchesPerMinute = if ($ExportDuration.TotalMinutes -gt 0) { [Math]::Round($PerformanceMetrics.TotalEventHubBatches / $ExportDuration.TotalMinutes, 2) } else { 0 }
    }
    
    # Final telemetry properties
    $completionProps = $BaseTelemetryProps.Clone()
    $completionProps['ResourceCount'] = $PerformanceMetrics.ResourceCount
    $completionProps['ResourceGroupCount'] = $PerformanceMetrics.ResourceGroupCount
    $completionProps['ChildResourceCount'] = $PerformanceMetrics.ChildResourceCount
    $completionProps['TotalRecords'] = $TotalRecords
    $completionProps['TotalEventHubBatches'] = $PerformanceMetrics.TotalEventHubBatches
    $completionProps['TotalExecutionTimeMs'] = $ExportDuration.TotalMilliseconds
    
    Write-CustomTelemetry -EventName "SubscriptionExportCompleted" -Properties $completionProps -Metrics $completionMetrics
    
    return @{
        Statistics = @{
            Resources = $PerformanceMetrics.ResourceCount
            ResourceGroups = $PerformanceMetrics.ResourceGroupCount
            ChildResources = $PerformanceMetrics.ChildResourceCount
            TotalRecords = $TotalRecords
            EventHubBatches = $PerformanceMetrics.TotalEventHubBatches
            Duration = $ExportDuration.TotalMinutes
            Performance = $completionMetrics
            StageTimings = @{
                Authentication = [Math]::Round($PerformanceMetrics.AuthenticationTime / 1000, 2)
                APIVersionDiscovery = [Math]::Round($PerformanceMetrics.APIVersionDiscoveryTime / 1000, 2)
                ResourcesExport = [Math]::Round($PerformanceMetrics.ResourcesExportTime / 1000, 2)
                ResourceGroupsExport = [Math]::Round($PerformanceMetrics.ResourceGroupsExportTime / 1000, 2)
                ChildResourcesExport = [Math]::Round($PerformanceMetrics.ChildResourcesExportTime / 1000, 2)
            }
        }
    }
}
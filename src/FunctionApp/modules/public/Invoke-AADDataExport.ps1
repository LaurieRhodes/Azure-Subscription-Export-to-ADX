<#
.SYNOPSIS
    Orchestrates the complete Azure AD data export process using modular components.

.DESCRIPTION
    This function coordinates the export of Azure AD data (Users, Groups, Memberships) 
    to Azure Data Explorer via Event Hub. It provides comprehensive telemetry, 
    performance monitoring, and structured error handling.

.PARAMETER TriggerContext
    Context information from the calling trigger (Timer, HTTP, etc.).

.PARAMETER IncludeExtendedUserProperties
    Switch to include extended user properties that require individual API calls.

.NOTES
    Author: Laurie Rhodes
    Version: 3.0
    Last Modified: 2025-08-31
    
    Key Features:
    - Modular architecture with separate export functions
    - Production v1.0 Graph API endpoints exclusively
    - Streamlined error handling without nested catch blocks
    - Comprehensive performance monitoring and telemetry
#>

function Invoke-AADDataExport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$TriggerContext = "Unknown",
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeExtendedUserProperties = $false
    )

    # Initialize execution tracking
    $correlationContext = New-CorrelationContext -OperationName "AADDataExport"
    $exportStartTime = Get-Date
    
    # Initialize performance metrics
    $performanceMetrics = @{
        UserCount = 0
        UserExtendedCount = 0
        GroupCount = 0
        MembershipCount = 0
        TotalEventHubBatches = 0
        AuthenticationTime = 0
        UsersExportTime = 0
        GroupsExportTime = 0
        MembershipsExportTime = 0
    }
    
    # Initialize telemetry properties
    $baseTelemetryProps = @{
        ExportId = $correlationContext.OperationId
        TriggerContext = $TriggerContext
        FunctionVersion = '3.0'
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        GraphApiVersion = 'v1.0'
        ExtendedUserProperties = $IncludeExtendedUserProperties.IsPresent
    }
    
    Write-Information "=== AAD Data Export Started ==="
    Write-Information "Export ID: $($correlationContext.OperationId)"
    Write-Information "Trigger Context: $TriggerContext"
    Write-Information "Extended Properties: $($IncludeExtendedUserProperties.IsPresent)"
    Write-Information "Start Time: $($exportStartTime.ToString('yyyy-MM-dd HH:mm:ss UTC'))"
    
    # Log export start event
    Write-CustomTelemetry -EventName "AADExportStarted" -Properties $baseTelemetryProps

    try {
        # Step 1: Authentication
        $authResult = Initialize-GraphAuthentication -BaseTelemetryProps $baseTelemetryProps
        if (-not $authResult.Success) {
            throw "Authentication failed: $($authResult.ErrorMessage)"
        }
        $authHeader = $authResult.AuthHeader
        $performanceMetrics.AuthenticationTime = $authResult.DurationMs
        
        Write-Information "Authentication successful"

        # Step 2: Users Export
        $usersResult = Export-AADUsers -AuthHeader $authHeader -CorrelationContext $correlationContext -IncludeExtendedProperties:$IncludeExtendedUserProperties
        if (-not $usersResult.Success) {
            throw "Users export failed: $($usersResult.Error.ErrorMessage)"
        }
        
        $performanceMetrics.UserCount = $usersResult.UserCount
        $performanceMetrics.UserExtendedCount = $usersResult.ExtendedPropertiesCount
        $performanceMetrics.UsersExportTime = $usersResult.DurationMs
        $performanceMetrics.TotalEventHubBatches += $usersResult.BatchCount
        
        Write-Information "Users export completed - $($usersResult.UserCount) users processed"

        # Step 3: Groups Export
        $groupsResult = Export-AADGroups -AuthHeader $authHeader -CorrelationContext $correlationContext
        if (-not $groupsResult.Success) {
            throw "Groups export failed: $($groupsResult.Error.ErrorMessage)"
        }
        
        $performanceMetrics.GroupCount = $groupsResult.GroupCount
        $performanceMetrics.GroupsExportTime = $groupsResult.DurationMs
        $performanceMetrics.TotalEventHubBatches += $groupsResult.BatchCount
        $allGroupIDs = $groupsResult.AllGroupIDs
        
        Write-Information "Groups export completed - $($groupsResult.GroupCount) groups processed"

        # Step 4: Group Memberships Export
        $membershipsInfo = @{ GroupSuccessRate = 100; FailedGroups = 0 }
        
        if ($allGroupIDs.Count -gt 0) {
            $membershipsResult = Export-AADGroupMemberships -AuthHeader $authHeader -GroupIDs $allGroupIDs -CorrelationContext $correlationContext
            if (-not $membershipsResult.Success) {
                throw "Group memberships export failed: $($membershipsResult.Error.ErrorMessage)"
            }
            
            $performanceMetrics.MembershipCount = $membershipsResult.MembershipCount
            $performanceMetrics.MembershipsExportTime = $membershipsResult.DurationMs
            $performanceMetrics.TotalEventHubBatches += $membershipsResult.BatchCount
            
            # Extract membership stats consistently
            $membershipsInfo.GroupSuccessRate = if ($membershipsResult.GroupSuccessRate) { $membershipsResult.GroupSuccessRate } else { 100 }
            $membershipsInfo.FailedGroups = if ($membershipsResult.FailedGroups) { $membershipsResult.FailedGroups } else { 0 }
            
            Write-Information "Group memberships export completed - $($membershipsResult.MembershipCount) memberships processed"
        }
        else {
            Write-Information "No groups found - skipping group memberships export"
        }

        # Calculate final metrics and log completion
        $exportEndTime = Get-Date
        $totalExportDuration = $exportEndTime - $exportStartTime
        $totalRecords = $performanceMetrics.UserCount + $performanceMetrics.GroupCount + $performanceMetrics.MembershipCount
        
        $completionResult = Complete-AADExport -PerformanceMetrics $performanceMetrics -ExportDuration $totalExportDuration -TotalRecords $totalRecords -BaseTelemetryProps $baseTelemetryProps -MembershipsResult $membershipsInfo
        
        Write-Information "=== AAD Data Export Completed Successfully ==="
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
            GraphApiVersion = "v1.0"
        }
        
    }
    catch {
        # Single-level error handling - no nested catch blocks
        $exportEndTime = Get-Date
        $failureDuration = $exportEndTime - $exportStartTime
        $errorMessage = $_.Exception.Message
        $errorType = Get-ErrorType -Exception $_
        
        $errorDetails = @{
            ExportId = $correlationContext.OperationId
            TriggerContext = $TriggerContext
            ErrorMessage = $errorMessage
            ErrorType = $errorType
            Timestamp = $exportEndTime.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            PartialStatistics = $performanceMetrics
            FailureDurationMs = $failureDuration.TotalMilliseconds
            ModularArchitecture = $true
            GraphApiVersion = "v1.0"
        }
        
        Write-CustomTelemetry -EventName "AADExportFailed" -Properties $errorDetails
        
        Write-Error "=== AAD Data Export Failed ==="
        Write-Error "Export ID: $($correlationContext.OperationId)"
        Write-Error "Error: $errorMessage"
        Write-Error "Duration before failure: $($failureDuration.ToString('hh\:mm\:ss'))"
        
        return @{
            Success = $false
            ExportId = $correlationContext.OperationId
            Error = $errorDetails
            PartialStatistics = $performanceMetrics
            ModularArchitecture = $true
            GraphApiVersion = "v1.0"
        }
    }
}

# Helper function for authentication initialization
function Initialize-GraphAuthentication {
    [CmdletBinding()]
    param (
        [hashtable]$BaseTelemetryProps
    )
    
    $authStartTime = Get-Date
    $result = @{ Success = $false; AuthHeader = $null; DurationMs = 0; ErrorMessage = "" }
    
    try {
        Write-Information "Acquiring Microsoft Graph authentication token..."
        
        $tokenProps = $BaseTelemetryProps.Clone()
        $tokenProps['Resource'] = 'https://graph.microsoft.com'
        
        $authScriptBlock = {
            Get-AzureADToken -resource "https://graph.microsoft.com" -clientId $env:ClientId
        }
        
        $token = Invoke-WithRetry -ScriptBlock $authScriptBlock -MaxRetryCount 2 -OperationName "GetGraphToken" -TelemetryProperties $tokenProps
        
        $result.AuthHeader = @{
            'Authorization' = "Bearer $token"
            'ConsistencyLevel' = 'eventual'
        }
        $result.Success = $true
        $result.DurationMs = ((Get-Date) - $authStartTime).TotalMilliseconds
    }
    catch {
        $result.ErrorMessage = $_.Exception.Message
        $result.DurationMs = ((Get-Date) - $authStartTime).TotalMilliseconds
    }
    
    return $result
}

# Helper function for export completion and metrics
function Complete-AADExport {
    [CmdletBinding()]
    param (
        [hashtable]$PerformanceMetrics,
        [TimeSpan]$ExportDuration,
        [int]$TotalRecords,
        [hashtable]$BaseTelemetryProps,
        [hashtable]$MembershipsResult
    )
    
    # Calculate performance metrics
    $completionMetrics = @{
        ExecutionDurationMinutes = [Math]::Round($ExportDuration.TotalMinutes, 2)
        RecordsPerMinute = if ($ExportDuration.TotalMinutes -gt 0) { [Math]::Round($TotalRecords / $ExportDuration.TotalMinutes, 0) } else { 0 }
        EventHubBatchesPerMinute = if ($ExportDuration.TotalMinutes -gt 0) { [Math]::Round($PerformanceMetrics.TotalEventHubBatches / $ExportDuration.TotalMinutes, 2) } else { 0 }
    }
    
    # Final telemetry properties
    $completionProps = $BaseTelemetryProps.Clone()
    $completionProps['UserCount'] = $PerformanceMetrics.UserCount
    $completionProps['UserExtendedCount'] = $PerformanceMetrics.UserExtendedCount
    $completionProps['GroupCount'] = $PerformanceMetrics.GroupCount
    $completionProps['MembershipCount'] = $PerformanceMetrics.MembershipCount
    $completionProps['TotalRecords'] = $TotalRecords
    $completionProps['TotalEventHubBatches'] = $PerformanceMetrics.TotalEventHubBatches
    $completionProps['TotalExecutionTimeMs'] = $ExportDuration.TotalMilliseconds
    $completionProps['GroupSuccessRate'] = $MembershipsResult.GroupSuccessRate
    $completionProps['FailedGroupCount'] = $MembershipsResult.FailedGroups
    
    Write-CustomTelemetry -EventName "AADExportCompleted" -Properties $completionProps -Metrics $completionMetrics
    
    return @{
        Statistics = @{
            Users = $PerformanceMetrics.UserCount
            UsersExtended = $PerformanceMetrics.UserExtendedCount
            Groups = $PerformanceMetrics.GroupCount
            Memberships = $PerformanceMetrics.MembershipCount
            TotalRecords = $TotalRecords
            EventHubBatches = $PerformanceMetrics.TotalEventHubBatches
            Duration = $ExportDuration.TotalMinutes
            GroupSuccessRate = $MembershipsResult.GroupSuccessRate
            FailedGroups = $MembershipsResult.FailedGroups
            Performance = $completionMetrics
            StageTimings = @{
                Authentication = [Math]::Round($PerformanceMetrics.AuthenticationTime / 1000, 2)
                UsersExport = [Math]::Round($PerformanceMetrics.UsersExportTime / 1000, 2)
                GroupsExport = [Math]::Round($PerformanceMetrics.GroupsExportTime / 1000, 2)
                MembershipsExport = [Math]::Round($PerformanceMetrics.MembershipsExportTime / 1000, 2)
            }
        }
    }
}
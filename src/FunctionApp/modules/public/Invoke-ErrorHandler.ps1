<#
.SYNOPSIS
    Provides comprehensive error handling functions for AAD Export operations.

.DESCRIPTION
    This module implements enterprise-grade error handling patterns for Azure Functions
    with Application Insights integration. All functions use single-level error handling
    without nested catch blocks for cleaner, more maintainable code.

.NOTES
    Author: Laurie Rhodes
    Version: 3.0
    Last Modified: 2025-08-31
    
    Key Features:
    - Single-level error handling (no nested catch blocks)
    - Comprehensive telemetry integration
    - Structured exception tracking
    - Performance monitoring and metrics
#>

function Invoke-WithRetry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxRetryCount = 3,
        
        [Parameter(Mandatory = $false)]
        [int]$InitialDelaySeconds = 2,
        
        [Parameter(Mandatory = $false)]
        [string]$OperationName = "Unknown",
        
        [Parameter(Mandatory = $false)]
        [hashtable]$TelemetryProperties = @{}
    )
    
    $attempt = 0
    $lastException = $null
    
    # Add operation context to telemetry
    $telemetryProps = $TelemetryProperties.Clone()
    $telemetryProps['OperationName'] = $OperationName
    $telemetryProps['MaxRetryCount'] = $MaxRetryCount
    
    while ($attempt -le $MaxRetryCount) {
        $attempt++
        $telemetryProps['AttemptNumber'] = $attempt
        
        # Initialize timing and error tracking
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $operationFailed = $false
        $errorType = ""
        $shouldRetry = $false
        
        try {
            Write-Information "Executing $OperationName (attempt $attempt of $($MaxRetryCount + 1))"
            
            # Execute the operation
            $result = & $ScriptBlock
            
            # Operation succeeded
            $stopwatch.Stop()
            Write-Information "$OperationName completed successfully on attempt $attempt"
            
            # Log success telemetry
            $successProps = $telemetryProps.Clone()
            $successProps['Result'] = 'Success'
            $successProps['DurationMs'] = $stopwatch.ElapsedMilliseconds
            $successProps['AttemptsRequired'] = $attempt
            
            Write-Information "TELEMETRY_EVENT: OperationSuccess|$($successProps | ConvertTo-Json -Compress)"
            
            return $result
            
        }
        catch {
            # Operation failed - handle error outside try block
            $stopwatch.Stop()
            $lastException = $_
            $operationFailed = $true
            $errorType = Get-ErrorType -Exception $_
            $shouldRetry = $attempt -lt ($MaxRetryCount + 1) -and (Test-ShouldRetry -Exception $_ -ErrorType $errorType)
        }
        
        # Handle failure outside of catch block (single-level error handling)
        if ($operationFailed) {
            $delay = [Math]::Min([Math]::Pow(2, $attempt - 1) * $InitialDelaySeconds, 60)
            
            # Create error telemetry
            $errorProps = $telemetryProps.Clone()
            $errorProps['Result'] = 'Error'
            $errorProps['ErrorType'] = $errorType
            $errorProps['ErrorMessage'] = $lastException.Exception.Message
            $errorProps['HttpStatusCode'] = Get-HttpStatusCode -Exception $lastException
            $errorProps['ShouldRetry'] = $shouldRetry
            $errorProps['DelaySeconds'] = $delay
            $errorProps['DurationMs'] = $stopwatch.ElapsedMilliseconds
            
            if ($shouldRetry) {
                Write-Warning "$OperationName failed on attempt $attempt - will retry after $delay seconds"
                Write-Warning "Error: $($lastException.Exception.Message)"
                
                Write-Information "TELEMETRY_EVENT: OperationRetry|$($errorProps | ConvertTo-Json -Compress)"
                Start-Sleep -Seconds $delay
            }
            else {
                Write-Error "$OperationName failed permanently after $attempt attempts"
                Write-Error "Final error: $($lastException.Exception.Message)"
                
                Write-Information "TELEMETRY_EVENT: OperationFailure|$($errorProps | ConvertTo-Json -Compress)"
                Write-Information "TELEMETRY_EXCEPTION: $($lastException.Exception.GetType().Name)|$($lastException.Exception.Message)|$($errorProps | ConvertTo-Json -Compress)"
                
                throw $lastException
            }
        }
    }
}

function Invoke-GraphAPIWithRetry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,
        
        [Parameter(Mandatory = $false)]
        [string]$Method = "GET",
        
        [Parameter(Mandatory = $false)]
        [hashtable]$CorrelationContext = @{},
        
        [Parameter(Mandatory = $false)]
        [int]$MaxRetryCount = 3
    )
    
    $operationName = "GraphAPI-$($Uri -replace 'https://graph\.microsoft\.com/[^/]+/', '' -replace '\?.*$', '')"
    
    # Add correlation properties
    $telemetryProps = $CorrelationContext.Clone()
    $telemetryProps['Uri'] = $Uri
    $telemetryProps['Method'] = $Method
    $telemetryProps['UserAgent'] = 'AAD-Export-Function/3.0'
    
    $scriptBlock = {
        # Start dependency timing
        $dependencyStart = Get-Date
        $dependencySuccess = $false
        $response = $null
        
        try {
            $response = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method
            $dependencySuccess = $true
        }
        catch {
            $dependencySuccess = $false
            throw
        }
        finally {
            # Log dependency telemetry regardless of outcome
            $dependencyDuration = ((Get-Date) - $dependencyStart).TotalMilliseconds
            Write-DependencyTelemetry -DependencyName "Microsoft Graph API" -Target $Uri -DurationMs $dependencyDuration -Success $dependencySuccess -Properties $telemetryProps
        }
        
        return $response
    }
    
    # Execute with retry logic
    return Invoke-WithRetry -ScriptBlock $scriptBlock -MaxRetryCount $MaxRetryCount -OperationName $operationName -TelemetryProperties $telemetryProps
}

function Write-CustomTelemetry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$EventName,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Properties = @{},
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Metrics = @{}
    )
    
    try {
        # Create structured telemetry event for Application Insights
        $telemetryEvent = @{
            EventName = $EventName
            Timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            Properties = $Properties
            Metrics = $Metrics
        }
        
        # Write as structured log for Application Insights to capture
        Write-Information "CUSTOM_TELEMETRY: $($telemetryEvent | ConvertTo-Json -Compress)"
    }
    catch {
        Write-Warning "Failed to write custom telemetry for event '$EventName': $($_.Exception.Message)"
    }
}

function Write-DependencyTelemetry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$DependencyName,
        
        [Parameter(Mandatory = $true)]
        [string]$Target,
        
        [Parameter(Mandatory = $true)]
        [long]$DurationMs,
        
        [Parameter(Mandatory = $true)]
        [bool]$Success,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Properties = @{}
    )
    
    try {
        $dependencyEvent = @{
            DependencyName = $DependencyName
            Target = $Target
            Duration = $DurationMs
            Success = $Success
            Timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            Properties = $Properties
        }
        
        # Write dependency telemetry for Application Insights
        Write-Information "DEPENDENCY_TELEMETRY: $($dependencyEvent | ConvertTo-Json -Compress)"
    }
    catch {
        Write-Warning "Failed to write dependency telemetry for '$DependencyName': $($_.Exception.Message)"
    }
}

function New-CorrelationContext {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$OperationId = [System.Guid]::NewGuid().ToString(),
        
        [Parameter(Mandatory = $false)]
        [string]$OperationName = "AADDataExport"
    )
    
    return @{
        OperationId = $OperationId
        OperationName = $OperationName
        ParentId = $null
        StartTime = Get-Date
    }
}

function Write-ExportProgress {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Stage,
        
        [Parameter(Mandatory = $true)]
        [int]$ProcessedCount,
        
        [Parameter(Mandatory = $false)]
        [int]$TotalCount = 0,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$CorrelationContext = @{}
    )
    
    $progressProps = $CorrelationContext.Clone()
    $progressProps['Stage'] = $Stage
    $progressProps['ProcessedCount'] = $ProcessedCount
    $progressProps['TotalCount'] = $TotalCount
    
    if ($TotalCount -gt 0) {
        $progressProps['PercentComplete'] = [Math]::Round(($ProcessedCount / $TotalCount) * 100, 2)
        $progressMessage = "$Stage - Progress: $ProcessedCount of $TotalCount ($($progressProps['PercentComplete'])%)"
    }
    else {
        $progressMessage = "$Stage - Processed: $ProcessedCount records"
    }
    
    # Write progress telemetry
    Write-CustomTelemetry -EventName "ExportProgress" -Properties $progressProps
    Write-Information $progressMessage
}
<#
.SYNOPSIS
    Writes custom telemetry events for monitoring and analytics.

.DESCRIPTION
    Sends custom telemetry events to Application Insights or other monitoring systems.
    Provides structured logging for tracking export operations and performance.

.PARAMETER EventName
    The name of the telemetry event.

.PARAMETER Properties
    Hashtable of properties to include with the event.

.PARAMETER Metrics
    Hashtable of metrics to include with the event.

.NOTES
    Author: Laurie Rhodes
    Version: 1.0
    Last Modified: 2025-01-31
#>

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
        # Create telemetry message
        $telemetryData = @{
            EventName = $EventName
            Timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
            Properties = $Properties
            Metrics = $Metrics
        }
        
        # Log as structured information (Application Insights will pick this up)
        $telemetryJson = $telemetryData | ConvertTo-Json -Compress
        Write-Information "TELEMETRY: $telemetryJson"
        
        # Also log key details for easy reading
        Write-Information "Event: $EventName"
        if ($Properties.Count -gt 0) {
            $Properties.GetEnumerator() | ForEach-Object {
                Write-Debug "  Property: $($_.Key) = $($_.Value)"
            }
        }
        if ($Metrics.Count -gt 0) {
            $Metrics.GetEnumerator() | ForEach-Object {
                Write-Debug "  Metric: $($_.Key) = $($_.Value)"
            }
        }
    }
    catch {
        Write-Warning "Failed to write custom telemetry: $($_.Exception.Message)"
    }
}
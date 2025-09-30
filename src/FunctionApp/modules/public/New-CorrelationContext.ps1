<#
.SYNOPSIS
    Creates a correlation context for tracking operations across the export process.

.DESCRIPTION
    Generates a correlation context object with operation ID and timing information
    for tracking and telemetry purposes.

.PARAMETER OperationName
    The name of the operation being tracked.

.NOTES
    Author: Laurie Rhodes
    Version: 1.0
    Last Modified: 2025-01-31
#>

function New-CorrelationContext {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$OperationName
    )
    
    $operationId = [System.Guid]::NewGuid().ToString()
    $startTime = Get-Date
    
    return @{
        OperationId = $operationId
        OperationName = $OperationName
        StartTime = $startTime
        Timestamp = $startTime.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    }
}
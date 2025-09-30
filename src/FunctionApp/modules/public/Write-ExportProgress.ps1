<#
.SYNOPSIS
    Writes export progress information for monitoring long-running operations.

.DESCRIPTION
    Provides progress updates during export operations to help with monitoring
    and troubleshooting of long-running subscription exports.

.PARAMETER Current
    Current number of items processed.

.PARAMETER Total
    Total number of items to process.

.PARAMETER OperationType
    Type of operation being performed.

.NOTES
    Author: Laurie Rhodes
    Version: 1.0
    Last Modified: 2025-01-31
#>

function Write-ExportProgress {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [int]$Current,
        
        [Parameter(Mandatory = $true)]
        [int]$Total,
        
        [Parameter(Mandatory = $true)]
        [string]$OperationType
    )
    
    try {
        $percentComplete = if ($Total -gt 0) { [Math]::Round(($Current / $Total) * 100, 1) } else { 0 }
        
        Write-Information "Progress: $OperationType - $Current/$Total ($percentComplete%)"
        
        # Log progress milestones
        if ($percentComplete -in @(25, 50, 75, 90, 100)) {
            Write-Information "MILESTONE: $OperationType reached $percentComplete% completion"
        }
    }
    catch {
        Write-Debug "Failed to write progress: $($_.Exception.Message)"
    }
}
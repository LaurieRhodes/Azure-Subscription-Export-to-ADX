<#
.SYNOPSIS
    Executes a script block with retry logic for improved resilience.

.DESCRIPTION
    Retries a script block execution with exponential backoff for handling
    transient failures in Azure API calls and other operations.

.PARAMETER ScriptBlock
    The script block to execute.

.PARAMETER MaxRetryCount
    Maximum number of retry attempts.

.PARAMETER OperationName
    Name of the operation for logging purposes.

.PARAMETER TelemetryProperties
    Additional telemetry properties.

.NOTES
    Author: Laurie Rhodes
    Version: 1.0
    Last Modified: 2025-01-31
#>

function Invoke-WithRetry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxRetryCount = 3,
        
        [Parameter(Mandatory = $false)]
        [string]$OperationName = "Operation",
        
        [Parameter(Mandatory = $false)]
        [hashtable]$TelemetryProperties = @{}
    )
    
    $attempt = 0
    $lastException = $null
    
    do {
        $attempt++
        
        try {
            Write-Debug "Executing $OperationName (attempt $attempt/$($MaxRetryCount + 1))"
            $result = & $ScriptBlock
            
            if ($attempt -gt 1) {
                Write-Information "$OperationName succeeded on attempt $attempt"
            }
            
            return $result
        }
        catch {
            $lastException = $_
            Write-Warning "$OperationName failed on attempt $attempt : $($_.Exception.Message)"
            
            if ($attempt -le $MaxRetryCount) {
                $waitTime = [Math]::Pow(2, $attempt - 1) # Exponential backoff: 1, 2, 4 seconds
                Write-Debug "Waiting $waitTime seconds before retry..."
                Start-Sleep -Seconds $waitTime
            }
        }
    } while ($attempt -le $MaxRetryCount)
    
    # If we get here, all retries failed
    Write-Error "$OperationName failed after $($MaxRetryCount + 1) attempts"
    throw $lastException
}
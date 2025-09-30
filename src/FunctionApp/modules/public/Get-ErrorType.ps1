<#
.SYNOPSIS
    Determines the error type from an exception for categorization.

.DESCRIPTION
    Analyzes PowerShell exceptions to categorize them for telemetry
    and error handling purposes.

.PARAMETER Exception
    The exception object to analyze.

.NOTES
    Author: Laurie Rhodes
    Version: 1.0
    Last Modified: 2025-01-31
#>

function Get-ErrorType {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$Exception
    )
    
    try {
        $exceptionType = $Exception.Exception.GetType().Name
        $errorMessage = $Exception.Exception.Message
        
        # Categorize common error types
        if ($exceptionType -like "*Http*" -or $errorMessage -like "*HTTP*") {
            return "HttpError"
        }
        elseif ($exceptionType -like "*Authentication*" -or $errorMessage -like "*authentication*" -or $errorMessage -like "*unauthorized*") {
            return "AuthenticationError"
        }
        elseif ($exceptionType -like "*Timeout*" -or $errorMessage -like "*timeout*") {
            return "TimeoutError"
        }
        elseif ($exceptionType -like "*Network*" -or $errorMessage -like "*network*" -or $errorMessage -like "*connection*") {
            return "NetworkError"
        }
        elseif ($exceptionType -like "*Configuration*" -or $errorMessage -like "*config*") {
            return "ConfigurationError"
        }
        elseif ($exceptionType -like "*Parse*" -or $errorMessage -like "*parse*" -or $errorMessage -like "*json*" -or $errorMessage -like "*yaml*") {
            return "ParseError"
        }
        else {
            return $exceptionType
        }
    }
    catch {
        return "UnknownError"
    }
}
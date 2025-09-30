# HelperFunctions.ps1 Refactoring Guide

## Current State Analysis

The `HelperFunctions.ps1` file currently contains **3 functions** that violate the established "one function per file" architecture principle:

```powershell
HelperFunctions.ps1
├── Get-ErrorType           # Error classification function
├── Get-HttpStatusCode      # HTTP status code extraction
└── Test-ShouldRetry        # Retry decision logic
```

## Required Refactoring Actions

### Step 1: Create Individual Function Files

#### Create Get-ErrorType.ps1
```powershell
# File: modules/public/Get-ErrorType.ps1
<#
.SYNOPSIS
    Classifies exceptions into actionable error types for retry logic.

.DESCRIPTION
    Provides standardized error categorization for intelligent retry decisions
    throughout the AAD export pipeline.

.PARAMETER Exception
    PowerShell ErrorRecord or .NET Exception object to classify.

.NOTES
    Author: Laurie Rhodes
    Version: 3.0
    Last Modified: 2025-09-01
#>

function Get-ErrorType {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $Exception
    )
    
    # [Copy entire function content from HelperFunctions.ps1]
}
```

#### Create Get-HttpStatusCode.ps1
```powershell
# File: modules/public/Get-HttpStatusCode.ps1
<#
.SYNOPSIS
    Extracts HTTP status codes from exceptions for error analysis.

.DESCRIPTION
    Provides precise HTTP status code identification from various exception
    types for accurate error handling and telemetry.

.PARAMETER Exception
    PowerShell ErrorRecord or .NET Exception object to analyze.

.NOTES
    Author: Laurie Rhodes
    Version: 3.0
    Last Modified: 2025-09-01
#>

function Get-HttpStatusCode {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $Exception
    )
    
    # [Copy entire function content from HelperFunctions.ps1]
}
```

#### Create Test-ShouldRetry.ps1
```powershell
# File: modules/public/Test-ShouldRetry.ps1
<#
.SYNOPSIS
    Determines if an operation should be retried based on error type.

.DESCRIPTION
    Prevents unnecessary retries for permanent failures while ensuring
    resilient handling of transient issues.

.PARAMETER Exception
    The exception that occurred during operation.

.PARAMETER ErrorType
    Classified error type from Get-ErrorType function.

.NOTES
    Author: Laurie Rhodes
    Version: 3.0
    Last Modified: 2025-09-01
#>

function Test-ShouldRetry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $Exception,
        
        [Parameter(Mandatory = $true)]
        [string]$ErrorType
    )
    
    # [Copy entire function content from HelperFunctions.ps1]
}
```

### Step 2: Update Module Manifest

Update `AADExporter.psd1` to include the new individual functions:

```powershell
# In AADExporter.psd1, update FunctionsToExport array:
FunctionsToExport = @(
    # Core orchestration
    'Invoke-AADDataExport',
    
    # Data export modules  
    'Export-AADUsers',
    'Export-AADGroups',
    'Export-AADGroupMemberships',
    
    # Authentication
    'Get-AzureADToken',
    
    # Event Hub integration
    'Send-EventsToEventHub',
    
    # Error handling and resilience
    'Invoke-WithRetry',
    'Invoke-GraphAPIWithRetry',
    'Get-ErrorType',           # ✅ Add this
    'Test-ShouldRetry',        # ✅ Add this  
    'Get-HttpStatusCode',      # ✅ Add this
    
    # Telemetry and monitoring
    'Write-CustomTelemetry',
    'Write-DependencyTelemetry',
    'Write-ExportProgress', 
    'New-CorrelationContext',
    
    # Storage utilities
    'Get-AzTableStorageData',
    'Set-AzTableStorageData',
    'Get-StorageTableValue',
    'Push-StorageTableValue'
    
    # Remove 'Get-Events' - legacy Okta function
)
```

### Step 3: Remove Legacy Files

After successful migration:

```powershell
# 1. Delete HelperFunctions.ps1
Remove-Item "modules/public/HelperFunctions.ps1"

# 2. Delete Get-Events.ps1 (legacy Okta function)  
Remove-Item "modules/public/Get-Events.ps1"
```

### Step 4: Validation Testing

#### Test Module Loading
```powershell
# Import module and verify functions
Import-Module .\modules\AADExporter.psm1 -Force

# Verify all three functions are available
$expectedFunctions = @('Get-ErrorType', 'Get-HttpStatusCode', 'Test-ShouldRetry')
foreach ($func in $expectedFunctions) {
    $command = Get-Command -Name $func -Module AADExporter -ErrorAction SilentlyContinue
    if ($command) {
        Write-Host "✅ $func - Available"
    } else {
        Write-Error "❌ $func - NOT AVAILABLE"
    }
}
```

#### Test Error Handling Integration
```powershell
# Test error classification workflow
try {
    throw [System.Net.WebException]::new("The remote server returned an error: (429) Too Many Requests")
} catch {
    $errorType = Get-ErrorType -Exception $_
    $statusCode = Get-HttpStatusCode -Exception $_
    $shouldRetry = Test-ShouldRetry -Exception $_ -ErrorType $errorType
    
    Write-Host "Error Type: $errorType"           # Should show: WebException (HTTP 429)
    Write-Host "Status Code: $statusCode"         # Should show: 429
    Write-Host "Should Retry: $shouldRetry"       # Should show: True
}
```

#### Test Integration with Invoke-WithRetry
```powershell
# Verify integration with retry mechanism
$testResult = Invoke-WithRetry -ScriptBlock {
    # Test operation that uses error classification
    throw [System.ArgumentException]::new("Test authentication error")
} -MaxRetryCount 2 -OperationName "TestRetryIntegration"

# Should properly classify error and make retry decision
```

## File Structure After Refactoring

### Before Refactoring ❌
```
modules/public/
├── HelperFunctions.ps1     # Contains 3 functions - violates architecture
├── Get-Events.ps1          # Legacy Okta function - not relevant
└── [other modules]         # Follow one-function-per-file pattern
```

### After Refactoring ✅
```
modules/public/
├── Get-ErrorType.ps1       # ✅ Individual function file
├── Get-HttpStatusCode.ps1  # ✅ Individual function file  
├── Test-ShouldRetry.ps1    # ✅ Individual function file
└── [other modules]         # All follow one-function-per-file pattern

# Removed files:
# ❌ HelperFunctions.ps1 (functions extracted)
# ❌ Get-Events.ps1 (legacy Okta code)
```

## Documentation Structure After Refactoring

Each function file should have its corresponding documentation:

```
modules/public/
├── Get-ErrorType.ps1 ↔️ Get-ErrorType.md
├── Get-HttpStatusCode.ps1 ↔️ Get-HttpStatusCode.md
├── Test-ShouldRetry.ps1 ↔️ Test-ShouldRetry.md
├── Export-AADUsers.ps1 ↔️ Export-AADUsers.md
├── Export-AADGroups.ps1 ↔️ Export-AADGroups.md
└── [all other modules with paired documentation]
```

## Implementation Script

### Automated Refactoring Script
```powershell
# PowerShell script to perform the refactoring
$modulesPath = ".\modules\public"

# 1. Read current HelperFunctions.ps1 content
$helperContent = Get-Content "$modulesPath\HelperFunctions.ps1" -Raw

# 2. Extract individual functions (manual step - functions have complex boundaries)
# Note: This requires manual extraction due to function complexity

# 3. Create individual files with proper headers
$functions = @(
    @{ Name = "Get-ErrorType"; Description = "Classifies exceptions into actionable error types" },
    @{ Name = "Get-HttpStatusCode"; Description = "Extracts HTTP status codes from exceptions" },
    @{ Name = "Test-ShouldRetry"; Description = "Determines if operations should be retried" }
)

foreach ($func in $functions) {
    $header = @"
<#
.SYNOPSIS
    $($func.Description).

.NOTES
    Author: Laurie Rhodes
    Version: 3.0
    Last Modified: 2025-09-01
    Extracted from HelperFunctions.ps1 for architectural compliance.
#>

"@
    
    Write-Host "Creating $($func.Name).ps1..."
    # Manual step: Add function content after header
}

# 4. Update module manifest
Write-Host "Update AADExporter.psd1 FunctionsToExport array"

# 5. Remove old files
Write-Host "Remove HelperFunctions.ps1 and Get-Events.ps1 after successful migration"
```

## Testing Checklist

### Pre-Refactoring Tests
- [ ] Document current module loading behavior
- [ ] Test error handling in Invoke-WithRetry
- [ ] Verify retry logic in Graph API calls
- [ ] Record baseline functionality

### Post-Refactoring Tests
- [ ] Module imports successfully without errors
- [ ] All three helper functions are available
- [ ] Error classification works correctly
- [ ] Retry logic integration functions properly
- [ ] No breaking changes in dependent functions
- [ ] Telemetry integration remains intact

### Validation Commands
```powershell
# Test complete error handling workflow
try {
    # Simulate Graph API rate limit error
    $response = Invoke-RestMethod -Uri "https://httpstat.us/429" -ErrorAction Stop
} catch {
    # Test full error handling pipeline
    $errorType = Get-ErrorType -Exception $_                    # Should work
    $statusCode = Get-HttpStatusCode -Exception $_              # Should return 429
    $shouldRetry = Test-ShouldRetry -Exception $_ -ErrorType $errorType  # Should return $true
    
    Write-Host "Error pipeline test:"
    Write-Host "  Error Type: $errorType"
    Write-Host "  Status Code: $statusCode" 
    Write-Host "  Should Retry: $shouldRetry"
}
```

## Migration Priority

### High Priority (Required for Architecture Compliance)
1. **Extract Get-ErrorType** - Core to all error handling
2. **Extract Get-HttpStatusCode** - Essential for HTTP error analysis  
3. **Extract Test-ShouldRetry** - Critical for retry logic

### Medium Priority (Code Cleanup)
4. **Remove Get-Events.ps1** - Legacy code cleanup
5. **Update documentation** - Ensure all functions have paired .md files

### Low Priority (Enhancement)
6. **Review storage utilities** - Consider consolidation or modernization
7. **Function header standardization** - Ensure consistent documentation blocks

This refactoring will achieve full architectural compliance with the "one function per file" principle while maintaining all existing functionality and improving code maintainability.

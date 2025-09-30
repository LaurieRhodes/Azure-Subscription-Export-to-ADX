# Get-Events

## Purpose

**⚠️ LEGACY FUNCTION - NOT RELEVANT TO AAD EXPORT**

This function appears to be legacy code from an Okta integration project and is not relevant to the Azure AD export functionality. It retrieves Okta events using Okta-specific API endpoints and authentication.

## Key Concepts

### Legacy Integration
This function contains Okta-specific logic that doesn't align with the current Azure AD export architecture and should be considered for removal.

### Okta API Integration
Uses Okta-specific authentication (`SSWS` tokens) and endpoints that are not applicable to Microsoft Graph or Azure AD scenarios.

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Starttime` | String | No | - | Start time for Okta events query (not used in current implementation) |

## Current Implementation Issues

### Unused Parameter
The `Starttime` parameter is processed but not used in the actual API call:
```powershell
# Parameter processed but not used
$starttime = ([System.DateTime]$($starttime)).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ")

# API call ignores starttime
$Url = "$($env:QUERYENDPOINT)?limit=1000"  # No since parameter
```

### Okta-Specific Dependencies
```powershell
# Uses Okta-specific authentication
$Token = Get-Token  # Function not found in AAD export modules

# Uses Okta-specific headers
$headers = @{
    "Authorization" = "SSWS $Token"  # Okta SSWS token format
    "User-Agent" = "OktaIngestor/1.0"
}
```

### Environment Variables
Depends on Okta-specific environment variables:
- `QUERYENDPOINT`: Okta API endpoint (not relevant to AAD export)

## Recommendations

### Immediate Action Required
**Remove this function** from the AAD Export Function App as it:
1. **Not relevant** to Azure AD export functionality
2. **Missing dependencies** (`Get-Token` function doesn't exist)
3. **Wrong authentication** (Okta SSWS vs Azure AD Bearer tokens)
4. **Incorrect API endpoints** (Okta vs Microsoft Graph)

### Refactoring Steps
```powershell
# 1. Remove Get-Events.ps1 from modules/public/
# 2. Remove 'Get-Events' from AADExporter.psd1 FunctionsToExport array
# 3. Verify no other functions reference Get-Events
# 4. Test module loading after removal
```

### Verification Commands
```powershell
# Check for any references to Get-Events
Get-ChildItem -Path ".\modules\public\*.ps1" -Recurse | Select-String -Pattern "Get-Events"

# Verify function exports after removal
Import-Module .\modules\AADExporter.psm1 -Force
Get-Command -Module AADExporter | Where-Object { $_.Name -eq "Get-Events" }
# Should return no results after removal
```

## File Removal Impact

### No Breaking Changes Expected
Removing this function should have **no impact** on AAD export functionality because:
- **Not called** by any AAD export functions
- **Wrong API integration** (Okta vs Azure AD)
- **Missing dependencies** would prevent it from working anyway

### Clean Architecture Benefits
Removing this legacy function will:
- **Reduce confusion** for developers
- **Eliminate dead code** from the module
- **Improve module clarity** and purpose alignment
- **Reduce maintenance overhead**

## Alternative Implementation

If Okta integration is actually needed (which seems unlikely for AAD export), create a separate module:
```powershell
# Create separate OktaIntegration module if needed
modules/OktaIntegration/
├── OktaIntegration.psm1
├── OktaIntegration.psd1
└── public/
    ├── Get-OktaEvents.ps1
    ├── Get-OktaToken.ps1
    └── Export-OktaData.ps1
```

## Conclusion

**RECOMMENDATION: DELETE THIS FILE**

The `Get-Events.ps1` function should be removed from the AAD Export Function App as it serves no purpose in the current architecture and contains dependencies that don't exist in the AAD export context.

# Infrastructure Deployment

This directory contains the Infrastructure as Code (IaC) templates for the Azure Subscription Export to ADX Function App.

## Files

- **`main.bicep`** - Main Bicep template for deploying all resources
- **`parameters.json`** - Deployment parameters
- **`example.parameters.json`** - Example parameter file
- **`cors-update.bicep`** - Standalone template for updating CORS settings
- **`azure-powershell-config.ps1`** - PowerShell configuration for suppressing warnings
- **`../deploy.ps1`** - PowerShell deployment script (enhanced v3.5)

## CORS Configuration

The Function App is automatically configured with CORS settings to allow testing from Azure Portal and other Microsoft services:

### Allowed Origins:
- `https://portal.azure.com` - Azure Portal (primary)
- `https://ms.portal.azure.com` - Azure Portal (alternative domain)
- `https://azure.microsoft.com` - Azure website
- `https://functions.azure.com` - Azure Functions portal

### Security Settings:
- `supportCredentials: false` - Credentials are not included in CORS requests
- HTTPS only - All origins use secure HTTPS protocol

## Updating CORS Settings

### For New Deployments:
CORS settings are automatically applied when deploying with `main.bicep`.

### For Existing Function Apps:
Use the standalone template to update CORS settings:

```bash
az deployment group create \
  --resource-group <resource-group-name> \
  --template-file cors-update.bicep \
  --parameters functionAppName=<function-app-name>
```

### Custom CORS Origins:
To add custom origins, modify the `allowedOrigins` array in `main.bicep`:

```bicep
cors: {
  allowedOrigins: [
    'https://portal.azure.com'
    'https://ms.portal.azure.com'
    'https://azure.microsoft.com'
    'https://functions.azure.com'
    'https://your-custom-domain.com'  // Add custom origins here
  ]
  supportCredentials: false
}
```

## Deployment

The enhanced deployment script (v3.5) includes:
- **Warning suppression** for Azure PowerShell breaking changes
- **Future compatibility** with Az.Accounts v5.0.0+ 
- **Enhanced error handling** and progress reporting
- **Automatic cleanup** of temporary files
- **Validation mode** support

### Basic Deployment:
```powershell
# Deploy infrastructure and code
.\deploy.ps1

# Deploy only code (skip infrastructure)
.\deploy.ps1 -SkipInfrastructure

# Validate infrastructure without deploying
.\deploy.ps1 -ValidateOnly
```

### CI/CD Integration:
For automated pipelines, set environment variable to suppress warnings:
```yaml
# Azure DevOps Pipeline
variables:
  SuppressAzurePowerShellBreakingChangeWarnings: true

# GitHub Actions
env:
  SuppressAzurePowerShellBreakingChangeWarnings: true
```

## Azure PowerShell Compatibility

The deployment script handles breaking changes in Azure PowerShell:

### Handled Breaking Changes:
- **Az.Accounts v5.0.0+**: `Get-AzAccessToken` token format change
- **Az.Websites**: Import warnings for unapproved verbs
- **General**: All breaking change warnings suppressed

### Requirements:
- **Azure CLI**: Latest version
- **Azure PowerShell**: Az.Websites module
- **PowerShell**: 5.1+ or PowerShell Core 7+

## Security Considerations

- CORS origins are restricted to Microsoft domains by default
- `supportCredentials` is disabled for security
- Function App uses HTTPS only
- Managed Identity authentication eliminates stored secrets
- Storage account keys are managed through Azure Key Management

## Troubleshooting

### Deployment Issues:
1. **PowerShell Module Errors**: Install required modules:
   ```powershell
   Install-Module Az.Websites -Force
   ```

2. **Authentication Issues**: Ensure you're logged in:
   ```powershell
   Connect-AzAccount
   az login
   ```

3. **Permission Issues**: Verify you have Contributor role on target subscription

### CORS Issues:
If you encounter CORS errors:

1. **Verify origins** - Check that your domain is in the allowed origins list
2. **Check protocol** - Ensure you're using HTTPS, not HTTP
3. **Clear browser cache** - Browser may cache CORS preflight responses
4. **Wait for propagation** - CORS changes may take a few minutes to apply

Common CORS error symptoms:
- "Cross-origin request blocked" in browser console
- 403 errors when calling Function App from browser
- Function works in Postman but not in browser

### Warning Suppression:
If you still see warnings, manually suppress them:
```powershell
Set-Item -Path Env:SuppressAzurePowerShellBreakingChangeWarnings -Value $true
```
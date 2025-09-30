<#
.SYNOPSIS
    Deployment script for Azure Subscription Export to ADX Function App.

.DESCRIPTION
    Deploys Azure infrastructure using Bicep and uploads Function App code.
    Reads configuration from parameters.json with enhanced error handling.

.PARAMETER SkipInfrastructure
    Skip infrastructure deployment, only deploy code.

.PARAMETER ValidateOnly
    Only validate Bicep template without deploying.

.EXAMPLE
    .\deploy.ps1
    .\deploy.ps1 -SkipInfrastructure
    .\deploy.ps1 -ValidateOnly

.NOTES
    Author: Laurie Rhodes
    Version: 3.5 - Fixed Azure PowerShell warnings and future compatibility
    Uses flat error handling - no nested try/catch blocks
    Fixed breaking change warnings for Az.Accounts and Az.Websites
#>

[CmdletBinding()]
param (
    [switch]$SkipInfrastructure,
    [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"

# Suppress Azure PowerShell breaking change warnings
Set-Item -Path Env:SuppressAzurePowerShellBreakingChangeWarnings -Value $true

$configFile = ".\infrastructure\parameters.json"
$bicepTemplate = ".\infrastructure\main.bicep"
$sourceCode = ".\src\FunctionApp"

Write-Host "Azure Subscription Export Function App Deployment" -ForegroundColor Cyan

if (-not (Test-Path $configFile)) {
    Write-Error "❌ Configuration file not found: $configFile"
    throw
}

$config = (Get-Content $configFile | ConvertFrom-Json).parameters
$resourceGroupName = ($config.resourceGroupID.value -split '/resourceGroups/')[1]
$functionAppName = $config.functionAppName.value
$subscriptionId = ($config.resourceGroupID.value -split '/')[2]

Write-Host "Deployment Configuration:" -ForegroundColor Yellow
Write-Host "  Subscription: $subscriptionId" -ForegroundColor Gray
Write-Host "  Resource Group: $resourceGroupName" -ForegroundColor Gray
Write-Host "  Function App: $functionAppName" -ForegroundColor Gray

# Set Azure CLI context
Write-Host "Setting Azure CLI context..." -ForegroundColor Blue
az account set --subscription $subscriptionId
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to set Azure subscription context"
    throw
}

if (-not $SkipInfrastructure) {
    Write-Host "Deploying infrastructure..." -ForegroundColor Blue
    
    $deployCmd = if ($ValidateOnly) { "validate" } else { "create" }
    $deploymentName = "subscription-export-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    
    az deployment group $deployCmd `
        --resource-group $resourceGroupName `
        --template-file $bicepTemplate `
        --parameters $configFile `
        --name $deploymentName
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Infrastructure deployment failed"
        throw
    }
    
    if ($ValidateOnly) {
        Write-Host "✅ Infrastructure validation completed successfully" -ForegroundColor Green
        return
    } else {
        Write-Host "✅ Infrastructure deployment completed" -ForegroundColor Green
    }
}

if (-not $ValidateOnly) {
    Write-Host "Deploying Function App code..." -ForegroundColor Blue
    
    # Import Azure PowerShell modules with warning suppression
    Write-Host "Importing Azure PowerShell modules..." -ForegroundColor Gray
    
    if (-not (Get-Module -ListAvailable Az.Websites)) {
        Write-Error "Az.Websites module required. Install with: Install-Module Az.Websites"
        throw
    }
    
    # Import with explicit warning suppression
    Import-Module Az.Websites -WarningAction SilentlyContinue
    
    # Ensure we're connected to Azure PowerShell
    $azContext = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $azContext -or $azContext.Subscription.Id -ne $subscriptionId) {
        Write-Host "Connecting to Azure PowerShell..." -ForegroundColor Gray
        Connect-AzAccount -Subscription $subscriptionId | Out-Null
    }
    
    # Verify Function App exists
    Write-Host "Verifying Function App exists..." -ForegroundColor Gray
    $functionApp = Get-AzWebApp -ResourceGroupName $resourceGroupName -Name $functionAppName -ErrorAction SilentlyContinue
    if (-not $functionApp) {
        Write-Error "Function App $functionAppName not found. Deploy infrastructure first."
        throw
    }
    
    # Package source code
    Write-Host "Packaging source code..." -ForegroundColor Gray
    $tempZip = "$env:TEMP\functionapp-$(Get-Date -Format 'yyyyMMdd-HHmmss').zip"
    if (Test-Path $tempZip) {
        Remove-Item $tempZip -Force
    }
    
    if (-not (Test-Path $sourceCode)) {
        Write-Error "Source code directory not found: $sourceCode"
        throw
    }
    
    Compress-Archive -Path "$sourceCode\*" -DestinationPath $tempZip -Force
    $zipSizeMB = [Math]::Round((Get-Item $tempZip).Length / 1MB, 2)
    Write-Host "Created deployment package: $zipSizeMB MB" -ForegroundColor Gray
    
    # Deploy using Kudu ZIP Deploy API
    Write-Host "Deploying to Function App via ZIP Deploy..." -ForegroundColor Gray
    
    try {
        # Get publishing profile for credentials
        $publishProfile = Get-AzWebAppPublishingProfile -ResourceGroupName $resourceGroupName -Name $functionAppName
        $xmlProfile = [xml]$publishProfile
        $creds = $xmlProfile.SelectSingleNode("//publishProfile[@publishMethod='MSDeploy']")
        
        if (-not $creds) {
            Write-Error "Could not extract deployment credentials from publishing profile"
            throw
        }
        
        # Prepare deployment request
        $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($creds.userName):$($creds.userPWD)"))
        $headers = @{ 
            Authorization = "Basic $auth"
            'Content-Type' = "application/zip"
        }
        $deployUrl = "https://$functionAppName.scm.azurewebsites.net/api/zipdeploy"
        
        # Deploy with extended timeout for large packages
        Invoke-RestMethod -Uri $deployUrl -Headers $headers -Method POST -InFile $tempZip -TimeoutSec 300
        
        Write-Host "✅ Code deployment completed" -ForegroundColor Green
        
    } catch {
        Write-Error "Code deployment failed: $($_.Exception.Message)"
        throw
    } finally {
        # Clean up temporary files
        if (Test-Path $tempZip) {
            Remove-Item $tempZip -Force
        }
    }
    
    # Sync function triggers (handle breaking change in Get-AzAccessToken)
    Write-Host "Syncing function triggers..." -ForegroundColor Gray
    
    try {
        $syncUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Web/sites/$functionAppName/syncfunctiontriggers?api-version=2024-11-01"
        
        # Handle breaking change in Get-AzAccessToken - use AsSecureString parameter for future compatibility
        try {
            # Try new method first (for Az.Accounts v5.0.0+)
            $tokenSecure = (Get-AzAccessToken -AsSecureString -ErrorAction SilentlyContinue).Token
            if ($tokenSecure) {
                # Convert SecureString to plain text for REST API
                $token = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($tokenSecure))
            } else {
                throw "AsSecureString not supported"
            }
        } catch {
            # Fallback to old method (current versions)
            $token = (Get-AzAccessToken).Token
        }
        
        $syncHeaders = @{ 'Authorization' = "Bearer $token" }
        
        # Suppress errors for trigger sync (non-critical operation)
        $ErrorActionPreference = "SilentlyContinue"
        Invoke-RestMethod -Uri $syncUrl -Headers $syncHeaders -Method POST -TimeoutSec 30
        
        if ($Error[0]) {
            Write-Host "Trigger sync failed, restarting Function App instead..." -ForegroundColor Yellow
            $ErrorActionPreference = "Stop"
            Restart-AzWebApp -ResourceGroupName $resourceGroupName -Name $functionAppName
            Write-Host "Function App restarted" -ForegroundColor Gray
        } else {
            Write-Host "Function triggers synced successfully" -ForegroundColor Gray
        }
        
        $ErrorActionPreference = "Stop"
        
    } catch {
        Write-Warning "Could not sync function triggers: $($_.Exception.Message)"
        Write-Host "This is non-critical - functions will sync automatically" -ForegroundColor Gray
    }
    
    # Display completion summary
    Write-Host ""
    Write-Host "🎉 Deployment completed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Function App Details:" -ForegroundColor Cyan
    Write-Host "  Name: $functionAppName" -ForegroundColor Gray
    Write-Host "  URL: https://$functionAppName.azurewebsites.net" -ForegroundColor Gray
    Write-Host "  Resource Group: $resourceGroupName" -ForegroundColor Gray
    Write-Host "  Subscription: $subscriptionId" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Verify deployment in Azure Portal" -ForegroundColor Gray
    Write-Host "  2. Test functions via Portal or REST API" -ForegroundColor Gray
    Write-Host "  3. Check Application Insights for logs" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "Deployment script completed!" -ForegroundColor Green
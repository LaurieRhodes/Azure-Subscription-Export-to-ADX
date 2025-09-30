# Deployment Guide

## 🚀 **Complete Deployment Instructions**

This guide provides step-by-step instructions for deploying the AAD Export to ADX solution in your Azure environment.

---

## 📋 **Prerequisites**

### **Azure Requirements**
- Azure subscription with Contributor access
- Azure AD tenant with Global Administrator or equivalent
- Resource group for deployment
- Azure CLI or PowerShell installed locally

### **Local Development Tools**
- PowerShell 7.0 or later
- Azure Functions Core Tools v4
- Git for source control
- Visual Studio Code (recommended)

### **Permissions Required**
- **Azure Subscription**: Contributor role
- **Azure AD**: Ability to create and assign managed identities
- **Resource Creation**: Function App, Event Hub, Storage Account, Application Insights

---

## 🏗️ **Step-by-Step Deployment**

### **Step 1: Create Azure Resources**

#### **Option A: Using Azure CLI**
```bash
# Set variables
$resourceGroup = "rg-aad-export"
$location = "australiaeast"
$functionAppName = "func-aad-export-prod"
$storageAccountName = "staadexportprod"  # Must be globally unique
$eventHubNamespace = "eh-aad-export"
$eventHubName = "aad-data"
$appInsightsName = "ai-aad-export"
$managedIdentityName = "mi-aad-export"

# Create resource group
az group create --name $resourceGroup --location $location

# Deploy infrastructure using Bicep
az deployment group create \
  --resource-group $resourceGroup \
  --template-file infrastructure/main.bicep \
  --parameters functionAppName=$functionAppName \
               storageAccountName=$storageAccountName \
               applicationInsightsName=$appInsightsName \
               eventHubNamespace=$eventHubNamespace \
               eventHubName=$eventHubName \
               userAssignedIdentityResourceId="/subscriptions/{subscription-id}/resourceGroups/$resourceGroup/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$managedIdentityName"
```

#### **Option B: Using Azure PowerShell**
```powershell
# Install required modules
Install-Module -Name Az -Force -AllowClobber
Install-Module -Name AzureAD -Force -AllowClobber

# Connect to Azure
Connect-AzAccount
Connect-AzureAD

# Set deployment variables
$resourceGroup = "rg-aad-export"
$location = "Australia East"
$subscriptionId = (Get-AzContext).Subscription.Id

# Create resource group
New-AzResourceGroup -Name $resourceGroup -Location $location

# Deploy using Bicep template
New-AzResourceGroupDeployment `
  -ResourceGroupName $resourceGroup `
  -TemplateFile "infrastructure/main.bicep" `
  -TemplateParameterFile "infrastructure/parameters.json"
```

### **Step 2: Configure Managed Identity Permissions**

#### **Create and Assign Graph API Permissions**
```powershell
# Connect to Azure AD
Connect-AzureAD

# Get the managed identity
$managedIdentityName = "mi-aad-export"
$managedIdentity = Get-AzureADServicePrincipal -Filter "displayName eq '$managedIdentityName'"

if (-not $managedIdentity) {
    Write-Error "Managed Identity '$managedIdentityName' not found. Ensure infrastructure deployment completed successfully."
    exit 1
}

# Microsoft Graph Service Principal (constant)
$graphAppId = "00000003-0000-0000-c000-000000000000"
$graphServicePrincipal = Get-AzureADServicePrincipal -Filter "appId eq '$graphAppId'"

# Required permissions
$requiredPermissions = @(
    "User.Read.All",
    "Group.Read.All",
    "AuditLog.Read.All"
)

foreach ($permission in $requiredPermissions) {
    $appRole = $graphServicePrincipal.AppRoles | Where-Object {
        $_.Value -eq $permission -and $_.AllowedMemberTypes -contains "Application"
    }
    
    if ($appRole) {
        try {
            New-AzureADServiceAppRoleAssignment `
                -ObjectId $managedIdentity.ObjectId `
                -PrincipalId $managedIdentity.ObjectId `
                -ResourceId $graphServicePrincipal.ObjectId `
                -Id $appRole.Id
            
            Write-Host "✅ Successfully assigned $permission to Managed Identity" -ForegroundColor Green
        }
        catch {
            Write-Warning "⚠️ Failed to assign $permission (may already exist): $_"
        }
    }
    else {
        Write-Error "❌ Could not find $permission role in Microsoft Graph"
    }
}
```

### **Step 3: Configure Event Hub Permissions**

#### **Assign Event Hub Roles**
```powershell
# Get managed identity resource ID
$managedIdentityResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$managedIdentityName"

# Event Hub namespace resource ID
$eventHubResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.EventHub/namespaces/$eventHubNamespace"

# Assign Azure Event Hubs Data Sender role
New-AzRoleAssignment `
    -ObjectId $managedIdentity.ObjectId `
    -RoleDefinitionName "Azure Event Hubs Data Sender" `
    -Scope $eventHubResourceId

Write-Host "✅ Event Hub permissions configured" -ForegroundColor Green
```

### **Step 4: Deploy Function Code**

#### **Using Azure Functions Core Tools**
```bash
# Navigate to function app directory
cd src/FunctionApp

# Install Azure Functions Core Tools (if not installed)
npm install -g azure-functions-core-tools@4 --unsafe-perm true

# Login to Azure
func azure account set --subscription-id $subscriptionId

# Deploy function code
func azure functionapp publish $functionAppName --powershell

# Verify deployment
func azure functionapp list-functions $functionAppName
```

#### **Alternative: Manual Deployment via Portal**
1. Open Azure Portal → Function Apps → [Your Function App]
2. Go to **Deployment Center**
3. Choose **External Git** or **Local Git**
4. Configure repository URL: `https://github.com/your-org/AAD-UserAndGroupExporttoADX.git`
5. Set branch to `main` and build provider to **App Service Build Service**
6. Save configuration and trigger deployment

### **Step 5: Configure Application Settings**

```powershell
# Get managed identity client ID
$managedIdentity = Get-AzUserAssignedIdentity -ResourceGroupName $resourceGroup -Name $managedIdentityName
$clientId = $managedIdentity.ClientId

# Configure function app environment variables
$appSettings = @(
    "EVENTHUBNAMESPACE=$eventHubNamespace",
    "EVENTHUB=$eventHubName", 
    "CLIENTID=$clientId"
)

# Apply settings using Azure CLI
foreach ($setting in $appSettings) {
    az functionapp config appsettings set `
      --resource-group $resourceGroup `
      --name $functionAppName `
      --settings $setting
}

Write-Host "✅ Application settings configured" -ForegroundColor Green
```

---

## 🧪 **Post-Deployment Testing**

### **Test 1: Managed Identity Authentication**
```powershell
# Test from Function App's Kudu console
# Navigate to: https://[function-app-name].scm.azurewebsites.net/DebugConsole

# Test Graph API access
$headers = @{
    'Metadata' = 'true'
    'X-IDENTITY-HEADER' = $env:IDENTITY_HEADER
}

$tokenUrl = "$($env:IDENTITY_ENDPOINT)?resource=https://graph.microsoft.com&client_id=$($env:CLIENTID)&api-version=2019-08-01"
$tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Headers $headers -Method GET

if ($tokenResponse.access_token) {
    Write-Host "✅ Managed Identity authentication successful" -ForegroundColor Green
} else {
    Write-Error "❌ Managed Identity authentication failed"
}
```

### **Test 2: HTTP Trigger Execution**
```bash
# Get function URL and key
$functionKey = $(az functionapp keys list --resource-group $resourceGroup --name $functionAppName --query "functionKeys.default" -o tsv)
$httpTriggerUrl = "https://$functionAppName.azurewebsites.net/api/HttpTriggerFunction?code=$functionKey"

# Execute test
$response = Invoke-RestMethod -Uri $httpTriggerUrl -Method POST -ContentType "application/json"

# Check response
if ($response.statusCode -eq 202) {
    Write-Host "✅ HTTP Trigger test successful" -ForegroundColor Green
    Write-Host "Response: $($response.body | ConvertTo-Json)"
} else {
    Write-Error "❌ HTTP Trigger test failed"
}
```

### **Test 3: Timer Trigger Schedule**
```bash
# Verify timer trigger configuration
az functionapp function show \
  --resource-group $resourceGroup \
  --name $functionAppName \
  --function-name TimerTriggerFunction \
  --query "config.bindings[0].schedule" -o tsv

# Should return: "0 0 1 * * *" (daily at 1 AM)
```

### **Test 4: Event Hub Data Flow**
```powershell
# Monitor Event Hub activity
az eventhubs eventhub show \
  --resource-group $resourceGroup \
  --namespace-name $eventHubNamespace \
  --name $eventHubName \
  --query "messageRetentionInDays"

# Check Event Hub metrics
az monitor metrics list \
  --resource "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.EventHub/namespaces/$eventHubNamespace" \
  --metric "IncomingMessages" \
  --interval PT1H
```

---

## 📊 **Monitoring & Alerting Setup**

### **Application Insights Configuration**

#### **Create Custom Dashboard**
```powershell
# Application Insights workspace ID
$appInsightsId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.Insights/components/$appInsightsName"

# Create monitoring queries
$queries = @{
    "FunctionExecutions" = "traces | where message contains 'Function Invoked' | summarize count() by bin(timestamp, 1h)"
    "ErrorAnalysis" = "exceptions | summarize count() by problemId, outerMessage | top 10 by count_"
    "GraphAPILatency" = "dependencies | where type == 'Http' and target contains 'graph.microsoft.com' | summarize avg(duration) by bin(timestamp, 1h)"
    "EventHubThroughput" = "traces | where message contains 'sending to event hub' | summarize count() by bin(timestamp, 5m)"
}
```

#### **Alert Rules**
```bash
# Function failure alert
az monitor metrics alert create \
  --name "AAD-Export-Function-Failures" \
  --resource-group $resourceGroup \
  --scopes $appInsightsId \
  --condition "count exceptions > 0" \
  --description "Alert when AAD export function encounters errors" \
  --evaluation-frequency 5m \
  --window-size 15m

# Long execution time alert  
az monitor metrics alert create \
  --name "AAD-Export-Long-Execution" \
  --resource-group $resourceGroup \
  --scopes $appInsightsId \
  --condition "avg duration > PT30M" \
  --description "Alert when function execution exceeds 30 minutes" \
  --evaluation-frequency 5m \
  --window-size 15m
```

### **Log Analytics Queries**

#### **Function Performance**
```kusto
// Function execution summary
traces
| where message contains "Function Invoked"
| extend TriggerType = case(
    message contains "HTTP", "HTTP",
    message contains "Timer", "Timer", 
    "Unknown"
)
| summarize 
    ExecutionCount = count(),
    AvgDuration = avg(todouble(customDimensions.Duration))
  by TriggerType, bin(timestamp, 1d)
| render timechart
```

#### **Error Analysis**
```kusto
// Detailed error breakdown
exceptions
| extend 
    ErrorType = case(
        outerMessage contains "401", "Authentication",
        outerMessage contains "429", "Rate Limit",
        outerMessage contains "timeout", "Timeout",
        "Other"
    )
| summarize count() by ErrorType, bin(timestamp, 1h)
| render columnchart
```

---

## 🔄 **Environment Management**

### **Development Environment**

#### **Local Development Setup**
```powershell
# Clone repository
git clone https://github.com/your-org/AAD-UserAndGroupExporttoADX.git
cd AAD-UserAndGroupExporttoADX

# Install Azure Functions Core Tools
npm install -g azure-functions-core-tools@4

# Configure local settings
# Create local.settings.json (not committed to source control)
@{
    "IsEncrypted" = $false
    "Values" = @{
        "AzureWebJobsStorage" = "DefaultEndpointsProtocol=https;AccountName=devstorageaccount001;AccountKey=..."
        "FUNCTIONS_WORKER_RUNTIME" = "powershell"
        "EVENTHUBNAMESPACE" = "eh-aad-export-dev"
        "EVENTHUB" = "aad-data-dev"
        "CLIENTID" = "dev-managed-identity-client-id"
    }
} | ConvertTo-Json | Out-File -FilePath "src/FunctionApp/local.settings.json"

# Start local development
cd src/FunctionApp
func start --powershell
```

### **Production Environment**

#### **Environment Configuration**
| Setting | Development | Production | Description |
|---------|-------------|------------|-------------|
| `EVENTHUBNAMESPACE` | `eh-aad-export-dev` | `eh-aad-export-prod` | Event Hub namespace |
| `EVENTHUB` | `aad-data-dev` | `aad-data-prod` | Event Hub name |
| `CLIENTID` | `dev-client-id` | `prod-client-id` | Managed identity client ID |
| **Logging Level** | `Debug` | `Information` | Application Insights verbosity |
| **Function Timeout** | `00:10:00` | `04:00:00` | Maximum execution time |

---

## 🔧 **Configuration Management**

### **Application Settings Management**
```powershell
# Function to update app settings
function Set-FunctionAppSettings {
    param(
        [string]$ResourceGroupName,
        [string]$FunctionAppName,
        [hashtable]$Settings
    )
    
    foreach ($setting in $Settings.GetEnumerator()) {
        az functionapp config appsettings set \
          --resource-group $ResourceGroupName \
          --name $FunctionAppName \
          --settings "$($setting.Key)=$($setting.Value)" \
          --output none
        
        Write-Host "✅ Set $($setting.Key)" -ForegroundColor Green
    }
}

# Production settings
$prodSettings = @{
    "EVENTHUBNAMESPACE" = "eh-aad-export-prod"
    "EVENTHUB" = "aad-data-prod"
    "CLIENTID" = "prod-managed-identity-client-id"
    "WEBSITE_TIME_ZONE" = "AUS Eastern Standard Time"
}

Set-FunctionAppSettings -ResourceGroupName $resourceGroup -FunctionAppName $functionAppName -Settings $prodSettings
```

### **Timer Schedule Configuration**
```json
{
  "bindings": [
    {
      "name": "myTimer",
      "type": "timerTrigger", 
      "direction": "in",
      "schedule": "0 0 1 * * *"
    }
  ]
}
```

**Schedule Format**: `{second} {minute} {hour} {day} {month} {day-of-week}`
- `0 0 1 * * *` = Daily at 1:00 AM UTC
- `0 30 2 * * *` = Daily at 2:30 AM UTC
- `0 0 9 * * MON` = Every Monday at 9:00 AM UTC

---

## 🧪 **Post-Deployment Testing**

### **Test 1: End-to-End Functionality**
```powershell
# Complete test script
function Test-AADExportDeployment {
    param(
        [string]$ResourceGroupName,
        [string]$FunctionAppName,
        [string]$EventHubNamespace
    )
    
    Write-Host "🧪 Starting deployment validation..." -ForegroundColor Cyan
    
    # Test 1: Function App accessibility
    try {
        $functionApp = Get-AzFunctionApp -ResourceGroupName $ResourceGroupName -Name $FunctionAppName
        Write-Host "✅ Function App accessible" -ForegroundColor Green
    }
    catch {
        Write-Error "❌ Function App not accessible: $_"
        return $false
    }
    
    # Test 2: HTTP trigger execution
    try {
        $functionKey = (Get-AzFunctionAppKey -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -KeyName "default").Value
        $httpUrl = "https://$FunctionAppName.azurewebsites.net/api/HttpTriggerFunction?code=$functionKey"
        
        $response = Invoke-RestMethod -Uri $httpUrl -Method POST -TimeoutSec 300
        
        if ($response.statusCode -eq 202) {
            Write-Host "✅ HTTP Trigger execution successful" -ForegroundColor Green
        }
    }
    catch {
        Write-Error "❌ HTTP Trigger test failed: $_"
        return $false
    }
    
    # Test 3: Event Hub message delivery
    Start-Sleep -Seconds 30  # Allow time for processing
    
    $ehMetrics = az monitor metrics list \
      --resource "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.EventHub/namespaces/$EventHubNamespace" \
      --metric "IncomingMessages" \
      --interval PT5M | ConvertFrom-Json
    
    if ($ehMetrics.value.timeseries.data.Count -gt 0) {
        Write-Host "✅ Event Hub receiving messages" -ForegroundColor Green
    }
    
    Write-Host "🎉 Deployment validation complete!" -ForegroundColor Green
    return $true
}

# Run validation
Test-AADExportDeployment -ResourceGroupName $resourceGroup -FunctionAppName $functionAppName -EventHubNamespace $eventHubNamespace
```

### **Test 2: Data Quality Validation**
```kusto
// Query ADX to verify data ingestion
.show ingestion failures 
| where Table in ("Users", "Groups", "GroupMembers")
| where IngestionSourceId contains "aad-export"

// Verify data freshness
Users 
| summarize max(ingestion_time())
| extend DataAge = now() - max_ingestion_time_
| project DataAge

// Sample data validation
Users
| take 10
| project displayName, userPrincipalName, department, accountEnabled
```

---

## 🔄 **Deployment Automation**

### **CI/CD Pipeline Setup**

#### **GitHub Actions Workflow**
```yaml
# .github/workflows/deploy.yml
name: Deploy AAD Export Function

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

env:
  AZURE_FUNCTIONAPP_NAME: func-aad-export-prod
  AZURE_FUNCTIONAPP_PACKAGE_PATH: './src/FunctionApp'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup PowerShell
      uses: azure/powershell@v1
      with:
        inlineScript: |
          Install-Module -Name Az.Functions -Force
        azPSVersion: "latest"
    
    - name: Login to Azure
      uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}
    
    - name: Deploy Function App
      run: |
        func azure functionapp publish ${{ env.AZURE_FUNCTIONAPP_NAME }} --powershell
      working-directory: ${{ env.AZURE_FUNCTIONAPP_PACKAGE_PATH }}
```

#### **Azure DevOps Pipeline**
```yaml
# azure-pipelines.yml
trigger:
- main

pool:
  vmImage: 'ubuntu-latest'

variables:
  functionAppName: 'func-aad-export-prod'
  resourceGroupName: 'rg-aad-export'

stages:
- stage: Deploy
  jobs:
  - job: DeployFunction
    steps:
    - task: AzureFunctionApp@1
      inputs:
        azureSubscription: 'Azure-Service-Connection'
        appType: 'functionApp'
        appName: '$(functionAppName)'
        package: 'src/FunctionApp'
        runtimeStack: 'powershell'
```

---

## 🛠️ **Troubleshooting**

### **Common Deployment Issues**

#### **Issue 1: Managed Identity Permission Denied**
```
Error: 401 Unauthorized when calling Graph API
```
**Solution**:
```powershell
# Verify managed identity has correct permissions
$managedIdentity = Get-AzureADServicePrincipal -Filter "displayName eq 'mi-aad-export'"
Get-AzureADServiceAppRoleAssignment -ObjectId $managedIdentity.ObjectId

# Re-assign permissions if missing
# [Follow Step 2 permission assignment]
```

#### **Issue 2: Function Timeout**
```
Error: Function execution timeout after 4 hours
```
**Solution**:
```json
// Increase timeout in host.json
{
  "functionTimeout": "08:00:00"  // 8 hours maximum
}
```

#### **Issue 3: Event Hub Connection Failure**
```
Error: Event Hub authentication failed
```
**Solution**:
```powershell
# Verify Event Hub role assignment
Get-AzRoleAssignment -ObjectId $managedIdentity.ObjectId -Scope $eventHubResourceId

# Re-assign if missing
New-AzRoleAssignment -ObjectId $managedIdentity.ObjectId -RoleDefinitionName "Azure Event Hubs Data Sender" -Scope $eventHubResourceId
```

### **Diagnostic Queries**

#### **Function Health Check**
```kusto
// Function execution status
traces
| where timestamp > ago(24h)
| where message contains "Function Invoked" or message contains "Export Complete"
| summarize count() by message, bin(timestamp, 1h)
| render timechart
```

#### **Performance Analysis**
```kusto
// Execution duration tracking
dependencies
| where timestamp > ago(24h)
| where type == "Http"
| extend ApiEndpoint = case(
    target contains "graph.microsoft.com/beta/users", "Users API",
    target contains "graph.microsoft.com/beta/groups", "Groups API", 
    target contains "servicebus.windows.net", "Event Hub",
    "Other"
)
| summarize 
    RequestCount = count(),
    AvgDuration = avg(duration),
    MaxDuration = max(duration)
  by ApiEndpoint
| order by RequestCount desc
```

---

## 🔄 **Maintenance & Updates**

### **Regular Maintenance Tasks**

#### **Monthly**
- [ ] Review Application Insights metrics and alerts
- [ ] Check Event Hub message retention and throughput
- [ ] Validate ADX data ingestion and quality
- [ ] Update PowerShell modules if needed

#### **Quarterly**
- [ ] Review and rotate function keys
- [ ] Audit managed identity permissions
- [ ] Performance optimization review
- [ ] Security assessment

#### **Annually**
- [ ] Review Graph API permission requirements
- [ ] Update Azure Functions runtime version
- [ ] Infrastructure cost optimization
- [ ] Disaster recovery testing

### **Update Procedure**
```powershell
# Safe update process
1. Stop-AzFunctionApp -ResourceGroupName $resourceGroup -Name $functionAppName
2. # Deploy new code
   func azure functionapp publish $functionAppName --powershell
3. # Test in staging slot if available
4. Start-AzFunctionApp -ResourceGroupName $resourceGroup -Name $functionAppName
5. # Monitor for 24 hours
```

---

## 📋 **Deployment Checklist**

### **Pre-Deployment**
- [ ] Azure subscription access confirmed
- [ ] Resource group created
- [ ] Managed identity created with proper permissions
- [ ] Event Hub namespace and hub created
- [ ] Application Insights workspace ready

### **Deployment**
- [ ] Infrastructure deployed via Bicep templates
- [ ] Managed identity Graph API permissions assigned
- [ ] Event Hub permissions configured
- [ ] Function code deployed successfully
- [ ] Application settings configured

### **Post-Deployment**
- [ ] HTTP trigger test successful
- [ ] Timer trigger schedule verified
- [ ] Event Hub message flow confirmed
- [ ] Application Insights telemetry working
- [ ] Monitoring alerts configured
- [ ] Documentation updated

### **Go-Live**
- [ ] Production environment validated
- [ ] Monitoring dashboards created
- [ ] Alert notifications configured
- [ ] Support team notified
- [ ] Rollback plan documented

---

## 📞 **Support & Maintenance**

### **Key Contacts**
- **Development Team**: [Your team contact]
- **Azure Support**: [Support case process]
- **On-Call**: [Emergency contact procedure]

### **Emergency Procedures**
1. **Function App Failure**: Stop function, check logs, restore from backup
2. **Data Quality Issues**: Verify Graph API responses, check Event Hub delivery
3. **Performance Degradation**: Review Application Insights, scale resources if needed

---

*This deployment guide ensures consistent, repeatable deployments across all environments while maintaining enterprise security and monitoring standards.*
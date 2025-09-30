# Configuration-Driven Subscription Export

## 🎯 **Overview**

The Azure Subscription Export Function App now supports YAML-based configuration files for managing multiple subscription IDs and export settings. This approach is much more maintainable than environment variables for large numbers of subscriptions.

## 📁 **Configuration File Structure**

### **Location**

```
src/FunctionApp/config/subscriptions.yaml
```

### **Full Configuration Example**

```yaml
# Azure Subscription Export Configuration
metadata:
  version: "1.0"
  description: "Azure Subscription Export Configuration"
  lastUpdated: "2025-01-31"
  owner: "Enterprise IT"

# Subscription Configuration
subscriptions:
  # Your initial subscription (already configured)
  - id: "2be53ae5-6e46-47df-beb9-6f3a795387b8"
    name: "Production Primary"
    description: "Main production environment"
    enabled: true
    priority: 1

  # Add more subscriptions as needed
  - id: "12345678-1234-1234-1234-123456789012"
    name: "Production Secondary"
    description: "Secondary production environment"
    enabled: true
    priority: 2

  - id: "87654321-4321-4321-4321-210987654321"
    name: "Development"
    description: "Development environment"
    enabled: false  # Disabled - won't be exported
    priority: 3

  - id: "abcdefgh-abcd-abcd-abcd-abcdefghijkl"
    name: "Staging"
    description: "Staging environment"
    enabled: true
    priority: 4

# Export Configuration
exportSettings:
  subscriptionObjects: true
  roleDefinitions: false
  resourceGroupDetails: true
  roleAssignments: true
  policyDefinitions: false
  policyAssignments: false
  policyExemptions: false
  securityCenterSubscriptions: false
  includeChildResources: true

# Resource Group Filters (optional)
resourceGroupFilters:
  - "rg-production-web"
  - "rg-production-data"
  - "rg-shared-services"

# Resource Type Exclusions (optional)
resourceTypeExclusions:
  - "Microsoft.Resources/deployments"
  - "Microsoft.Resources/deploymentScripts"

# Advanced Settings
advanced:
  verboseTelemetry: true
  enableProfiling: false
  customTags:
    exportSource: "FunctionApp"
    environment: "production"
    dataClassification: "internal"
```

## 🚀 **Usage Modes**

### **1. Automatic Mode (Timer Trigger)**

The Function App automatically detects configuration and chooses the best export method:

**Priority Order:**

1. **Config File**: Uses `config/subscriptions.yaml` if present
2. **Multi-Subscription Env Vars**: Uses `ALL_SUBSCRIPTION_IDS` or `ADDITIONAL_SUBSCRIPTION_IDS`
3. **Single Subscription**: Falls back to `SUBSCRIPTION_ID`

**Timer runs daily at 1:00 AM UTC**

### **2. Manual HTTP Trigger**

**GET Request - Status Check:**

```bash
curl https://your-function-app.azurewebsites.net/api/HttpTriggerFunction
```

**Response includes configuration preview:**

```json
{
  "status": "ready",
  "configuration": {
    "status": "available",
    "source": "Azure Subscription Export Configuration",
    "version": "1.0",
    "subscriptionsCount": 3,
    "subscriptions": [
      {
        "name": "Production Primary",
        "id": "2be53ae5...",
        "priority": 1
      }
    ]
  }
}
```

**POST Request - Manual Export:**

```bash
# Use default configuration
curl -X POST https://your-function-app.azurewebsites.net/api/HttpTriggerFunction

# With custom options
curl -X POST https://your-function-app.azurewebsites.net/api/HttpTriggerFunction \
  -H "Content-Type: application/json" \
  -d '{
    "configFile": "subscriptions",
    "subscriptionFilter": ["2be53ae5-6e46-47df-beb9-6f3a795387b8"],
    "exportConfigurationOverrides": {
      "RoleAssignments": true,
      "PolicyDefinitions": true
    }
  }'
```

## ⚙️ **Configuration Management**

### **Adding New Subscriptions**

Simply edit `config/subscriptions.yaml`:

```yaml
subscriptions:
  # Existing subscription
  - id: "2be53ae5-6e46-47df-beb9-6f3a795387b8"
    name: "Production Primary"
    enabled: true
    priority: 1

  # Add new subscription
  - id: "new-subscription-id-here"
    name: "New Environment"
    description: "Description of new environment"
    enabled: true
    priority: 5
```

### **Disabling Subscriptions**

Set `enabled: false` to temporarily skip a subscription:

```yaml
  - id: "temp-disabled-subscription"
    name: "Maintenance Environment"
    enabled: false  # Will be skipped
    priority: 10
```

### **Priority Ordering**

Lower numbers = higher priority. Subscriptions are processed in priority order:

```yaml
  - priority: 1  # Processed first
  - priority: 2  # Processed second
  - priority: 3  # Processed third
```

## 🔧 **Export Settings**

### **Resource Types**

Control which Azure objects to export:

```yaml
exportSettings:
  subscriptionObjects: true      # VMs, storage, networks, etc.
  roleDefinitions: false         # RBAC role definitions
  resourceGroupDetails: true     # Resource group metadata
  roleAssignments: true          # RBAC assignments
  policyDefinitions: false       # Policy definitions
  policyAssignments: false       # Policy assignments
  policyExemptions: false        # Policy exemptions
  securityCenterSubscriptions: false  # Security Center settings
  includeChildResources: true    # Child objects (Event Hubs, subnets, etc.)
```

### **Filtering Options**

**Resource Group Filter:**

```yaml
resourceGroupFilters:
  - "rg-production-web"
  - "rg-production-data"
  # Only these resource groups will be exported
  # Leave empty to export all resource groups
```

**Resource Type Exclusions:**

```yaml
resourceTypeExclusions:
  - "Microsoft.Resources/deployments"
  - "Microsoft.Resources/deploymentScripts"
  # These resource types will be skipped
```

## 🔐 **Permissions Required**

**For each subscription in your configuration, the Managed Identity needs:**

```bash
# Reader permission (for resources)
az role assignment create \
  --assignee-object-id {managed-identity-object-id} \
  --role "Reader" \
  --scope "/subscriptions/2be53ae5-6e46-47df-beb9-6f3a795387b8"

# User Access Administrator (for role assignments - if enabled)
az role assignment create \
  --assignee-object-id {managed-identity-object-id} \
  --role "User Access Administrator" \
  --scope "/subscriptions/2be53ae5-6e46-47df-beb9-6f3a795387b8"
```

**Apply to all subscriptions in your config file.**

## 📊 **Monitoring & Telemetry**

### **Application Insights Events**

- `ConfigDrivenSubscriptionExportCompleted`
- `SubscriptionExportStarted` (per subscription)
- `SubscriptionExportCompleted` (per subscription)

### **Custom Properties Tracked**

- Configuration source and version
- Subscription processing statistics
- Per-subscription success/failure
- Performance metrics by stage

### **Export Data Structure**

Each exported object includes:

```json
{
  "OdataContext": "subscription-resources|resource-groups|child-resources",
  "ResourceType": "Microsoft.Storage/storageAccounts",
  "ResourceGroup": "my-resource-group",
  "SubscriptionId": "2be53ae5-6e46-47df-beb9-6f3a795387b8",
  "ExportId": "correlation-id",
  "Timestamp": "2025-01-31T10:30:00.000Z",
  "Data": {
    // Cleaned Azure resource object
  }
}
```

## 🛠️ **Troubleshooting**

### **Configuration File Issues**

1. **File not found**: Function falls back to environment variables
2. **Invalid YAML**: Check syntax, indentation (use spaces, not tabs)
3. **Invalid subscription IDs**: Must be valid GUIDs

### **Permission Issues**

1. Check Managed Identity has Reader role on each subscription
2. For role assignments, ensure User Access Administrator role
3. Verify subscription IDs are correct in configuration

### **Common Error Messages**

- `"No valid subscription IDs found"`: Check your configuration file syntax
- `"Authentication failed"`: Verify Managed Identity permissions
- `"Configuration file not found"`: Ensure file exists at `config/subscriptions.yaml`

## 🔄 **Migration from Environment Variables**

**If you currently use environment variables:**

1. **Create configuration file** with your subscription IDs
2. **Test with HTTP trigger** to verify configuration loads correctly
3. **Remove environment variables** (optional - config file takes priority)
4. **Timer trigger automatically uses config file**

**Environment variables still work as fallback if config file is missing!**

## 📈 **Benefits of Configuration Files**

✅ **Scalable**: Easy to manage hundreds of subscriptions
✅ **Version Control**: Track changes to subscription lists
✅ **Metadata Rich**: Names, descriptions, priorities
✅ **Flexible**: Enable/disable subscriptions without redeployment
✅ **Maintainable**: No character limits like environment variables
✅ **Auditable**: Clear history of configuration changes

## 🎯 **Next Steps**

1. **Review your initial configuration** in `config/subscriptions.yaml`
2. **Test with HTTP trigger** to ensure everything works
3. **Add additional subscriptions** as needed
4. **Configure permissions** for all subscriptions
5. **Monitor exports** via Application Insights

Your initial subscription `2be53ae5-6e46-47df-beb9-6f3a795387b8` is already configured and ready to export!
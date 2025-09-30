# Bicep Deployment Parameters

This document describes the parameters used in the Bicep deployment files and how to customize them for your specific deployment.

## Parameters

### `location`

- **Description**: The Azure region where the resources will be deployed.
- **Type**: `string`
- **Default**: The location of the resource group.
- **Example**: `"Australia SouthEast"`
- **Customization**: Set this to the Azure region where you want your resources to be deployed.

### `resourceGroupID`

- **Description**: The Resource Group for application deployment.
- **Type**: `string`
- **Default**: The existing resource group ID.
- **Example**: `"/subscriptions/1111111-1111-2222-3333-44444444/resourceGroups/Your-ResourceGroup"`
- **Customization**: Used as reference by the example PowerShell deployment script rather than functional in Bicep.

### `functionAppName`

- **Description**: The name of the Azure Function App.
- **Type**: `string`
- **Example**: `"userandgroupexporttoadx"`
- **Customization**: Provide a unique name for your Function App. This name must be globally unique within Azure.

### `storageAccountName`

- **Description**: The name of the Azure Storage Account.
- **Type**: `string`
- **Example**: `"userandgroupexport111"`
- **Customization**: Provide a unique name for your Storage Account. This name must be globally unique within Azure and follow the naming conventions for storage accounts.

### `applicationInsightsName`

- **Description**: The name of the Application Insights resource.
- **Type**: `string`
- **Example**: `"userandgroupexporttoadx"`
- **Customization**: Provide a unique name for your Application Insights resource. This name must be unique within your Azure subscription.

### `userAssignedIdentityResourceId`

- **Description**: The User Assigned Managed Identity Resource Id.
- **Type**: `string`
- **Example**: `"/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/{resourceName}"`
- **Customization**: Provide the User Assigned Managed Identity Resource Id. Ensure that this identity has the necessary permissions for accessing the resources required by your Function App.

## Example Parameters File

Below is an example of a `parameters.json` file with sample values:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "Australia East"
    },
    "resourceGroupID": {
      "value": "/subscriptions/1111111-1111-2222-3333-44444444/resourceGroups/Your-ResourceGroup"
    },
    "functionAppName": {
      "value": "userandgroupexporttoadx"
    },
    "storageAccountName": {
      "value": "userandgroupexport111"
    },
    "applicationInsightsName": {
      "value": "userandgroupexporttoadx"
    },
    "userAssignedIdentityResourceId": {
      "value": "/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/{resourceName}"
    },
    "eventHubNamespace": {
      "value": "ehns-ase-security"
    },
    "eventHubName": {
      "value": "AADGraph"
    }
  }
}
```

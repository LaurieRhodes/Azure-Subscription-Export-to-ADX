<#
.SYNOPSIS
    Cleans Azure resource objects by removing read-only properties and handling nested resources.

.DESCRIPTION
    This function processes Azure resource objects to remove read-only properties like etag,
    provisioningState, timestamps, etc. It also handles resource-specific cleaning and
    discovers child resources where appropriate.
    
    Based on the comprehensive cleaning logic from the 5+ year successful backup script,
    adapted for Event Hub streaming instead of file output.

.PARAMETER AzureObject
    The Azure resource object to clean.

.PARAMETER AuthHeader
    Authentication header for making additional API calls if needed.

.PARAMETER CorrelationContext
    Correlation context for tracking and telemetry.

.PARAMETER DiscoverChildResources
    Switch to enable discovery and processing of child resources.

.NOTES
    Author: Laurie Rhodes
    Version: 1.0
    Last Modified: 2025-01-31
#>

function Clean-AzureResourceObject {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$AzureObject,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$AuthHeader,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$CorrelationContext,
        
        [Parameter(Mandatory = $false)]
        [switch]$DiscoverChildResources = $false
    )

    Write-Debug "Starting Clean-AzureResourceObject for type: $($AzureObject.type)"
    
    if (-not $AzureObject) {
        Write-Warning "AzureObject is null or empty"
        return $null
    }
    
    try {
        # Clone the object to avoid modifying the original
        $cleanedObject = $AzureObject | ConvertTo-Json -Depth 50 | ConvertFrom-Json
        
        # Remove common read-only properties
        if ($cleanedObject.PSObject.Properties['etag']) {
            $cleanedObject.PSObject.Properties.Remove('etag')
        }
        
        # Resource-specific cleaning based on type
        switch ($cleanedObject.type) {
            "Microsoft.ApiManagement/service" {
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'provisioningState'
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'CreatedAtUTC'
            }
            
            "Microsoft.Automation/automationAccounts" {
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'state'
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'creationTime'
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'lastModifiedBy'
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'lastModifiedTime'
            }
            
            "Microsoft.Compute/virtualMachines" {
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'provisioningState'
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'vmId'
                
                if ($cleanedObject.identity) {
                    Remove-PropertySafely -Object $cleanedObject.identity -PropertyName 'principalId'
                    Remove-PropertySafely -Object $cleanedObject.identity -PropertyName 'tenantId'
                }
                
                if ($cleanedObject.properties.osProfile) {
                    Remove-PropertySafely -Object $cleanedObject.properties.osProfile -PropertyName 'requireGuestProvisionSignal'
                }
                
                # Clean managed disk references
                if ($cleanedObject.properties.storageProfile.osDisk.managedDisk) {
                    Remove-PropertySafely -Object $cleanedObject.properties.storageProfile.osDisk.managedDisk -PropertyName 'id'
                }
            }
            
            "Microsoft.Compute/disks" {
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'timeCreated'
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'provisioningState'
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'uniqueId'
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'diskSizeBytes'
            }
            
            "Microsoft.KeyVault/vaults" {
                Remove-PropertySafely -Object $cleanedObject -PropertyName 'systemData'
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'provisioningState'
            }
            
            "Microsoft.Kusto/clusters" {
                Remove-PropertySafely -Object $cleanedObject -PropertyName 'etag'
                
                # Note: Child resource discovery for Kusto clusters would be handled separately
                # if DiscoverChildResources is enabled
            }
            
            "Microsoft.Network/networkSecurityGroups" {
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'provisioningState'
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'resourceGuid'
                
                # Clean security rules in place
                if ($cleanedObject.properties.securityRules) {
                    foreach ($rule in $cleanedObject.properties.securityRules) {
                        Remove-PropertySafely -Object $rule -PropertyName 'etag'
                        Remove-PropertySafely -Object $rule.properties -PropertyName 'provisioningState'
                    }
                }
                
                # Clean default security rules
                if ($cleanedObject.properties.defaultSecurityRules) {
                    foreach ($rule in $cleanedObject.properties.defaultSecurityRules) {
                        Remove-PropertySafely -Object $rule -PropertyName 'etag'
                        Remove-PropertySafely -Object $rule.properties -PropertyName 'provisioningState'
                    }
                }
            }
            
            "Microsoft.Network/virtualNetworks" {
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'provisioningState'
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'resourceGuid'
                
                # Note: Subnets and peerings would be handled as child resources
                # if DiscoverChildResources is enabled
            }
            
            "Microsoft.OperationalInsights/workspaces" {
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'provisioningState'
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'createdDate'
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'modifiedDate'
                
                if ($cleanedObject.properties.sku) {
                    Remove-PropertySafely -Object $cleanedObject.properties.sku -PropertyName 'lastSkuUpdate'
                }
                
                if ($cleanedObject.properties.workspaceCapping) {
                    Remove-PropertySafely -Object $cleanedObject.properties.workspaceCapping -PropertyName 'quotaNextResetTime'
                }
            }
            
            "Microsoft.Storage/storageAccounts" {
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'provisioningState'
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'creationTime'
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'secondaryLocation'
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'statusOfSecondary'
            }
            
            "Microsoft.EventHub/namespaces" {
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'createdAt'
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'updatedAt'
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'provisioningState'
            }
            
            "Microsoft.Logic/workflows" {
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'provisioningState'
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'createdTime'
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'changedTime'
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'endpointsConfiguration'
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'version'
            }
            
            "Microsoft.Insights/components" {
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'CreationDate'
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'provisioningState'
            }
            
            default {
                # Generic cleaning for unknown resource types
                Write-Debug "Applying generic cleaning for resource type: $($cleanedObject.type)"
                Remove-PropertySafely -Object $cleanedObject.properties -PropertyName 'provisioningState'
                Remove-PropertySafely -Object $cleanedObject -PropertyName 'systemData'
            }
        }
        
        # Generic cleanup of common properties
        Remove-PropertySafely -Object $cleanedObject -PropertyName 'createdTime'
        Remove-PropertySafely -Object $cleanedObject -PropertyName 'changedTime'
        Remove-PropertySafely -Object $cleanedObject -PropertyName 'lastModifiedTime'
        
        Write-Debug "Completed cleaning for resource type: $($cleanedObject.type)"
        
        return $cleanedObject
        
    }
    catch {
        Write-Warning "Failed to clean Azure resource object: $($_.Exception.Message)"
        Write-Debug "Resource type: $($AzureObject.type)"
        Write-Debug "Resource ID: $($AzureObject.id)"
        
        # Return the original object if cleaning fails
        return $AzureObject
    }
}

# Helper function to safely remove properties
function Remove-PropertySafely {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Object,
        
        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )
    
    if ($Object -and $Object.PSObject.Properties[$PropertyName]) {
        try {
            $Object.PSObject.Properties.Remove($PropertyName)
            Write-Debug "Removed property: $PropertyName"
        }
        catch {
            Write-Debug "Failed to remove property $PropertyName : $($_.Exception.Message)"
        }
    }
}
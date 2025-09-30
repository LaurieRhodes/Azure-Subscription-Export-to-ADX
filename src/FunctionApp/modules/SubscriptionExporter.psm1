#
# SubscriptionExporter Module - Azure Subscription Data Export Module
# Author: Laurie Rhodes
# Version: 1.2.0
# Created: 2025-01-31
# Updated: 2025-09-28 - Added Resource Group handling fix
#
# This module provides comprehensive Azure subscription data export capabilities
# for integration with Azure Data Explorer via Event Hub.
# Based on proven architecture from 5+ years of successful subscription backup operations.
#

Write-Information "Loading SubscriptionExporter module v1.2.0..."

# Import private functions first (if any exist)
$privateFunctions = @(Get-ChildItem -Path $PSScriptRoot\private\*.ps1 -ErrorAction SilentlyContinue)

# Import public functions
$publicFunctions = @(Get-ChildItem -Path $PSScriptRoot\public\*.ps1 -ErrorAction SilentlyContinue)

Write-Information "Found $($publicFunctions.Count) public function files to load"

# Dot source all function files
foreach ($import in @($privateFunctions + $publicFunctions)) {
    try {
        Write-Verbose "Loading function file: $($import.FullName)"
        . $import.FullName
        Write-Verbose "Successfully loaded: $($import.Name)"
    }
    catch {
        Write-Error "Failed to import function $($import.FullName): $($_.Exception.Message)"
        throw
    }
}

# Export only the public functions listed in the manifest
$functionsToExport = @(
    # Core orchestration
    'Invoke-SubscriptionDataExport',
    'Invoke-MultiSubscriptionDataExport',
    'Invoke-ConfigDrivenSubscriptionExport',
    
    # Configuration management
    'Get-SubscriptionExportConfig',
    
    # Data export modules
    'Export-AzureSubscriptionResources',
    'Export-AzureResourceGroups', 
    'Export-AzureChildResources',
    
    # Discovery and API utilities
    'Get-AzureAPIVersions',
    'Get-AzureResourceEndpoints',
    'Get-AzureResourceDetails',      # Added - handles Resource Groups properly
    'Clean-AzureResourceObject',
    
    # Authentication (updated for ARM)
    'Get-AzureARMToken',
    
    # Event Hub integration (reused from AAD project)
    'Send-EventsToEventHub',
    
    # Error handling and resilience
    'Invoke-WithRetry',
    'Get-ErrorType',
    
    # Telemetry and monitoring
    'Write-CustomTelemetry',
    'Write-ExportProgress',
    'New-CorrelationContext',
    
    # Storage utilities (reused)
    'Get-AzTableStorageData',
    'Set-AzTableStorageData',
    'Get-Events',
    'Get-StorageTableValue',
    'Push-StorageTableValue'
)

# Only export functions that actually exist to avoid errors
$availableExports = @()
$missingFunctions = @()

foreach ($functionName in $functionsToExport) {
    if (Get-Command -Name $functionName -CommandType Function -ErrorAction SilentlyContinue) {
        $availableExports += $functionName
        Write-Verbose "Function available for export: $functionName"
    }
    else {
        $missingFunctions += $functionName
        Write-Warning "Function not found and will not be exported: $functionName"
    }
}

Write-Information "SubscriptionExporter module loaded successfully!"
Write-Information "  Available functions: $($availableExports.Count)"
Write-Information "  Missing functions: $($missingFunctions.Count)"

if ($missingFunctions.Count -gt 0) {
    Write-Warning "Missing functions: $($missingFunctions -join ', ')"
}

# Show critical functions status
$criticalFunctions = @('Invoke-ConfigDrivenSubscriptionExport', 'Get-SubscriptionExportConfig', 'Get-AzureARMToken', 'Get-AzureResourceDetails')
foreach ($func in $criticalFunctions) {
    if ($func -in $availableExports) {
        Write-Information "✅ Critical function available: $func"
    } else {
        Write-Warning "❌ Critical function missing: $func"
    }
}

Export-ModuleMember -Function $availableExports
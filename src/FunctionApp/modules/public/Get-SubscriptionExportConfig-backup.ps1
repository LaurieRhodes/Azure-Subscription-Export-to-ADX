<#
.SYNOPSIS
    Reads and parses YAML configuration files for subscription export settings.

.DESCRIPTION
    This function reads YAML configuration files from the config directory and converts
    them to PowerShell objects. Uses a simplified but robust YAML parser.

.PARAMETER ConfigFileName
    The name of the YAML configuration file to read (without extension).

.PARAMETER ConfigDirectory
    The directory containing configuration files. Defaults to config subfolder.

.NOTES
    Author: Laurie Rhodes
    Version: 1.4
    Last Modified: 2025-09-27
    
    Fixed hashtable addition error in YAML parser
#>

function Get-SubscriptionExportConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$ConfigFileName = "subscriptions",
        
        [Parameter(Mandatory = $false)]
        [string]$ConfigDirectory = $null
    )

    Write-Information "Loading subscription export configuration..."
    
    try {
        # Determine config directory path - fix for Azure Functions environment
        if (-not $ConfigDirectory) {
            # In Azure Functions, we need to go to the function app root, not the modules directory
            $functionAppRoot = $env:HOME
            if (-not $functionAppRoot) {
                # Fallback for local development or different environments
                $functionAppRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            } else {
                $functionAppRoot = Join-Path $functionAppRoot "site\wwwroot"
            }
            
            $ConfigDirectory = Join-Path $functionAppRoot "config"
        }
        
        $configPath = Join-Path $ConfigDirectory "$ConfigFileName.yaml"
        
        Write-Information "Function App Root: $functionAppRoot"
        Write-Information "Config Directory: $ConfigDirectory"
        Write-Information "Config file path: $configPath"
        
        # Debug: Check if directories exist
        Write-Information "Config directory exists: $(Test-Path $ConfigDirectory)"
        if (Test-Path $ConfigDirectory) {
            $configFiles = Get-ChildItem $ConfigDirectory -Filter "*.yaml" -ErrorAction SilentlyContinue
            Write-Information "Found YAML files in config directory: $($configFiles.Name -join ', ')"
        }
        
        if (-not (Test-Path $configPath)) {
            Write-Warning "Configuration file not found: $configPath"
            Write-Information "Falling back to environment variable configuration"
            return Get-FallbackConfiguration
        }
        
        # Read the YAML file
        $yamlContent = Get-Content -Path $configPath -Raw -Encoding UTF8
        
        Write-Information "YAML content loaded successfully (length: $($yamlContent.Length) chars)"
        
        # Parse YAML content with improved parser
        $config = ConvertFrom-SimpleYaml -YamlString $yamlContent
        
        if (-not $config) {
            throw "Failed to parse YAML configuration file"
        }
        
        Write-Information "Configuration parsed successfully"
        
        # Validate and process configuration
        $processedConfig = Process-SubscriptionConfig -Config $config
        
        Write-Information "Configuration processing completed"
        Write-Information "Found $($processedConfig.Subscriptions.Count) enabled subscriptions"
        
        return $processedConfig
        
    }
    catch {
        Write-Error "Failed to load configuration: $($_.Exception.Message)"
        Write-Error "Stack trace: $($_.ScriptStackTrace)"
        Write-Information "Falling back to environment variable configuration"
        return Get-FallbackConfiguration
    }
}

function ConvertFrom-SimpleYaml {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$YamlString
    )
    
    Write-Information "Starting simple YAML parsing..."
    
    try {
        # Clean up the YAML content
        $lines = $YamlString -split "`r?`n" | ForEach-Object {
            $line = $_.TrimEnd()
            # Remove comments (but be careful about quotes)
            if ($line.Contains('#') -and -not ($line.Contains('"') -or $line.Contains("'"))) {
                $line = ($line -split '#')[0].TrimEnd()
            }
            $line
        } | Where-Object { $_.Trim() -ne '' }
        
        Write-Information "Processing $($lines.Count) non-empty lines"
        
        # Use a more robust parsing approach with PSObject instead of hashtables
        $result = New-Object PSObject
        $currentObject = $result
        $objectStack = @()
        $currentIndent = 0
        
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            $trimmed = $line.Trim()
            $indent = ($line.Length - $line.TrimStart().Length) / 2  # Assume 2-space indentation
            
            Write-Debug "Line $i (indent $indent): '$trimmed'"
            
            # Handle indentation changes
            while ($objectStack.Count -gt 0 -and $indent -le $objectStack[-1].Indent) {
                $objectStack.RemoveAt($objectStack.Count - 1)
                if ($objectStack.Count -gt 0) {
                    $currentObject = $objectStack[-1].Object
                    $currentIndent = $objectStack[-1].Indent
                } else {
                    $currentObject = $result
                    $currentIndent = 0
                }
            }
            
            if ($trimmed.StartsWith('- ')) {
                # Array item
                $itemContent = $trimmed.Substring(2).Trim()
                
                # Find the parent property that should be an array
                $parentProperty = $null
                if ($objectStack.Count -gt 0) {
                    $parentProperty = $objectStack[-1].ArrayProperty
                }
                
                if (-not $parentProperty) {
                    Write-Warning "Array item found without parent property: $trimmed"
                    continue
                }
                
                # Ensure parent property is initialized as array
                if (-not $currentObject.PSObject.Properties[$parentProperty]) {
                    $currentObject | Add-Member -NotePropertyName $parentProperty -NotePropertyValue @()
                } elseif ($currentObject.$parentProperty -isnot [Array]) {
                    $currentObject.$parentProperty = @($currentObject.$parentProperty)
                }
                
                if ($itemContent.Contains(':')) {
                    # Object in array
                    $arrayItem = New-Object PSObject
                    
                    # Parse the first key-value pair
                    $parts = $itemContent -split ':', 2
                    $key = $parts[0].Trim()
                    $value = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }
                    $arrayItem | Add-Member -NotePropertyName $key -NotePropertyValue (Convert-SimpleYamlValue $value)
                    
                    # Look ahead for more properties of this array item
                    $nextIndent = $indent + 1
                    $j = $i + 1
                    while ($j -lt $lines.Count) {
                        $nextLine = $lines[$j]
                        $nextTrimmed = $nextLine.Trim()
                        $nextLineIndent = ($nextLine.Length - $nextLine.TrimStart().Length) / 2
                        
                        if ($nextLineIndent -le $indent) {
                            break # End of this array item
                        }
                        
                        if ($nextLineIndent -eq $nextIndent -and $nextTrimmed.Contains(':') -and -not $nextTrimmed.StartsWith('-')) {
                            $nextParts = $nextTrimmed -split ':', 2
                            $nextKey = $nextParts[0].Trim()
                            $nextValue = if ($nextParts.Count -gt 1) { $nextParts[1].Trim() } else { '' }
                            $arrayItem | Add-Member -NotePropertyName $nextKey -NotePropertyValue (Convert-SimpleYamlValue $nextValue)
                            $i = $j  # Skip this line in main loop
                        }
                        $j++
                    }
                    
                    # Add the array item
                    $currentObject.$parentProperty += $arrayItem
                } else {
                    # Simple array item
                    $currentObject.$parentProperty += Convert-SimpleYamlValue $itemContent
                }
            } elseif ($trimmed.Contains(':')) {
                # Key-value pair
                $parts = $trimmed -split ':', 2
                $key = $parts[0].Trim()
                $value = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }
                
                if ([string]::IsNullOrWhiteSpace($value)) {
                    # This is a section header or array key
                    $newObject = New-Object PSObject
                    $currentObject | Add-Member -NotePropertyName $key -NotePropertyValue $newObject
                    
                    # Push current context to stack
                    $objectStack += @{
                        Object = $currentObject
                        Indent = $currentIndent
                        ArrayProperty = $key
                    }
                    
                    $currentObject = $newObject
                    $currentIndent = $indent
                } else {
                    # Regular key-value pair
                    $currentObject | Add-Member -NotePropertyName $key -NotePropertyValue (Convert-SimpleYamlValue $value)
                }
            }
        }
        
        Write-Information "YAML parsing completed successfully"
        
        # Get property names for debugging
        $propertyNames = $result.PSObject.Properties.Name
        Write-Information "Top-level properties: $($propertyNames -join ', ')"
        
        return $result
        
    }
    catch {
        Write-Error "Simple YAML parsing failed: $($_.Exception.Message)"
        Write-Error "Error at line: $($_.InvocationInfo.ScriptLineNumber)"
        Write-Error "Full error: $($_.Exception | ConvertTo-Json -Depth 3)"
        throw
    }
}

function Convert-SimpleYamlValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Value = ''
    )
    
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }
    
    $trimmed = $Value.Trim().Trim('"', "'")
    
    # Boolean values
    if ($trimmed -ieq 'true') { return $true }
    if ($trimmed -ieq 'false') { return $false }
    if ($trimmed -ieq 'null') { return $null }
    
    # Numeric values
    if ($trimmed -match '^\d+$') {
        return [int]$trimmed
    }
    
    if ($trimmed -match '^\d+\.\d+$') {
        return [double]$trimmed
    }
    
    # String values
    return $trimmed
}

function Process-SubscriptionConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )
    
    Write-Information "Processing subscription configuration..."
    
    # Initialize processed configuration
    $processedConfig = @{
        Metadata = if ($Config.metadata) { $Config.metadata } else { @{} }
        Subscriptions = @()
        ExportSettings = @{}
        ResourceGroupFilters = @()
        ResourceTypeExclusions = @()
        Advanced = @{}
    }
    
    # Process subscriptions
    if ($Config.subscriptions) {
        Write-Information "Processing subscriptions array with $($Config.subscriptions.Count) items"
        
        foreach ($subscription in $Config.subscriptions) {
            Write-Information "Processing subscription: $($subscription.name) - ID: $($subscription.id) - Enabled: $($subscription.enabled)"
            
            # Only include enabled subscriptions
            if ($subscription.enabled -eq $true) {
                $processedConfig.Subscriptions += @{
                    Id = $subscription.id
                    Name = $subscription.name
                    Description = if ($subscription.description) { $subscription.description } else { "" }
                    Priority = if ($subscription.priority) { [int]$subscription.priority } else { 999 }
                }
                
                Write-Information "✅ Added enabled subscription: $($subscription.name) ($($subscription.id))"
            } else {
                Write-Information "⏭️  Skipped disabled subscription: $($subscription.name)"
            }
        }
        
        # Sort by priority
        $processedConfig.Subscriptions = $processedConfig.Subscriptions | Sort-Object Priority
        
        Write-Information "Final subscription count: $($processedConfig.Subscriptions.Count) enabled subscriptions"
    } else {
        Write-Warning "❌ No subscriptions section found in configuration"
    }
    
    # Process export settings with defaults
    $defaultExportSettings = @{
        SubscriptionObjects = $true
        RoleDefinitions = $false
        ResourceGroupDetails = $true
        RoleAssignments = $true
        PolicyDefinitions = $false
        PolicyAssignments = $false
        PolicyExemptions = $false
        SecurityCenterSubscriptions = $false
        IncludeChildResources = $true
    }
    
    if ($Config.exportSettings) {
        Write-Information "Processing export settings from config"
        $processedConfig.ExportSettings = @{
            SubscriptionObjects = Get-ConfigValue $Config.exportSettings.subscriptionObjects $defaultExportSettings.SubscriptionObjects
            RoleDefinitions = Get-ConfigValue $Config.exportSettings.roleDefinitions $defaultExportSettings.RoleDefinitions
            ResourceGroupDetails = Get-ConfigValue $Config.exportSettings.resourceGroupDetails $defaultExportSettings.ResourceGroupDetails
            RoleAssignments = Get-ConfigValue $Config.exportSettings.roleAssignments $defaultExportSettings.RoleAssignments
            PolicyDefinitions = Get-ConfigValue $Config.exportSettings.policyDefinitions $defaultExportSettings.PolicyDefinitions
            PolicyAssignments = Get-ConfigValue $Config.exportSettings.policyAssignments $defaultExportSettings.PolicyAssignments
            PolicyExemptions = Get-ConfigValue $Config.exportSettings.policyExemptions $defaultExportSettings.PolicyExemptions
            SecurityCenterSubscriptions = Get-ConfigValue $Config.exportSettings.securityCenterSubscriptions $defaultExportSettings.SecurityCenterSubscriptions
            IncludeChildResources = Get-ConfigValue $Config.exportSettings.includeChildResources $defaultExportSettings.IncludeChildResources
        }
    } else {
        Write-Information "Using default export settings"
        $processedConfig.ExportSettings = $defaultExportSettings
    }
    
    Write-Information "Configuration processing completed successfully"
    return $processedConfig
}

function Get-ConfigValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        $Value,
        
        [Parameter(Mandatory = $true)]
        $DefaultValue
    )
    
    if ($null -ne $Value) {
        return $Value
    } else {
        return $DefaultValue
    }
}

function Get-FallbackConfiguration {
    [CmdletBinding()]
    param ()
    
    Write-Information "Using fallback configuration from environment variables"
    
    # Get subscriptions from environment variables
    $subscriptions = @()
    
    if ($env:ALL_SUBSCRIPTION_IDS) {
        $allSubs = $env:ALL_SUBSCRIPTION_IDS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        foreach ($sub in $allSubs) {
            $subscriptions += @{
                Id = $sub
                Name = "Subscription-$sub"
                Description = "From ALL_SUBSCRIPTION_IDS"
                Priority = 1
            }
        }
    } else {
        if ($env:SUBSCRIPTION_ID) {
            $subscriptions += @{
                Id = $env:SUBSCRIPTION_ID
                Name = "Primary-Subscription"
                Description = "From SUBSCRIPTION_ID"
                Priority = 1
            }
        }
        
        if ($env:ADDITIONAL_SUBSCRIPTION_IDS) {
            $additionalSubs = $env:ADDITIONAL_SUBSCRIPTION_IDS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
            foreach ($sub in $additionalSubs) {
                $subscriptions += @{
                    Id = $sub
                    Name = "Additional-$sub"
                    Description = "From ADDITIONAL_SUBSCRIPTION_IDS"
                    Priority = 2
                }
            }
        }
    }
    
    Write-Information "Environment variable fallback found $($subscriptions.Count) subscriptions"
    
    return @{
        Metadata = @{
            version = "1.0-fallback"
            description = "Fallback configuration from environment variables"
            source = "environment"
        }
        Subscriptions = $subscriptions
        ExportSettings = @{
            SubscriptionObjects = $true
            RoleDefinitions = $false
            ResourceGroupDetails = $true
            RoleAssignments = $true
            PolicyDefinitions = $false
            PolicyAssignments = $false
            PolicyExemptions = $false
            SecurityCenterSubscriptions = $false
            IncludeChildResources = $true
        }
        ResourceGroupFilters = @()
        ResourceTypeExclusions = @()
        Advanced = @{
            VerboseTelemetry = $false
            EnableProfiling = $false
            CustomTags = @{}
        }
    }
}
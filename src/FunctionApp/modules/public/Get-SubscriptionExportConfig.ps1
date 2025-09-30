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
    Version: 1.9 - FIXED NESTED SUBSCRIPTIONS
    Last Modified: 2025-09-27
    
    FIXED: Handle nested subscriptions structure from YAML parser
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
        
        # ENHANCED: Debug the parsed configuration structure
        Write-Information "=== PARSED CONFIGURATION DEBUG ==="
        if ($config.PSObject.Properties.Name) {
            Write-Information "Top-level properties: $($config.PSObject.Properties.Name -join ', ')"
            
            if ($config.subscriptions) {
                Write-Information "Subscriptions property found"
                Write-Information "Subscriptions type: $($config.subscriptions.GetType().Name)"
                if ($config.subscriptions -is [Array]) {
                    Write-Information "Subscriptions array count: $($config.subscriptions.Count)"
                    for ($i = 0; $i -lt $config.subscriptions.Count; $i++) {
                        $sub = $config.subscriptions[$i]
                        Write-Information "  Subscription $($i):"
                        Write-Information "    Type: $($sub.GetType().Name)"
                        if ($sub.PSObject.Properties.Name) {
                            Write-Information "    Properties: $($sub.PSObject.Properties.Name -join ', ')"
                            if ($sub.id) { Write-Information "    id: $($sub.id)" }
                            if ($sub.name) { Write-Information "    name: $($sub.name)" }
                            if ($sub.enabled -ne $null) { Write-Information "    enabled: $($sub.enabled)" }
                        }
                    }
                } else {
                    Write-Information "Subscriptions is not an array: $($config.subscriptions)"
                    # Check if it's a nested structure
                    if ($config.subscriptions.PSObject.Properties.Name -contains "subscriptions") {
                        Write-Information "Found nested subscriptions structure!"
                        Write-Information "Nested subscriptions type: $($config.subscriptions.subscriptions.GetType().Name)"
                        if ($config.subscriptions.subscriptions -is [Array]) {
                            Write-Information "Nested subscriptions array count: $($config.subscriptions.subscriptions.Count)"
                        }
                    }
                }
            } else {
                Write-Warning "❌ No subscriptions property found in parsed config"
            }
            
            if ($config.exportSettings) {
                Write-Information "Export settings found: $($config.exportSettings.PSObject.Properties.Name -join ', ')"
            } else {
                Write-Warning "❌ No exportSettings property found"
            }
        } else {
            Write-Warning "❌ Parsed config has no properties"
        }
        Write-Information "=== END CONFIGURATION DEBUG ==="
        
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
        # FIXED: Improved comment removal and line filtering
        $lines = $YamlString -split "`r?`n" | ForEach-Object {
            $line = $_.TrimEnd()
            
            # Skip completely commented lines (lines that start with # after trimming)
            $trimmedLine = $line.Trim()
            if ($trimmedLine.StartsWith('#')) {
                return $null  # Skip this line entirely
            }
            
            # For lines that contain comments but aren't entirely comments, remove the comment part
            # But be careful about quotes
            if ($line.Contains('#')) {
                # Check if the # is inside quotes
                $inQuotes = $false
                $quoteChar = $null
                $commentIndex = -1
                
                for ($i = 0; $i -lt $line.Length; $i++) {
                    $char = $line[$i]
                    
                    if ($char -eq '"' -or $char -eq "'") {
                        if (-not $inQuotes) {
                            $inQuotes = $true
                            $quoteChar = $char
                        } elseif ($char -eq $quoteChar) {
                            $inQuotes = $false
                            $quoteChar = $null
                        }
                    } elseif ($char -eq '#' -and -not $inQuotes) {
                        $commentIndex = $i
                        break
                    }
                }
                
                if ($commentIndex -ge 0) {
                    $line = $line.Substring(0, $commentIndex).TrimEnd()
                }
            }
            
            return $line
        } | Where-Object { $_ -ne $null -and $_.Trim() -ne '' }
        
        Write-Information "Processing $($lines.Count) non-empty, non-comment lines"
        
        # Debug: Show first few lines being processed
        for ($i = 0; $i -lt [Math]::Min(5, $lines.Count); $i++) {
            Write-Debug "Line $($i): '$($lines[$i])'"
        }
        
        # Use a more robust parsing approach with ArrayList for dynamic stack management
        $result = New-Object PSObject
        $currentObject = $result
        
        # FIXED: Use ArrayList instead of regular array to avoid "fixed size" error
        $objectStack = New-Object System.Collections.ArrayList
        $currentIndent = 0
        
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            $trimmed = $line.Trim()
            $indent = ($line.Length - $line.TrimStart().Length) / 2  # Assume 2-space indentation
            
            Write-Debug "Processing line $($i) (indent $($indent)): '$($trimmed)'"
            
            # Skip any remaining comment lines that might have slipped through
            if ($trimmed.StartsWith('#')) {
                Write-Debug "Skipping comment line: $($trimmed)"
                continue
            }
            
            # Handle indentation changes - FIXED: Use ArrayList methods
            while ($objectStack.Count -gt 0 -and $indent -le $objectStack[$objectStack.Count - 1].Indent) {
                # FIXED: Use ArrayList RemoveAt method instead of array RemoveAt
                $objectStack.RemoveAt($objectStack.Count - 1) | Out-Null
                
                if ($objectStack.Count -gt 0) {
                    $currentObject = $objectStack[$objectStack.Count - 1].Object
                    $currentIndent = $objectStack[$objectStack.Count - 1].Indent
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
                    $parentProperty = $objectStack[$objectStack.Count - 1].ArrayProperty
                }
                
                if (-not $parentProperty) {
                    Write-Warning "Array item found without parent property: $($trimmed)"
                    continue
                }
                
                Write-Debug "Adding array item to property: $($parentProperty)"
                
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
                    
                    Write-Debug "Created array item with $($key): $($value)"
                    
                    # Look ahead for more properties of this array item
                    $nextIndent = $indent + 1
                    $j = $i + 1
                    while ($j -lt $lines.Count) {
                        $nextLine = $lines[$j]
                        $nextTrimmed = $nextLine.Trim()
                        $nextLineIndent = ($nextLine.Length - $nextLine.TrimStart().Length) / 2
                        
                        # Skip comments that might be in the middle of array items
                        if ($nextTrimmed.StartsWith('#')) {
                            $j++
                            continue
                        }
                        
                        if ($nextLineIndent -le $indent) {
                            break # End of this array item
                        }
                        
                        if ($nextLineIndent -eq $nextIndent -and $nextTrimmed.Contains(':') -and -not $nextTrimmed.StartsWith('-')) {
                            $nextParts = $nextTrimmed -split ':', 2
                            $nextKey = $nextParts[0].Trim()
                            $nextValue = if ($nextParts.Count -gt 1) { $nextParts[1].Trim() } else { '' }
                            $arrayItem | Add-Member -NotePropertyName $nextKey -NotePropertyValue (Convert-SimpleYamlValue $nextValue)
                            Write-Debug "Added property to array item: $($nextKey) = $($nextValue)"
                            $i = $j  # Skip this line in main loop
                        }
                        $j++
                    }
                    
                    # Add the array item - ensure we're working with a mutable array
                    $tempArray = @($currentObject.$parentProperty)
                    $tempArray += $arrayItem
                    $currentObject.$parentProperty = $tempArray
                    
                    Write-Debug "Array item added. Total items in $($parentProperty): $($currentObject.$parentProperty.Count)"
                } else {
                    # Simple array item
                    $tempArray = @($currentObject.$parentProperty)
                    $tempArray += Convert-SimpleYamlValue $itemContent
                    $currentObject.$parentProperty = $tempArray
                }
            } elseif ($trimmed.Contains(':')) {
                # Key-value pair
                $parts = $trimmed -split ':', 2
                $key = $parts[0].Trim()
                $value = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }
                
                # FIXED: Validate that key doesn't start with # (additional safety check)
                if ($key.StartsWith('#')) {
                    Write-Debug "Skipping key that starts with comment: $($key)"
                    continue
                }
                
                if ([string]::IsNullOrWhiteSpace($value)) {
                    # This is a section header or array key
                    $newObject = New-Object PSObject
                    
                    Write-Debug "Creating new section: $($key)"
                    
                    # FIXED: Check if property already exists before adding
                    if ($currentObject.PSObject.Properties[$key]) {
                        Write-Debug "Property '$($key)' already exists, updating instead of adding"
                        $currentObject.$key = $newObject
                    } else {
                        $currentObject | Add-Member -NotePropertyName $key -NotePropertyValue $newObject
                    }
                    
                    # Push current context to stack - FIXED: Use ArrayList Add method
                    $stackItem = @{
                        Object = $currentObject
                        Indent = $currentIndent
                        ArrayProperty = $key
                    }
                    $objectStack.Add($stackItem) | Out-Null
                    
                    $currentObject = $newObject
                    $currentIndent = $indent
                } else {
                    # Regular key-value pair
                    Write-Debug "Adding property: $($key) = $($value)"
                    
                    # FIXED: Check if property already exists before adding
                    if ($currentObject.PSObject.Properties[$key]) {
                        Write-Debug "Property '$($key)' already exists, updating value"
                        $currentObject.$key = Convert-SimpleYamlValue $value
                    } else {
                        $currentObject | Add-Member -NotePropertyName $key -NotePropertyValue (Convert-SimpleYamlValue $value)
                    }
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
    
    # ENHANCED: Debug subscription processing
    Write-Information "=== SUBSCRIPTION PROCESSING DEBUG ==="
    
    # FIXED: Handle nested subscriptions structure
    $subscriptionsData = $null
    
    if ($Config.subscriptions) {
        Write-Information "Subscriptions property exists"
        Write-Information "Type: $($Config.subscriptions.GetType().Name)"
        
        # Check if subscriptions is directly an array
        if ($Config.subscriptions -is [Array]) {
            $subscriptionsData = $Config.subscriptions
            Write-Information "Subscriptions is directly an array with $($subscriptionsData.Count) items"
        }
        # Check if subscriptions is a PSCustomObject with a nested subscriptions property
        elseif ($Config.subscriptions.PSObject.Properties.Name -contains "subscriptions") {
            $subscriptionsData = $Config.subscriptions.subscriptions
            Write-Information "Found nested subscriptions structure"
            Write-Information "Nested subscriptions type: $($subscriptionsData.GetType().Name)"
            if ($subscriptionsData -is [Array]) {
                Write-Information "Nested subscriptions is an array with $($subscriptionsData.Count) items"
            }
        }
        else {
            Write-Warning "❌ Subscriptions structure not recognized: $($Config.subscriptions)"
        }
    } else {
        Write-Warning "❌ No subscriptions section found in configuration"
    }
    
    if ($subscriptionsData -and $subscriptionsData -is [Array]) {
        Write-Information "Processing subscriptions array with $($subscriptionsData.Count) items"
        
        for ($i = 0; $i -lt $subscriptionsData.Count; $i++) {
            $subscription = $subscriptionsData[$i]
            Write-Information "Processing subscription index $($i):"
            Write-Information "  Type: $($subscription.GetType().Name)"
            Write-Information "  Properties: $($subscription.PSObject.Properties.Name -join ', ')"
            Write-Information "  Name: $($subscription.name)"
            Write-Information "  ID: $($subscription.id)"
            Write-Information "  Enabled: $($subscription.enabled) (Type: $($subscription.enabled.GetType().Name))"
            
            # Only include enabled subscriptions
            if ($subscription.enabled -eq $true) {
                $newSub = @{
                    Id = $subscription.id
                    Name = $subscription.name
                    Description = if ($subscription.description) { $subscription.description } else { "" }
                    Priority = if ($subscription.priority) { [int]$subscription.priority } else { 999 }
                }
                $processedConfig.Subscriptions += $newSub
                
                Write-Information "✅ Added enabled subscription: $($subscription.name) ($($subscription.id))"
            } else {
                Write-Information "⏭️  Skipped disabled subscription: $($subscription.name)"
            }
        }
        
        # Sort by priority
        $processedConfig.Subscriptions = $processedConfig.Subscriptions | Sort-Object Priority
        
        Write-Information "Final subscription count: $($processedConfig.Subscriptions.Count) enabled subscriptions"
    } else {
        Write-Warning "❌ No valid subscriptions array found"
    }
    
    Write-Information "=== END SUBSCRIPTION PROCESSING DEBUG ==="
    
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
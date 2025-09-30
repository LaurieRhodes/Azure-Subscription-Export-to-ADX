<#
.SYNOPSIS
    Enhanced Azure AD Groups export with comprehensive property retrieval using multiple API calls.

.DESCRIPTION
    This module exports Azure AD groups to Event Hub for ADX ingestion with complete property coverage.
    Uses multiple API calls to overcome Graph API property selection limits and retrieves all available
    group properties from Microsoft Graph v1.0 endpoint.

.PARAMETER AuthHeader
    Authentication headers for Microsoft Graph API calls.

.PARAMETER CorrelationContext
    Correlation context containing operation ID and tracking information.

.PARAMETER IncludeExchangeProperties
    Switch to include Exchange-stored properties that require individual API calls.

.NOTES
    Author: Laurie Rhodes
    Version: 4.1
    Last Modified: 2025-09-02
    
    Key Features:
    - Complete group property coverage using multiple API calls
    - Intelligent batching to overcome Graph API $select limitations
    - Consolidated group objects for Event Hub transmission
    - Enhanced error handling and performance monitoring
    - Production-ready v1.0 Graph API endpoints exclusively

.CHANGES
    Version 4.1 Changes:
    - Fixed invalid property references causing 400 Bad Request errors
    - Removed properties not available in v1.0 endpoint
    - Updated property groups to use only valid v1.0 properties
    - Added better error handling for property validation
#>

function Export-AADGroups {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$AuthHeader,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$CorrelationContext,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeExchangeProperties = $false
    )
    
    # Initialize tracking variables
    $groupStageStart = Get-Date
    $groupCount = 0
    $batchCount = 0
    $processedExchange = 0
    $AllGroupIDs = @()
    $errors = @()
    
    # Base telemetry properties
    $baseTelemetryProps = $CorrelationContext.Clone()
    $baseTelemetryProps['ApiEndpoint'] = 'Groups'
    $baseTelemetryProps['ApiVersion'] = 'v1.0'
    $baseTelemetryProps['ComprehensiveProperties'] = $true
    
    Write-Information "Starting Groups Export - Comprehensive Properties Mode (v4.1)"
    Write-Information "Enhanced mode: Multiple API calls for complete property coverage"
    
    try {
        # Stage 1: Basic Group List with Core Properties
        $basicResult = Export-GroupsBasicProperties -AuthHeader $AuthHeader -BaseTelemetryProps $baseTelemetryProps -CorrelationContext $CorrelationContext
        $groupCount = $basicResult.GroupCount
        $groupIds = $basicResult.GroupIds
        $basicGroupData = $basicResult.GroupData
        $AllGroupIDs = $basicResult.GroupIds
        
        Write-Information "Stage 1 Complete - Basic properties for $groupCount groups"
        
        # Stage 2: Enhanced Properties Retrieval (Multiple API Calls)
        $enhancedResult = Export-GroupsEnhancedProperties -AuthHeader $AuthHeader -GroupIds $groupIds -BasicGroupData $basicGroupData -BaseTelemetryProps $baseTelemetryProps -CorrelationContext $CorrelationContext
        $consolidatedGroups = $enhancedResult.ConsolidatedGroups
        $batchCount += $enhancedResult.BatchCount
        
        Write-Information "Stage 2 Complete - Enhanced properties consolidated for $($consolidatedGroups.Count) groups"
        
        # Stage 3: Exchange Properties Export (if enabled)
        if ($IncludeExchangeProperties -and $groupIds.Count -gt 0) {
            Write-Information "Stage 3: Processing Exchange-stored properties for $($groupIds.Count) groups..."
            $exchangeResult = Export-GroupsExchangeProperties -AuthHeader $AuthHeader -GroupIds $groupIds -ConsolidatedGroups $consolidatedGroups -BaseTelemetryProps $baseTelemetryProps -CorrelationContext $CorrelationContext
            $consolidatedGroups = $exchangeResult.ConsolidatedGroups
            $processedExchange = $exchangeResult.ProcessedCount
            $batchCount += $exchangeResult.BatchCount
            $errors = $exchangeResult.Errors
            
            Write-Information "Stage 3 Complete - Exchange properties for $processedExchange groups"
        }
        
        # Stage 4: Final Event Hub Transmission
        $transmissionResult = Export-ConsolidatedGroupsToEventHub -ConsolidatedGroups $consolidatedGroups -BaseTelemetryProps $baseTelemetryProps -CorrelationContext $CorrelationContext
        $batchCount += $transmissionResult.BatchCount
        
        Write-Information "Stage 4 Complete - Transmitted $($consolidatedGroups.Count) complete group records"
        
        # Calculate final metrics
        $totalGroupsDuration = ((Get-Date) - $groupStageStart).TotalMilliseconds
        
        # Log completion telemetry - Fixed property count calculation
        $completionProps = $baseTelemetryProps.Clone()
        $completionProps['TotalGroups'] = $groupCount
        $completionProps['ConsolidatedGroups'] = $consolidatedGroups.Count
        $completionProps['ExchangePropertiesProcessed'] = $processedExchange
        $completionProps['TotalBatches'] = $batchCount
        $completionProps['DurationMs'] = $totalGroupsDuration
        $completionProps['ErrorCount'] = $errors.Count
        # FIXED: Proper property count calculation for consolidated groups
        $completionProps['PropertiesPerGroup'] = if ($consolidatedGroups.Count -gt 0 -and $null -ne $consolidatedGroups[0]) { 
            ($consolidatedGroups[0] | Get-Member -MemberType Properties).Count 
        } else { 
            0 
        }
        
        $metrics = @{
            'GroupsPerMinute' = if ($totalGroupsDuration -gt 0) { [Math]::Round($groupCount / ($totalGroupsDuration / 60000), 0) } else { 0 }
            'BatchesCreated' = $batchCount
            'PropertiesCoverage' = $completionProps['PropertiesPerGroup']
        }
        
        Write-CustomTelemetry -EventName "GroupsExportComprehensiveCompleted" -Properties $completionProps -Metrics $metrics
        
        Write-Information "=== Groups Export Completed Successfully (v4.1) ==="
        Write-Information "  - Total Groups: $groupCount"
        Write-Information "  - Consolidated Records: $($consolidatedGroups.Count)"
        Write-Information "  - Properties Per Group: $($completionProps['PropertiesPerGroup'])"
        Write-Information "  - Exchange Properties: $processedExchange groups"
        Write-Information "  - Total Batches: $batchCount"
        Write-Information "  - Duration: $([Math]::Round($totalGroupsDuration/1000, 2)) seconds"
        Write-Information "  - Errors: $($errors.Count)"
        
        return @{
            Success = $true
            GroupCount = $groupCount
            ConsolidatedGroups = $consolidatedGroups.Count
            ExchangePropertiesCount = $processedExchange
            BatchCount = $batchCount
            DurationMs = $totalGroupsDuration
            PropertiesPerGroup = $completionProps['PropertiesPerGroup']
            AllGroupIDs = $AllGroupIDs
            Errors = $errors
        }
        
    }
    catch {
        # Single-level error handling - no nested catch blocks
        $errorMessage = $_.Exception.Message
        $errorType = Get-ErrorType -Exception $_
        
        $errorDetails = @{
            ExportId = $CorrelationContext.OperationId
            Stage = 'GroupsExportComprehensive'
            ErrorMessage = $errorMessage
            ErrorType = $errorType
            ProcessedGroups = $groupCount
            FailureTimestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        }
        
        Write-CustomTelemetry -EventName "GroupsExportComprehensiveFailed" -Properties $errorDetails
        Write-Error "Comprehensive Groups Export failed after processing $groupCount groups - $errorMessage"
        
        return @{
            Success = $false
            GroupCount = $groupCount
            ConsolidatedGroups = 0
            ExchangePropertiesCount = $processedExchange
            BatchCount = $batchCount
            AllGroupIDs = $AllGroupIDs
            Error = $errorDetails
        }
    }
}

# Helper function for basic group properties (first API call)
function Export-GroupsBasicProperties {
    [CmdletBinding()]
    param (
        [hashtable]$AuthHeader,
        [hashtable]$BaseTelemetryProps,
        [hashtable]$CorrelationContext
    )
    
    $groupCount = 0
    $groupIds = @()
    $groupData = @{}
    
    # Basic properties that are returned by default (always available)
    $basicProperties = @(
        'id', 'displayName', 'description', 'mail', 'mailEnabled', 'mailNickname',
        'securityEnabled', 'groupTypes', 'visibility', 'createdDateTime'
    )
    
    $groupsApiUrl = "https://graph.microsoft.com/v1.0/groups?`$select=$($basicProperties -join ',')&`$top=999"
    
    do {
        # Graph API call with retry logic
        $groupProps = $BaseTelemetryProps.Clone()
        $groupProps['Stage'] = 'BasicProperties'
        $groupProps['PageUrl'] = $groupsApiUrl
        
        $response = Invoke-GraphAPIWithRetry -Uri $groupsApiUrl -Headers $AuthHeader -CorrelationContext $groupProps -MaxRetryCount 5
        
        Write-Information "Retrieved $($response.value.Count) groups with basic properties"

        # Store basic group data
        foreach ($group in $response.value) {
            $groupData[$group.id] = $group
            $groupIds += $group.id
            $groupCount++
        }

        # Get next page URL
        $groupsApiUrl = $response.'@odata.nextLink'

    } while ($null -ne $groupsApiUrl)
    
    return @{
        GroupCount = $groupCount
        GroupIds = $groupIds
        GroupData = $groupData
    }
}

# Helper function for enhanced properties (multiple targeted API calls)
function Export-GroupsEnhancedProperties {
    [CmdletBinding()]
    param (
        [hashtable]$AuthHeader,
        [array]$GroupIds,
        [hashtable]$BasicGroupData,
        [hashtable]$BaseTelemetryProps,
        [hashtable]$CorrelationContext
    )
    
    Write-Information "Starting enhanced properties retrieval for $($GroupIds.Count) groups using multiple API calls"
    
    # Define property groups to overcome $select limitations (v1.0 validated properties only)
    # Group 1: Core Identity and Classification Properties
    $identityProperties = @(
        'id', 'deletedDateTime', 'classification', 'createdDateTime', 'creationOptions',
        'expirationDateTime', 'isAssignableToRole', 'securityIdentifier'
    )
    
    # Group 2: Mail and Communication Properties  
    $mailProperties = @(
        'id', 'mail', 'mailEnabled', 'mailNickname', 'proxyAddresses', 
        'preferredLanguage', 'preferredDataLocation'
    )
    
    # Group 3: Membership and Dynamic Rules Properties (FIXED - removed invalid properties)
    $membershipProperties = @(
        'id', 'membershipRule', 'membershipRuleProcessingState', 'groupTypes'
    )
    
    # Group 4: On-Premises Integration Properties
    $onPremProperties = @(
        'id', 'onPremisesDomainName', 'onPremisesLastSyncDateTime', 'onPremisesNetBiosName',
        'onPremisesSamAccountName', 'onPremisesSecurityIdentifier', 'onPremisesSyncEnabled',
        'onPremisesProvisioningErrors'
    )
    
    # Group 5: Resource and Behavior Properties
    $resourceProperties = @(
        'id', 'resourceBehaviorOptions', 'resourceProvisioningOptions', 'renewedDateTime',
        'theme', 'writebackConfiguration'
    )
    
    # Group 6: License and Assignment Properties (FIXED - removed invalid properties)
    $licenseProperties = @(
        'id', 'assignedLicenses', 'assignedLabels', 'serviceProvisioningErrors'
    )
    
    $propertyGroups = @(
        @{ Name = "Identity"; Properties = $identityProperties }
        @{ Name = "Mail"; Properties = $mailProperties }
        @{ Name = "Membership"; Properties = $membershipProperties }
        @{ Name = "OnPremises"; Properties = $onPremProperties }
        @{ Name = "Resource"; Properties = $resourceProperties }
        @{ Name = "License"; Properties = $licenseProperties }
    )
    
    $consolidatedGroups = @{}
    $batchCount = 0
    
    # Initialize consolidated groups with basic data
    foreach ($groupId in $GroupIds) {
        $consolidatedGroups[$groupId] = $BasicGroupData[$groupId].PSObject.Copy()
    }
    
    # Process each property group with separate API calls
    foreach ($group in $propertyGroups) {
        Write-Information "Processing $($group.Name) properties for $($GroupIds.Count) groups..."
        
        $groupsApiUrl = "https://graph.microsoft.com/v1.0/groups?`$select=$($group.Properties -join ',')&`$top=999"
        
        do {
            $groupProps = $BaseTelemetryProps.Clone()
            $groupProps['Stage'] = "Enhanced-$($group.Name)"
            $groupProps['PropertyGroup'] = $group.Name
            $groupProps['PropertyCount'] = $group.Properties.Count
            
            try {
                $response = Invoke-GraphAPIWithRetry -Uri $groupsApiUrl -Headers $AuthHeader -CorrelationContext $groupProps -MaxRetryCount 3
                
                # Merge properties into consolidated group objects
                foreach ($groupObj in $response.value) {
                    if ($consolidatedGroups.ContainsKey($groupObj.id)) {
                        # Merge new properties into existing group object
                        foreach ($property in $groupObj.PSObject.Properties) {
                            if ($property.Name -ne 'id') {  # Skip ID as it's already present
                                $consolidatedGroups[$groupObj.id] | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
                            }
                        }
                    }
                }
                
                Write-Information "Merged $($group.Name) properties for $($response.value.Count) groups"
            }
            catch {
                Write-Warning "Failed to retrieve $($group.Name) properties: $($_.Exception.Message)"
                # Continue with other property groups
            }
            
            # Get next page URL
            $groupsApiUrl = $response.'@odata.nextLink'
            
        } while ($null -ne $groupsApiUrl)
    }
    
    # Convert hashtable to array for Event Hub transmission
    $consolidatedArray = @()
    foreach ($groupId in $GroupIds) {
        if ($consolidatedGroups.ContainsKey($groupId)) {
            $consolidatedArray += $consolidatedGroups[$groupId]
        }
    }
    
    Write-Information "Property consolidation completed for $($consolidatedArray.Count) groups"
    # FIXED: Added null safety check for property counting
    if ($consolidatedArray.Count -gt 0 -and $null -ne $consolidatedArray[0]) {
        Write-Information "Average properties per group: $([Math]::Round(($consolidatedArray[0] | Get-Member -MemberType Properties).Count, 0))"
    } else {
        Write-Information "No groups available for property count calculation"
    }
    
    return @{
        ConsolidatedGroups = $consolidatedArray
        BatchCount = $batchCount
    }
}

# Helper function for Exchange-stored properties (individual API calls)
function Export-GroupsExchangeProperties {
    [CmdletBinding()]
    param (
        [hashtable]$AuthHeader,
        [array]$GroupIds,
        [array]$ConsolidatedGroups,
        [hashtable]$BaseTelemetryProps,
        [hashtable]$CorrelationContext
    )
    
    $processedExchange = 0
    $batchCount = 0
    $errors = @()
    
    # Exchange-stored properties (require individual API calls and may not be available for all groups)
    $exchangeProperties = @(
        'allowExternalSenders', 'autoSubscribeNewMembers', 'hideFromAddressLists',
        'hideFromOutlookClients', 'isSubscribedByMail', 'unseenCount'
    )
    
    Write-Information "Processing Exchange-stored properties requiring individual API calls..."
    
    $groupIndex = @{}
    for ($i = 0; $i -lt $ConsolidatedGroups.Count; $i++) {
        $groupIndex[$ConsolidatedGroups[$i].id] = $i
    }
    
    $processedBatch = 0
    $batchSize = 50
    
    for ($i = 0; $i -lt $GroupIds.Count; $i += $batchSize) {
        $groupIdBatch = $GroupIds[$i..([Math]::Min($i + $batchSize - 1, $GroupIds.Count - 1))]
        $processedBatch++
        
        Write-Information "Processing Exchange properties batch $processedBatch ($(($processedBatch-1)*$batchSize + 1) to $($processedBatch*$batchSize))"
        
        foreach ($groupId in $groupIdBatch) {
            $groupExtendedUrl = "https://graph.microsoft.com/v1.0/groups/$groupId" + "?`$select=$($exchangeProperties -join ',')"
            
            $extendedGroupProps = $BaseTelemetryProps.Clone()
            $extendedGroupProps['Stage'] = 'ExchangeProperties'
            $extendedGroupProps['GroupId'] = $groupId
            $extendedGroupProps['PropertyCount'] = $exchangeProperties.Count
            
            try {
                $extendedData = Invoke-GraphAPIWithRetry -Uri $groupExtendedUrl -Headers $AuthHeader -CorrelationContext $extendedGroupProps -MaxRetryCount 3
                
                # Merge Exchange properties into consolidated group
                if ($groupIndex.ContainsKey($groupId)) {
                    $groupArrayIndex = $groupIndex[$groupId]
                    foreach ($property in $extendedData.PSObject.Properties) {
                        if ($property.Name -ne 'id' -and $null -ne $property.Value) {
                            $ConsolidatedGroups[$groupArrayIndex] | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
                        }
                    }
                    $processedExchange++
                }
            }
            catch {
                $errorProps = $BaseTelemetryProps.Clone()
                $errorProps['GroupId'] = $groupId
                $errorProps['ErrorMessage'] = $_.Exception.Message
                $errorProps['ErrorType'] = Get-ErrorType -Exception $_
                
                Write-CustomTelemetry -EventName "GroupExchangePropertiesError" -Properties $errorProps
                Write-Warning "Failed to get Exchange properties for group $groupId - $($_.Exception.Message)"
                
                $errors += @{
                    GroupId = $groupId
                    ErrorMessage = $_.Exception.Message
                    ErrorType = Get-ErrorType -Exception $_
                }
            }
        }
        
        # Rate limiting between batches
        if ($processedBatch % 10 -eq 0) {
            Write-Information "Processed $($processedBatch * $batchSize) groups, pausing briefly..."
            Start-Sleep -Milliseconds 2000
        }
    }
    
    Write-Information "Exchange properties processing completed: $processedExchange groups enhanced"
    
    return @{
        ConsolidatedGroups = $ConsolidatedGroups
        ProcessedCount = $processedExchange
        BatchCount = $batchCount
        Errors = $errors
    }
}

# Helper function for final Event Hub transmission
function Export-ConsolidatedGroupsToEventHub {
    [CmdletBinding()]
    param (
        [array]$ConsolidatedGroups,
        [hashtable]$BaseTelemetryProps,
        [hashtable]$CorrelationContext
    )
    
    $batchCount = 0
    $eventHubBatchSize = 100  # Smaller batches due to comprehensive property data
    
    Write-Information "Transmitting $($ConsolidatedGroups.Count) comprehensive group records to Event Hub"
    
    for ($i = 0; $i -lt $ConsolidatedGroups.Count; $i += $eventHubBatchSize) {
        $groupBatch = $ConsolidatedGroups[$i..([Math]::Min($i + $eventHubBatchSize - 1, $ConsolidatedGroups.Count - 1))]
        
        $eventHubRecords = @()
        foreach ($group in $groupBatch) {
            $groupRecord = [PSCustomObject]@{
                OdataContext = "groups"
                ExportId = $CorrelationContext.OperationId
                ExportTimestamp = $CorrelationContext.StartTime.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                Stage = "ComprehensiveProperties"
                PropertyCount = ($group | Get-Member -MemberType Properties).Count
                Data = $group
            }
            $eventHubRecords += $groupRecord
        }
        
        # Send batch to Event Hub
        if ($eventHubRecords.Count -gt 0) {
            $eventHubProps = $BaseTelemetryProps.Clone()
            $eventHubProps['DataType'] = 'Groups-Comprehensive'
            $eventHubProps['RecordCount'] = $eventHubRecords.Count
            $eventHubProps['BatchNumber'] = ++$batchCount
            $eventHubProps['AvgPropertiesPerGroup'] = [Math]::Round(($eventHubRecords | ForEach-Object { $_.PropertyCount } | Measure-Object -Average).Average, 0)
            
            $eventHubScriptBlock = {
                Send-EventsToEventHub -payload (ConvertTo-Json -InputObject $eventHubRecords -Depth 50)
            }
            
            Invoke-WithRetry -ScriptBlock $eventHubScriptBlock -MaxRetryCount 3 -OperationName "SendComprehensiveGroupsToEventHub" -TelemetryProperties $eventHubProps
            
            Write-Information "Transmitted batch $batchCount with $($eventHubRecords.Count) comprehensive group records"
        }
    }
    
    return @{
        BatchCount = $batchCount
    }
}
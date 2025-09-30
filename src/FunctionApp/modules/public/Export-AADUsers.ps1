<#
.SYNOPSIS
    Enhanced Azure AD Users export with comprehensive property retrieval using multiple API calls.

.DESCRIPTION
    This module exports Azure AD users to Event Hub for ADX ingestion with complete property coverage.
    Uses multiple API calls to overcome Graph API property selection limits and retrieves all available
    user properties from Microsoft Graph v1.0 endpoint.

.PARAMETER AuthHeader
    Authentication headers for Microsoft Graph API calls.

.PARAMETER CorrelationContext
    Correlation context containing operation ID and tracking information.

.PARAMETER IncludeExtendedProperties
    Switch to include extended user properties that require individual API calls.

.NOTES
    Author: Laurie Rhodes
    Version: 4.1
    Last Modified: 2025-09-02
    
    Key Features:
    - Complete user property coverage using multiple API calls
    - Intelligent batching to overcome Graph API $select limitations
    - Consolidated user objects for Event Hub transmission
    - Enhanced error handling and performance monitoring
    - Production-ready v1.0 Graph API endpoints exclusively

.CHANGES
    Version 4.1 Changes:
    - Fixed property count calculation error (removed incorrect .Data reference)
    - Added null safety checks for property counting
    - Improved error handling for edge cases
#>

function Export-AADUsers {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$AuthHeader,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$CorrelationContext,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeExtendedProperties = $false
    )
    
    # Initialize tracking variables
    $userStageStart = Get-Date
    $userCount = 0
    $batchCount = 0
    $processedExtended = 0
    $errors = @()
    
    # Base telemetry properties
    $baseTelemetryProps = $CorrelationContext.Clone()
    $baseTelemetryProps['ApiEndpoint'] = 'Users'
    $baseTelemetryProps['ApiVersion'] = 'v1.0'
    $baseTelemetryProps['ComprehensiveProperties'] = $true
    
    Write-Information "Starting Users Export - Comprehensive Properties Mode (v4.1)"
    Write-Information "Enhanced mode: Multiple API calls for complete property coverage"
    
    try {
        # Stage 1: Basic User List with Core Properties
        $basicResult = Export-UsersBasicProperties -AuthHeader $AuthHeader -BaseTelemetryProps $baseTelemetryProps -CorrelationContext $CorrelationContext
        $userCount = $basicResult.UserCount
        $userIds = $basicResult.UserIds
        $basicUserData = $basicResult.UserData
        
        Write-Information "Stage 1 Complete - Basic properties for $userCount users"
        
        # Stage 2: Enhanced Properties Retrieval (Multiple API Calls)
        $enhancedResult = Export-UsersEnhancedProperties -AuthHeader $AuthHeader -UserIds $userIds -BasicUserData $basicUserData -BaseTelemetryProps $baseTelemetryProps -CorrelationContext $CorrelationContext
        $consolidatedUsers = $enhancedResult.ConsolidatedUsers
        $batchCount += $enhancedResult.BatchCount
        
        Write-Information "Stage 2 Complete - Enhanced properties consolidated for $($consolidatedUsers.Count) users"
        
        # Stage 3: Extended Properties Export (if enabled)
        if ($IncludeExtendedProperties -and $userIds.Count -gt 0) {
            Write-Information "Stage 3: Processing SharePoint-stored properties for $($userIds.Count) users..."
            $extendedResult = Export-UsersSharePointProperties -AuthHeader $AuthHeader -UserIds $userIds -ConsolidatedUsers $consolidatedUsers -BaseTelemetryProps $baseTelemetryProps -CorrelationContext $CorrelationContext
            $consolidatedUsers = $extendedResult.ConsolidatedUsers
            $processedExtended = $extendedResult.ProcessedCount
            $batchCount += $extendedResult.BatchCount
            $errors = $extendedResult.Errors
            
            Write-Information "Stage 3 Complete - Extended properties for $processedExtended users"
        }
        
        # Stage 4: Final Event Hub Transmission
        $transmissionResult = Export-ConsolidatedUsersToEventHub -ConsolidatedUsers $consolidatedUsers -BaseTelemetryProps $baseTelemetryProps -CorrelationContext $CorrelationContext
        $batchCount += $transmissionResult.BatchCount
        
        Write-Information "Stage 4 Complete - Transmitted $($consolidatedUsers.Count) complete user records"
        
        # Calculate final metrics
        $totalUsersDuration = ((Get-Date) - $userStageStart).TotalMilliseconds
        
        # Log completion telemetry - Fixed property count calculation
        $completionProps = $baseTelemetryProps.Clone()
        $completionProps['TotalUsers'] = $userCount
        $completionProps['ConsolidatedUsers'] = $consolidatedUsers.Count
        $completionProps['ExtendedPropertiesProcessed'] = $processedExtended
        $completionProps['TotalBatches'] = $batchCount
        $completionProps['DurationMs'] = $totalUsersDuration
        $completionProps['ErrorCount'] = $errors.Count
        # FIXED: Removed incorrect .Data reference - consolidated users contain user objects directly
        $completionProps['PropertiesPerUser'] = if ($consolidatedUsers.Count -gt 0 -and $null -ne $consolidatedUsers[0]) { 
            ($consolidatedUsers[0] | Get-Member -MemberType Properties).Count 
        } else { 
            0 
        }
        
        $metrics = @{
            'UsersPerMinute' = if ($totalUsersDuration -gt 0) { [Math]::Round($userCount / ($totalUsersDuration / 60000), 0) } else { 0 }
            'BatchesCreated' = $batchCount
            'PropertiesCoverage' = $completionProps['PropertiesPerUser']
        }
        
        Write-CustomTelemetry -EventName "UsersExportComprehensiveCompleted" -Properties $completionProps -Metrics $metrics
        
        Write-Information "=== Users Export Completed Successfully (v4.1) ==="
        Write-Information "  - Total Users: $userCount"
        Write-Information "  - Consolidated Records: $($consolidatedUsers.Count)"
        Write-Information "  - Properties Per User: $($completionProps['PropertiesPerUser'])"
        Write-Information "  - Extended Properties: $processedExtended users"
        Write-Information "  - Total Batches: $batchCount"
        Write-Information "  - Duration: $([Math]::Round($totalUsersDuration/1000, 2)) seconds"
        Write-Information "  - Errors: $($errors.Count)"
        
        return @{
            Success = $true
            UserCount = $userCount
            ConsolidatedUsers = $consolidatedUsers.Count
            ExtendedPropertiesCount = $processedExtended
            BatchCount = $batchCount
            DurationMs = $totalUsersDuration
            PropertiesPerUser = $completionProps['PropertiesPerUser']
            Errors = $errors
        }
        
    }
    catch {
        # Single-level error handling - no nested catch blocks
        $errorMessage = $_.Exception.Message
        $errorType = Get-ErrorType -Exception $_
        
        $errorDetails = @{
            ExportId = $CorrelationContext.OperationId
            Stage = 'UsersExportComprehensive'
            ErrorMessage = $errorMessage
            ErrorType = $errorType
            ProcessedUsers = $userCount
            FailureTimestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        }
        
        Write-CustomTelemetry -EventName "UsersExportComprehensiveFailed" -Properties $errorDetails
        Write-Error "Comprehensive Users Export failed after processing $userCount users - $errorMessage"
        
        return @{
            Success = $false
            UserCount = $userCount
            ConsolidatedUsers = 0
            ExtendedPropertiesCount = $processedExtended
            BatchCount = $batchCount
            Error = $errorDetails
        }
    }
}

# Helper function for basic user properties (first API call)
function Export-UsersBasicProperties {
    [CmdletBinding()]
    param (
        [hashtable]$AuthHeader,
        [hashtable]$BaseTelemetryProps,
        [hashtable]$CorrelationContext
    )
    
    $userCount = 0
    $userIds = @()
    $userData = @{}
    
    # Basic properties that are returned by default (always available)
    $basicProperties = @(
        'id', 'accountEnabled', 'displayName', 'givenName', 'surname', 
        'userPrincipalName', 'mail', 'jobTitle', 'department', 'companyName',
        'businessPhones', 'mobilePhone', 'officeLocation', 'preferredLanguage'
    )
    
    $usersApiUrl = "https://graph.microsoft.com/v1.0/users?`$select=$($basicProperties -join ',')&`$top=999"
    
    do {
        # Graph API call with retry logic
        $userProps = $BaseTelemetryProps.Clone()
        $userProps['Stage'] = 'BasicProperties'
        $userProps['PageUrl'] = $usersApiUrl
        
        $response = Invoke-GraphAPIWithRetry -Uri $usersApiUrl -Headers $AuthHeader -CorrelationContext $userProps -MaxRetryCount 5
        
        Write-Information "Retrieved $($response.value.Count) users with basic properties"

        # Store basic user data
        foreach ($user in $response.value) {
            $userData[$user.id] = $user
            $userIds += $user.id
            $userCount++
        }

        # Get next page URL
        $usersApiUrl = $response.'@odata.nextLink'

    } while ($null -ne $usersApiUrl)
    
    return @{
        UserCount = $userCount
        UserIds = $userIds
        UserData = $userData
    }
}

# Helper function for enhanced properties (multiple targeted API calls)
function Export-UsersEnhancedProperties {
    [CmdletBinding()]
    param (
        [hashtable]$AuthHeader,
        [array]$UserIds,
        [hashtable]$BasicUserData,
        [hashtable]$BaseTelemetryProps,
        [hashtable]$CorrelationContext
    )
    
    Write-Information "Starting enhanced properties retrieval for $($UserIds.Count) users using multiple API calls"
    
    # Define property groups to overcome $select limitations
    # Group 1: Core Identity and Security Properties
    $identityProperties = @(
        'id', 'deletedDateTime', 'createdDateTime', 'lastPasswordChangeDateTime',
        'signInSessionsValidFromDateTime', 'userType', 'creationType', 'externalUserState',
        'externalUserStateChangeDateTime', 'isResourceAccount', 'isManagementRestricted',
        'securityIdentifier', 'identities', 'imAddresses'
    )
    
    # Group 2: Contact and Location Properties  
    $contactProperties = @(
        'id', 'businessPhones', 'mobilePhone', 'faxNumber', 'mail', 'mailNickname',
        'otherMails', 'proxyAddresses', 'streetAddress', 'city', 'state', 
        'postalCode', 'country', 'usageLocation', 'preferredDataLocation'
    )
    
    # Group 3: Organization and Employment Properties
    $orgProperties = @(
        'id', 'employeeId', 'employeeType', 'employeeHireDate', 'employeeLeaveDateTime',
        'employeeOrgData', 'costCenter', 'division', 'showInAddressList'
    )
    
    # Group 4: License and Provisioning Properties
    $licenseProperties = @(
        'id', 'assignedLicenses', 'assignedPlans', 'provisionedPlans', 
        'licenseAssignmentStates', 'serviceProvisioningErrors'
    )
    
    # Group 5: On-Premises Integration Properties
    $onPremProperties = @(
        'id', 'onPremisesDistinguishedName', 'onPremisesDomainName', 'onPremisesImmutableId',
        'onPremisesLastSyncDateTime', 'onPremisesSamAccountName', 'onPremisesSecurityIdentifier',
        'onPremisesSyncEnabled', 'onPremisesUserPrincipalName', 'onPremisesExtensionAttributes',
        'onPremisesProvisioningErrors'
    )
    
    # Group 6: Authentication and Age Properties  
    $authProperties = @(
        'id', 'ageGroup', 'consentProvidedForMinor', 'legalAgeGroupClassification',
        'passwordPolicies', 'passwordProfile', 'signInActivity'
    )
    
    # Group 7: Custom Security Attributes (if available)
    $customProperties = @(
        'id', 'customSecurityAttributes'
    )
    
    $propertyGroups = @(
        @{ Name = "Identity"; Properties = $identityProperties }
        @{ Name = "Contact"; Properties = $contactProperties }
        @{ Name = "Organization"; Properties = $orgProperties }
        @{ Name = "License"; Properties = $licenseProperties }
        @{ Name = "OnPremises"; Properties = $onPremProperties }
        @{ Name = "Authentication"; Properties = $authProperties }
        @{ Name = "Custom"; Properties = $customProperties }
    )
    
    $consolidatedUsers = @{}
    $batchCount = 0
    
    # Initialize consolidated users with basic data
    foreach ($userId in $UserIds) {
        $consolidatedUsers[$userId] = $BasicUserData[$userId].PSObject.Copy()
    }
    
    # Process each property group with separate API calls
    foreach ($group in $propertyGroups) {
        Write-Information "Processing $($group.Name) properties for $($UserIds.Count) users..."
        
        $usersApiUrl = "https://graph.microsoft.com/v1.0/users?`$select=$($group.Properties -join ',')&`$top=999"
        
        do {
            $userProps = $BaseTelemetryProps.Clone()
            $userProps['Stage'] = "Enhanced-$($group.Name)"
            $userProps['PropertyGroup'] = $group.Name
            $userProps['PropertyCount'] = $group.Properties.Count
            
            try {
                $response = Invoke-GraphAPIWithRetry -Uri $usersApiUrl -Headers $AuthHeader -CorrelationContext $userProps -MaxRetryCount 3
                
                # Merge properties into consolidated user objects
                foreach ($user in $response.value) {
                    if ($consolidatedUsers.ContainsKey($user.id)) {
                        # Merge new properties into existing user object
                        foreach ($property in $user.PSObject.Properties) {
                            if ($property.Name -ne 'id') {  # Skip ID as it's already present
                                $consolidatedUsers[$user.id] | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
                            }
                        }
                    }
                }
                
                Write-Information "Merged $($group.Name) properties for $($response.value.Count) users"
            }
            catch {
                Write-Warning "Failed to retrieve $($group.Name) properties: $($_.Exception.Message)"
                # Continue with other property groups
            }
            
            # Get next page URL
            $usersApiUrl = $response.'@odata.nextLink'
            
        } while ($null -ne $usersApiUrl)
    }
    
    # Convert hashtable to array for Event Hub transmission
    $consolidatedArray = @()
    foreach ($userId in $UserIds) {
        if ($consolidatedUsers.ContainsKey($userId)) {
            $consolidatedArray += $consolidatedUsers[$userId]
        }
    }
    
    Write-Information "Property consolidation completed for $($consolidatedArray.Count) users"
    # FIXED: Added null safety check for property counting
    if ($consolidatedArray.Count -gt 0 -and $null -ne $consolidatedArray[0]) {
        Write-Information "Average properties per user: $([Math]::Round(($consolidatedArray[0] | Get-Member -MemberType Properties).Count, 0))"
    } else {
        Write-Information "No users available for property count calculation"
    }
    
    return @{
        ConsolidatedUsers = $consolidatedArray
        BatchCount = $batchCount
    }
}

# Helper function for SharePoint-stored properties (individual API calls)
function Export-UsersSharePointProperties {
    [CmdletBinding()]
    param (
        [hashtable]$AuthHeader,
        [array]$UserIds,
        [array]$ConsolidatedUsers,
        [hashtable]$BaseTelemetryProps,
        [hashtable]$CorrelationContext
    )
    
    $processedExtended = 0
    $batchCount = 0
    $errors = @()
    
    # SharePoint-stored properties (require individual API calls)
    $sharePointProperties = @(
        'aboutMe', 'birthday', 'hireDate', 'interests', 'mySite', 
        'pastProjects', 'preferredName', 'responsibilities', 'schools', 'skills'
    )
    
    Write-Information "Processing SharePoint-stored properties requiring individual API calls..."
    
    $userIndex = @{}
    for ($i = 0; $i -lt $ConsolidatedUsers.Count; $i++) {
        $userIndex[$ConsolidatedUsers[$i].id] = $i
    }
    
    $processedBatch = 0
    $batchSize = 50
    
    for ($i = 0; $i -lt $UserIds.Count; $i += $batchSize) {
        $userIdBatch = $UserIds[$i..([Math]::Min($i + $batchSize - 1, $UserIds.Count - 1))]
        $processedBatch++
        
        Write-Information "Processing SharePoint properties batch $processedBatch ($(($processedBatch-1)*$batchSize + 1) to $($processedBatch*$batchSize))"
        
        foreach ($userId in $userIdBatch) {
            $userExtendedUrl = "https://graph.microsoft.com/v1.0/users/$userId" + "?`$select=$($sharePointProperties -join ',')"
            
            $extendedUserProps = $BaseTelemetryProps.Clone()
            $extendedUserProps['Stage'] = 'SharePointProperties'
            $extendedUserProps['UserId'] = $userId
            $extendedUserProps['PropertyCount'] = $sharePointProperties.Count
            
            try {
                $extendedData = Invoke-GraphAPIWithRetry -Uri $userExtendedUrl -Headers $AuthHeader -CorrelationContext $extendedUserProps -MaxRetryCount 3
                
                # Merge SharePoint properties into consolidated user
                if ($userIndex.ContainsKey($userId)) {
                    $userArrayIndex = $userIndex[$userId]
                    foreach ($property in $extendedData.PSObject.Properties) {
                        if ($property.Name -ne 'id' -and $null -ne $property.Value) {
                            $ConsolidatedUsers[$userArrayIndex] | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
                        }
                    }
                    $processedExtended++
                }
            }
            catch {
                $errorProps = $BaseTelemetryProps.Clone()
                $errorProps['UserId'] = $userId
                $errorProps['ErrorMessage'] = $_.Exception.Message
                $errorProps['ErrorType'] = Get-ErrorType -Exception $_
                
                Write-CustomTelemetry -EventName "UserSharePointPropertiesError" -Properties $errorProps
                Write-Warning "Failed to get SharePoint properties for user $userId - $($_.Exception.Message)"
                
                $errors += @{
                    UserId = $userId
                    ErrorMessage = $_.Exception.Message
                    ErrorType = Get-ErrorType -Exception $_
                }
            }
        }
        
        # Rate limiting between batches
        if ($processedBatch % 10 -eq 0) {
            Write-Information "Processed $($processedBatch * $batchSize) users, pausing briefly..."
            Start-Sleep -Milliseconds 2000
        }
    }
    
    Write-Information "SharePoint properties processing completed: $processedExtended users enhanced"
    
    return @{
        ConsolidatedUsers = $ConsolidatedUsers
        ProcessedCount = $processedExtended
        BatchCount = $batchCount
        Errors = $errors
    }
}

# Helper function for final Event Hub transmission
function Export-ConsolidatedUsersToEventHub {
    [CmdletBinding()]
    param (
        [array]$ConsolidatedUsers,
        [hashtable]$BaseTelemetryProps,
        [hashtable]$CorrelationContext
    )
    
    $batchCount = 0
    $eventHubBatchSize = 100  # Smaller batches due to comprehensive property data
    
    Write-Information "Transmitting $($ConsolidatedUsers.Count) comprehensive user records to Event Hub"
    
    for ($i = 0; $i -lt $ConsolidatedUsers.Count; $i += $eventHubBatchSize) {
        $userBatch = $ConsolidatedUsers[$i..([Math]::Min($i + $eventHubBatchSize - 1, $ConsolidatedUsers.Count - 1))]
        
        $eventHubRecords = @()
        foreach ($user in $userBatch) {
            $userRecord = [PSCustomObject]@{
                OdataContext = "users"
                ExportId = $CorrelationContext.OperationId
                ExportTimestamp = $CorrelationContext.StartTime.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                Stage = "ComprehensiveProperties"
                PropertyCount = ($user | Get-Member -MemberType Properties).Count
                Data = $user
            }
            $eventHubRecords += $userRecord
        }
        
        # Send batch to Event Hub
        if ($eventHubRecords.Count -gt 0) {
            $eventHubProps = $BaseTelemetryProps.Clone()
            $eventHubProps['DataType'] = 'Users-Comprehensive'
            $eventHubProps['RecordCount'] = $eventHubRecords.Count
            $eventHubProps['BatchNumber'] = ++$batchCount
            $eventHubProps['AvgPropertiesPerUser'] = [Math]::Round(($eventHubRecords | ForEach-Object { $_.PropertyCount } | Measure-Object -Average).Average, 0)
            
            $eventHubScriptBlock = {
                Send-EventsToEventHub -payload (ConvertTo-Json -InputObject $eventHubRecords -Depth 50)
            }
            
            Invoke-WithRetry -ScriptBlock $eventHubScriptBlock -MaxRetryCount 3 -OperationName "SendComprehensiveUsersToEventHub" -TelemetryProperties $eventHubProps
            
            Write-Information "Transmitted batch $batchCount with $($eventHubRecords.Count) comprehensive user records"
        }
    }
    
    return @{
        BatchCount = $batchCount
    }
}
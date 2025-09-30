<#
.SYNOPSIS
    Handles Azure AD Group Memberships export with optimized batch processing.

.DESCRIPTION
    This module exports Azure AD group memberships to Event Hub for ADX ingestion.
    It processes group memberships efficiently using v1.0 production endpoint,
    implements intelligent batching for 1MB Event Hub limits, and provides
    resilient error handling for individual group failures.

.NOTES
    Author: Laurie Rhodes
    Version: 2.0
    Created: 2025-08-31
    
    Key Features:
    - Uses v1.0 production endpoint for stability
    - Processes large group lists efficiently with batching
    - Continues processing despite individual group failures
    - Respects Event Hub 1MB payload limits
    - Comprehensive error handling and progress tracking
#>

function Export-AADGroupMemberships {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$AuthHeader,
        
        [Parameter(Mandatory = $true)]
        [array]$GroupIDs,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$CorrelationContext
    )
    
    Write-Information "Starting Group Memberships Export for $($GroupIDs.Count) groups..."
    $membershipStageStart = Get-Date
    $membershipCount = 0
    $processedGroups = 0
    $failedGroups = @()
    $batchCount = 0
    
    # Base telemetry properties
    $baseTelemetryProps = $CorrelationContext.Clone()
    $baseTelemetryProps['ApiEndpoint'] = 'GroupMembers'
    $baseTelemetryProps['ApiVersion'] = 'v1.0'
    $baseTelemetryProps['TotalGroupsToProcess'] = $GroupIDs.Count
    
    try {
        # Initialize batch processing
        $membershipBatch = @()
        $batchSizeLimit = 2000  # Optimal batch size for 1MB Event Hub limit
        
        # Process each group for memberships
        foreach ($GroupID in $GroupIDs) {
            $memberProps = $baseTelemetryProps.Clone()
            $memberProps['GroupID'] = $GroupID
            $memberProps['ProcessedGroups'] = $processedGroups
            
            # Use v1.0 production endpoint for group members with enhanced member details
            $membersApiUrl = "https://graph.microsoft.com/v1.0/groups/$GroupID/members?`$select=id,displayName,userPrincipalName,userType&`$top=999"
            
            try {
                # Handle pagination for groups with many members
                do {
                    $membersResponse = Invoke-GraphAPIWithRetry -Uri $membersApiUrl -Headers $AuthHeader -CorrelationContext $memberProps -MaxRetryCount 3
                    
                    # Process each member in the current page
                    foreach ($member in $membersResponse.value) {
                        $memberRecord = [PSCustomObject]@{
                            OdataContext = "GroupMembers"
                            ExportId = $CorrelationContext.OperationId
                            ExportTimestamp = $CorrelationContext.StartTime.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                            GroupID = $GroupID
                            Data = @{
                                MemberId = $member.id
                                MemberDisplayName = $member.displayName
                                MemberUserPrincipalName = $member.userPrincipalName
                                MemberType = $member.userType
                            }
                        }
                        $membershipBatch += $memberRecord
                        $membershipCount++
                    }
                    
                    # Get next page for this group if available
                    $membersApiUrl = $membersResponse.'@odata.nextLink'
                    
                } while ($null -ne $membersApiUrl)

                # Send batch when it reaches optimal size (respecting 1MB Event Hub limit)
                if ($membershipBatch.Count -ge $batchSizeLimit) {
                    $eventHubProps = $baseTelemetryProps.Clone()
                    $eventHubProps['DataType'] = 'GroupMembers'
                    $eventHubProps['RecordCount'] = $membershipBatch.Count
                    $eventHubProps['BatchNumber'] = ++$batchCount
                    
                    $eventHubScriptBlock = {
                        Send-EventsToEventHub -payload (ConvertTo-Json -InputObject $membershipBatch -Depth 50)
                    }
                    
                    Invoke-WithRetry -ScriptBlock $eventHubScriptBlock -MaxRetryCount 3 -OperationName "SendMembershipsToEventHub" -TelemetryProperties $eventHubProps
                    
                    Write-Information "Sent batch of $($membershipBatch.Count) membership records to Event Hub"
                    $membershipBatch = @()  # Reset batch
                }

                $processedGroups++
                
                # Progress reporting every 100 groups
                if ($processedGroups % 100 -eq 0) {
                    Write-ExportProgress -Stage "GroupMemberships" -ProcessedCount $processedGroups -TotalCount $GroupIDs.Count -CorrelationContext $baseTelemetryProps
                    
                    # Log intermediate statistics
                    Write-Information "Progress: $processedGroups/$($GroupIDs.Count) groups processed, $membershipCount total memberships collected"
                }
                
                # Rate limiting with jitter to avoid API throttling
                $jitter = Get-Random -Minimum 1000 -Maximum 2000
                Start-Sleep -Milliseconds $jitter
                
            } catch {
                # Log group-specific error but continue processing other groups
                $groupErrorProps = $baseTelemetryProps.Clone()
                $groupErrorProps['GroupID'] = $GroupID
                $groupErrorProps['ErrorMessage'] = $_.Exception.Message
                $groupErrorProps['ErrorType'] = Get-ErrorType -Exception $_.Exception
                $groupErrorProps['HttpStatusCode'] = Get-HttpStatusCode -Exception $_.Exception
                $groupErrorProps['ProcessedGroups'] = $processedGroups
                
                Write-CustomTelemetry -EventName "GroupMembershipError" -Properties $groupErrorProps
                Write-Warning "Failed to get members for group $GroupID`: $($_.Exception.Message)"
                
                $failedGroups += $GroupID
                $processedGroups++  # Still count as processed even if failed
                continue  # Continue with next group
            }
        }

        # Send any remaining membership records in final batch
        if ($membershipBatch.Count -gt 0) {
            $eventHubProps = $baseTelemetryProps.Clone()
            $eventHubProps['DataType'] = 'GroupMembers'
            $eventHubProps['RecordCount'] = $membershipBatch.Count
            $eventHubProps['BatchType'] = 'Final'
            $eventHubProps['BatchNumber'] = ++$batchCount
            
            $eventHubScriptBlock = {
                Send-EventsToEventHub -payload (ConvertTo-Json -InputObject $membershipBatch -Depth 50)
            }
            
            Invoke-WithRetry -ScriptBlock $eventHubScriptBlock -MaxRetryCount 3 -OperationName "SendFinalMembershipsToEventHub" -TelemetryProperties $eventHubProps
            
            Write-Information "Sent final batch of $($membershipBatch.Count) membership records to Event Hub"
        }

        $totalMembershipsDuration = ((Get-Date) - $membershipStageStart).TotalMilliseconds
        
        # Calculate success metrics
        $successfulGroups = $processedGroups - $failedGroups.Count
        $groupSuccessRate = if ($GroupIDs.Count -gt 0) { 
            [Math]::Round(($successfulGroups / $GroupIDs.Count) * 100, 2) 
        } else { 100 }
        
        # Final telemetry for memberships export
        $membershipCompletionProps = $baseTelemetryProps.Clone()
        $membershipCompletionProps['TotalMemberships'] = $membershipCount
        $membershipCompletionProps['ProcessedGroups'] = $processedGroups
        $membershipCompletionProps['SuccessfulGroups'] = $successfulGroups
        $membershipCompletionProps['FailedGroups'] = $failedGroups.Count
        $membershipCompletionProps['GroupSuccessRate'] = $groupSuccessRate
        $membershipCompletionProps['TotalBatches'] = $batchCount
        $membershipCompletionProps['DurationMs'] = $totalMembershipsDuration
        
        $membershipMetrics = @{
            'MembershipsPerMinute' = [Math]::Round($membershipCount / ($totalMembershipsDuration / 60000), 0)
            'GroupsPerMinute' = [Math]::Round($processedGroups / ($totalMembershipsDuration / 60000), 0)
            'BatchesCreated' = $batchCount
        }
        
        Write-CustomTelemetry -EventName "GroupMembershipsExportCompleted" -Properties $membershipCompletionProps -Metrics $membershipMetrics
        
        Write-Information "=== Group Memberships Export Completed ==="
        Write-Information "  - Total Memberships: $membershipCount"
        Write-Information "  - Processed Groups: $processedGroups of $($GroupIDs.Count)"
        Write-Information "  - Successful Groups: $successfulGroups ($groupSuccessRate%)"
        Write-Information "  - Failed Groups: $($failedGroups.Count)"
        Write-Information "  - Total Batches: $batchCount"
        Write-Information "  - Duration: $([Math]::Round($totalMembershipsDuration/1000, 2)) seconds"
        
        return @{
            Success = $true
            MembershipCount = $membershipCount
            ProcessedGroups = $processedGroups
            SuccessfulGroups = $successfulGroups
            FailedGroups = $failedGroups.Count
            GroupSuccessRate = $groupSuccessRate
            BatchCount = $batchCount
            DurationMs = $totalMembershipsDuration
        }
        
    } catch {
        # Enhanced error handling for membership export
        $errorDetails = @{
            ExportId = $CorrelationContext.OperationId
            Stage = 'GroupMembershipsExport'
            ErrorMessage = $_.Exception.Message
            ErrorType = Get-ErrorType -Exception $_.Exception
            ProcessedGroups = $processedGroups
            ProcessedMemberships = $membershipCount
            FailedGroups = $failedGroups.Count
            FailureTimestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        }
        
        Write-CustomTelemetry -EventName "GroupMembershipsExportFailed" -Properties $errorDetails
        Write-Error "Group Memberships Export failed after processing $processedGroups groups and $membershipCount memberships: $($_.Exception.Message)"
        
        throw $_
    }
}
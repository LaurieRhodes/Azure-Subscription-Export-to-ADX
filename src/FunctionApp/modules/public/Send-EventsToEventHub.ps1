<#
  PURPOSE:  Submit JSON to Event Hubs with enhanced error handling and resource identification
  REQUIRES:

  Function App Environment Variables set for:
	EVENTHUBNAMESPACE
	EVENTHUBNAME  (Note: was EVENTHUB in previous version)
	CLIENTID

  And the user-assigned managed identity needs:
  - Azure Event Hubs Data Sender role on the Event Hub
#>

function Send-EventsToEventHub {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Payload
    )

    # Validate required environment variables - CORRECTED VARIABLE NAMES
    $requiredVars = @{
        'EVENTHUBNAMESPACE' = $env:EVENTHUBNAMESPACE
        'EVENTHUBNAME' = $env:EVENTHUBNAME  # Changed from EVENTHUB to EVENTHUBNAME
        'CLIENTID' = $env:CLIENTID
    }
    
    $missingVars = @()
    $presentVars = @()
    
    foreach ($var in $requiredVars.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace($var.Value)) {
            $missingVars += $var.Key
        } else {
            $presentVars += "$($var.Key)=$($var.Value.Substring(0, [Math]::Min(8, $var.Value.Length)))..."
        }
    }
    
    Write-Information "Event Hub Environment Variables Check:"
    Write-Information "Present: $($presentVars -join ', ')"
    if ($missingVars.Count -gt 0) {
        Write-Information "Missing: $($missingVars -join ', ')"
    }
    
    if ($missingVars.Count -gt 0) {
        $errorMessage = "Missing required environment variables for Event Hub: $($missingVars -join ', '). Cannot proceed with Event Hub data transmission."
        Write-Error $errorMessage
        throw [System.Configuration.ConfigurationErrorsException]::new($errorMessage)
    }

    # Enhanced payload size limits for Basic SKU Event Hub (256KB limit) - aligned with batch processing
    $maxPayloadSize = 230KB            # Aligned with batch processing limit
    $maxSingleResourceSize = 100KB     # Individual resource size limit
    $warningThreshold = 200KB          # Warn when approaching limit

    Write-Information "Using Basic SKU Event Hub limits: Max payload $([Math]::Round($maxPayloadSize/1KB, 0))KB, Max resource $([Math]::Round($maxSingleResourceSize/1KB, 0))KB"

    # Parse the JSON payload into an object
    try {
        $PayloadObject = ConvertFrom-Json -InputObject $Payload
        Write-Information "Parsed payload: $($PayloadObject.Count) records"
    }
    catch {
        $errorMessage = "Invalid JSON payload: $($_.Exception.Message)"
        Write-Error $errorMessage
        throw [System.ArgumentException]::new($errorMessage)
    }

    # Pre-validate individual resources for size issues (changed to warning-only)
    $oversizedResources = @()
    foreach ($record in $PayloadObject) {
        $recordJson = ConvertTo-Json -InputObject $record -Depth 50
        $recordSize = [System.Text.Encoding]::UTF8.GetByteCount($recordJson)
        
        if ($recordSize -gt $maxSingleResourceSize) {
            $resourceId = if ($record.Data -and $record.Data.id) { $record.Data.id } 
                         elseif ($record.id) { $record.id }
                         else { "Unknown Resource" }
            
            $oversizedResources += @{
                ResourceId = $resourceId
                ResourceType = if ($record.ResourceType) { $record.ResourceType } else { "Unknown" }
                SizeKB = [Math]::Round($recordSize/1024, 2)
            }
            
            Write-Warning "LARGE RESOURCE DETECTED: $resourceId ($([Math]::Round($recordSize/1024, 2)) KB)"
        }
    }

    # Log oversized resources but don't fail - continue processing
    if ($oversizedResources.Count -gt 0) {
        Write-Warning "Found $($oversizedResources.Count) large resources (Basic SKU will chunk appropriately):"
        foreach ($resource in $oversizedResources) {
            Write-Warning "  - $($resource.ResourceType): $($resource.ResourceId) ($($resource.SizeKB) KB)"
        }
        Write-Information "Note: Large resources will be automatically chunked by Event Hub sender"
    }

    # Initialize variables for chunking (should rarely be needed with proper batching)
    $chunk = @()
    $messages = @()
    $currentSize = 0
    $chunkResourceIds = @()  # Track resource IDs in current chunk

    foreach ($record in $PayloadObject) {
        $recordJson = ConvertTo-Json -InputObject $record -Depth 50
        $recordSize = [System.Text.Encoding]::UTF8.GetByteCount($recordJson)
        
        # Get resource identifier for tracking
        $resourceId = if ($record.Data -and $record.Data.id) { $record.Data.id } 
                     elseif ($record.id) { $record.id }
                     else { "Resource-$($chunk.Count + 1)" }

        # Check if adding this record would exceed the Basic SKU limit
        if (($currentSize + $recordSize) -ge $maxPayloadSize) {
            # Store current chunk with metadata
            $chunkInfo = @{
                Records = $chunk
                ResourceIds = $chunkResourceIds
                SizeKB = [Math]::Round($currentSize/1024, 2)
            }
            $messages += $chunkInfo
            
            # Reset for new chunk
            $chunk = @()
            $chunkResourceIds = @()
            $currentSize = 0
        }
        
        $chunk += $record
        $chunkResourceIds += $resourceId
        $currentSize += $recordSize

        # Warn if chunk is getting large for Basic SKU
        if ($currentSize -gt $warningThreshold) {
            Write-Warning "Chunk approaching Basic SKU size limit: $([Math]::Round($currentSize/1024, 2)) KB (Contains $($chunk.Count) resources)"
        }
    }

    # Add remaining chunk if it contains data
    if ($chunk.Count -gt 0) {
        $chunkInfo = @{
            Records = $chunk
            ResourceIds = $chunkResourceIds
            SizeKB = [Math]::Round($currentSize/1024, 2)
        }
        $messages += $chunkInfo
    }

    # CORRECTED: Use EVENTHUBNAME instead of EVENTHUB
    $EventHubUri = "https://$($env:EVENTHUBNAMESPACE).servicebus.windows.net/$($env:EVENTHUBNAME)/messages"
    Write-Information "Sending $($messages.Count) message chunks to Event Hub: $EventHubUri"

    $successfulChunks = 0
    $totalChunks = $messages.Count
    $failedChunks = @()

    foreach ($chunkInfo in $messages) {
        $currentChunkNumber = $successfulChunks + 1
        
        try {
            # Get Event Hub Token with enhanced error handling
            Write-Debug "Acquiring Event Hub token for resource: https://eventhubs.azure.net"
            
            $EHtoken = Get-AzureADToken -resource "https://eventhubs.azure.net" -clientId $env:CLIENTID
            
            if ([string]::IsNullOrWhiteSpace($EHtoken)) {
                throw [System.Security.Authentication.AuthenticationException]::new("Event Hub token acquisition returned empty token")
            }
            
            Write-Debug "Event Hub token acquired successfully"

            $jsonPayload = ConvertTo-Json -InputObject $chunkInfo.Records -Depth 50
            $payloadSizeKB = [Math]::Round([System.Text.Encoding]::UTF8.GetByteCount($jsonPayload)/1024, 2)

            # Final size check before sending - should rarely trigger with proper batching
            if ($payloadSizeKB -gt 230) {
                Write-Warning "Chunk size $payloadSizeKB KB exceeds Basic SKU safe limit (230KB) - batch sizing may need adjustment"
            }

            $headers = @{
                'content-type'  = 'application/json'
                'authorization' = "Bearer $($EHtoken)"
                'Content-Length' = [System.Text.Encoding]::UTF8.GetByteCount($jsonPayload)
            }

            Write-Information "Sending chunk $currentChunkNumber of $totalChunks (Size: $payloadSizeKB KB, Records: $($chunkInfo.Records.Count))"

            # Send the request
            if ($PSVersionTable.PSEdition -eq 'Core') {
                $Response = Invoke-RestMethod -Uri $EventHubUri -Method Post -Headers $headers -Body $jsonPayload -SkipHeaderValidation -SkipCertificateCheck
            } else {
                $Response = Invoke-RestMethod -Uri $EventHubUri -Method Post -Headers $headers -Body $jsonPayload
            }

            $successfulChunks++
            Write-Information "Successfully sent chunk $currentChunkNumber of $totalChunks to Event Hub"

        } catch {
            $chunkError = "Event Hub transmission failed for chunk $currentChunkNumber of $totalChunks"
            $exceptionMessage = $_.Exception.Message
            
            # Enhanced 413 error handling with resource identification
            if ($exceptionMessage -match "413|Request Entity Too Large") {
                Write-Error "PAYLOAD TOO LARGE ERROR - Chunk $currentChunkNumber exceeds Basic SKU Event Hub limits (256KB)"
                Write-Error "Chunk Size: $($chunkInfo.SizeKB) KB (Basic SKU limit: 256KB)"
                Write-Error "Resource Count: $($chunkInfo.Records.Count)"
                Write-Error "RECOMMENDATION: Batch sizing algorithm needs adjustment - please report this issue"
                Write-Error "Affected Resources in this chunk:"
                
                # List the first 5 resource IDs to help identify the problem
                $displayCount = [Math]::Min(5, $chunkInfo.ResourceIds.Count)
                for ($i = 0; $i -lt $displayCount; $i++) {
                    Write-Error "  - $($chunkInfo.ResourceIds[$i])"
                }
                if ($chunkInfo.ResourceIds.Count -gt 5) {
                    Write-Error "  ... and $($chunkInfo.ResourceIds.Count - 5) more resources"
                }
                
                # Store failed chunk info for summary
                $failedChunks += @{
                    ChunkNumber = $currentChunkNumber
                    SizeKB = $chunkInfo.SizeKB
                    ResourceCount = $chunkInfo.Records.Count
                    ResourceIds = $chunkInfo.ResourceIds
                    Error = "413 - Payload Too Large (Basic SKU Limit Exceeded)"
                }
            }
            
            Write-Error "$chunkError - $exceptionMessage"
            
            # Enhanced error diagnostics for Event Hub issues
            if ($exceptionMessage -match "401|unauthorized") {
                Write-Error "EVENT HUB PERMISSION ERROR - This is a FATAL configuration issue"
                Write-Error "1. Managed Identity '$($env:CLIENTID)' needs 'Azure Event Hubs Data Sender' role"
                Write-Error "2. Role assignment on Event Hub Namespace: '$($env:EVENTHUBNAMESPACE)'"
                Write-Error "3. Target Event Hub: '$($env:EVENTHUBNAME)'"
                Write-Error "4. NOTE: Managed identity permissions can take up to 24 hours to propagate"
                Write-Error "5. RECOMMENDATION: Wait 24 hours after role assignment or use alternative authentication"
                
                # This is a fatal error - don't retry
                throw [System.Security.Authentication.AuthenticationException]::new("Event Hub authentication failed - managed identity lacks required permissions", $_.Exception)
            }
            elseif ($exceptionMessage -match "403|forbidden") {
                Write-Error "EVENT HUB AUTHORIZATION ERROR - Managed identity has insufficient permissions"
                throw [System.UnauthorizedAccessException]::new("Event Hub authorization failed - check role assignments", $_.Exception)
            }
            elseif ($exceptionMessage -match "404|not found") {
                Write-Error "EVENT HUB NOT FOUND - Check namespace and Event Hub names"
                Write-Error "Namespace: '$($env:EVENTHUBNAMESPACE)'"
                Write-Error "Event Hub: '$($env:EVENTHUBNAME)'"
                throw [System.ArgumentException]::new("Event Hub configuration error - resource not found", $_.Exception)
            }
            else {
                # For other errors, provide generic guidance
                Write-Error "EVENT HUB COMMUNICATION ERROR: $exceptionMessage"
                
                # Store failed chunk info
                $failedChunks += @{
                    ChunkNumber = $currentChunkNumber
                    SizeKB = $chunkInfo.SizeKB
                    ResourceCount = $chunkInfo.Records.Count
                    ResourceIds = $chunkInfo.ResourceIds
                    Error = $exceptionMessage
                }
            }
        }
    }

    # Enhanced completion reporting
    if ($failedChunks.Count -gt 0) {
        Write-Error "TRANSMISSION SUMMARY - Some chunks failed (Basic SKU Event Hub):"
        Write-Error "Successful chunks: $successfulChunks / $totalChunks"
        Write-Error "Failed chunks: $($failedChunks.Count)"
        
        foreach ($failedChunk in $failedChunks) {
            Write-Error "Failed Chunk $($failedChunk.ChunkNumber): $($failedChunk.Error)"
            Write-Error "  Size: $($failedChunk.SizeKB) KB, Resources: $($failedChunk.ResourceCount)"
        }
        
        Write-Error "BASIC SKU RECOMMENDATION: Consider upgrading to Standard SKU for 1MB message limits"
    } else {
        Write-Information "Successfully transmitted all $successfulChunks chunks to Basic SKU Event Hub"
    }

    return @{
        ChunksSent = $successfulChunks
        TotalChunks = $totalChunks
        Success = ($successfulChunks -eq $totalChunks)
        EventHubUri = $EventHubUri
        FailedChunks = $failedChunks
        OversizedResources = $oversizedResources
        SKURecommendation = if ($failedChunks.Count -gt 0) { "Consider upgrading to Standard SKU for larger message limits" } else { $null }
    }
}
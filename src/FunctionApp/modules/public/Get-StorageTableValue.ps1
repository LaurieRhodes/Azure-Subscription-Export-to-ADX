function Get-StorageTableValue {
    [CmdletBinding()]
    [OutputType([System.String])]
    param (
        [Parameter(Mandatory=$true)]
        [object]$StorageTable,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$TableName,

        [Parameter(Mandatory=$false)]
        [string]$PartitionKey = "part1",

        [Parameter(Mandatory=$false)]
        [string]$RowKey = "1",

        [Parameter(Mandatory=$false)]
        [string]$DefaultStartTime = (Get-Date).ToUniversalTime().ToString("o")
    )

    begin {
        Write-Debug "[Get-StorageTableValue] Starting retrieval for table: $TableName"

        # Validate storage context is available in parent scope
        if (-not (Get-Variable -Name 'StorageTable' -ErrorAction SilentlyContinue)) {
            throw "Storage context not found. Ensure 'StorageTable' variable is defined in parent scope."
        }
    }

    process {
        try {
            # Initialize or get table
            $cloudTable = $null

            if ($null -eq $StorageTable.Name) {
                Write-Debug "[Get-StorageTableValue] Table doesn't exist. Creating new table: $TableName"

                try {
                    New-AzStorageTable -Name $TableName -Context $StorageTable -ErrorAction Stop
                    Write-Debug "[Get-StorageTableValue] Table created successfully"

                    $cloudTable = (Get-AzStorageTable -Name $TableName -Context $StorageTable.Context).CloudTable

                    # Initialize with default start time
                    $properties = @{
                        "starttime" = $DefaultStartTime
                    }

                    Add-AzTableRow -Table $cloudTable `
                                           -PartitionKey $PartitionKey `
                                           -RowKey $RowKey `
                                           -Property $properties `
                                           -UpdateExisting

                    Write-Debug "[Get-StorageTableValue] Initialized new table row with start time: $DefaultStartTime"
                }
                catch {
                    throw "Failed to create storage table: $($_.Exception.Message)"
                }
            }
            else {
                Write-Debug "[Get-StorageTableValue] Using existing table"
                $cloudTable = (Get-AzStorageTable -Name $TableName -Context $StorageTable.Context).CloudTable
            }

            # Retrieve the row with retry logic
            $maxRetries = 3
            $retryCount = 0
            $retryDelaySeconds = 2
            $row = $null

            do {
                try {
                    $row = Get-AzTableRow -Table $cloudTable `
                                        -PartitionKey $PartitionKey `
                                        -RowKey $RowKey `
                                        -ErrorAction Stop
                    break
                }
                catch {
                    $retryCount++
                    if ($retryCount -eq $maxRetries) {
                        throw
                    }
                    Write-Warning "[Get-StorageTableValue] Attempt $retryCount failed. Retrying in $retryDelaySeconds seconds..."
                    Start-Sleep -Seconds $retryDelaySeconds
                    $retryDelaySeconds *= 2
                }
            } while ($retryCount -lt $maxRetries)

            # Handle missing or invalid start time
            if ($null -eq $row -or $null -eq $row.starttime) {
                Write-Debug "[Get-StorageTableValue] No valid start time found. Initializing with default."

                $properties = @{
                    "starttime" = $DefaultStartTime
                }

                Add-AzTableRow -Table $cloudTable `
                                -PartitionKey $PartitionKey `
                                -RowKey $RowKey `
                                -Property $properties `
                                -UpdateExisting

                return $DefaultStartTime
            }

            Write-Debug "[Get-StorageTableValue] Retrieved start time: $($row.starttime)"
            return $row.starttime.ToString()
        }
        catch {
            $errorMessage = "[Get-StorageTableValue] Failed to retrieve storage table value: $($_.Exception.Message)"
            if ($_.Exception.InnerException) {
                $errorMessage += " Inner Exception: $($_.Exception.InnerException.Message)"
            }
            Write-Error $errorMessage
            throw $errorMessage
        }
    }
}

# Example usage:
<#
try {
    $lastRunTime = Get-StorageTableValue -StorageTable $storageTable `
                                        -TableName "MyTable" `
                                        -Verbose
    Write-Debug "Last run time: $lastRunTime"
}
catch {
    Write-Error "Failed to get storage table value: $_"
}
#>
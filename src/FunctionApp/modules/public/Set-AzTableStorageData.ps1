function Set-AzTableStorageData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Common.Authentication.Abstractions.IStorageContext]$StorageContext,
        
        [Parameter(Mandatory = $true)]
        [string]$PartitionKey,
        
        [Parameter(Mandatory = $true)]
        [string]$RowKey,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Properties,
        
        [switch]$CreateIfNotExists = $true
    )
    
    try {
        # Initialize logging
        Write-Information "Starting table storage operation for table: $TableName"
        
        # Get or create table
        $storageTable = Get-AzStorageTable -Name $TableName -Context $StorageContext -ErrorAction Ignore
        
        if ($null -eq $storageTable.Name) {
            if ($CreateIfNotExists) {
                Write-Information "Creating new storage table: $TableName"
                $result = New-AzStorageTable -Name $TableName -Context $StorageContext
                if (-not $result.Name) {
                    throw "Failed to create table $TableName"
                }
                $cloudTable = (Get-AzStorageTable -Name $TableName -Context $StorageContext.Context).CloudTable
            }
            else {
                throw "Table $TableName does not exist and CreateIfNotExists is false"
            }
        }
        else {
            $cloudTable = (Get-AzStorageTable -Name $TableName -Context $StorageContext.Context).CloudTable
        }
        
        # Try to get existing row
        $existingRow = Get-AzTableRow -Table $cloudTable -PartitionKey $PartitionKey -RowKey $RowKey -ErrorAction Ignore
        
        # Add or update row
        if ($null -eq $existingRow) {
            Write-Information "Adding new row with PartitionKey: $PartitionKey, RowKey: $RowKey"
            $result = Add-AzTableRow -Table $cloudTable `
                                   -PartitionKey $PartitionKey `
                                   -RowKey $RowKey `
                                   -Property $Properties
        }
        else {
            Write-Information "Updating existing row with PartitionKey: $PartitionKey, RowKey: $RowKey"
            $result = Add-AzTableRow -Table $cloudTable `
                                   -PartitionKey $PartitionKey `
                                   -RowKey $RowKey `
                                   -Property $Properties `
                                   -UpdateExisting
        }
        
        # Verify operation
        $verifiedRow = Get-AzTableRow -Table $cloudTable -PartitionKey $PartitionKey -RowKey $RowKey
        if ($null -eq $verifiedRow) {
            throw "Failed to verify row after write operation"
        }
        
        return $verifiedRow
    }
    catch {
        Write-Error "Error in Set-AzTableStorageData: $_"
        throw
    }
}
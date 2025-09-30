function Get-AzTableStorageData {
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
        [string]$PropertyName
    )

    # Create the storage table if it doesnt exist
    $StorageTable = Get-AzStorageTable -Name $Tablename -Context $StorageContext -ErrorAction Ignore
    if($null -eq $StorageTable.Name){
        write-information "creating new storage table"
        $result = New-AzStorageTable -Name $Tablename -Context $StorageContext
        write-information "storage table creation result = $($result | convertto-json)"
        $Table = (Get-AzStorageTable -Name $Tablename -Context $StorageContext.Context).cloudTable
        $result = Add-AzTableRow -table $Table -PartitionKey "part1" -RowKey "1" -property @{"$($PropertyName)"=""} -UpdateExisting
    }


    try {
        $cloudTable = (Get-AzStorageTable -Name $TableName -Context $StorageContext ).CloudTable






        $row = Get-AzTableRow -Table $cloudTable -PartitionKey $PartitionKey -RowKey $RowKey
        
        if ($null -eq $row) {
            Write-Information "No row found with PartitionKey: $PartitionKey, RowKey: $RowKey"
            return $null
        }
        
        if (-not $row.$PropertyName) {
            Write-Information "Property '$PropertyName' not found in row"
            return $null
        }
        
        return $row.$PropertyName.ToString()
    }
    catch {
        Write-Error "Error in Get-AzTableStorageData: $_"
        throw
    }
}
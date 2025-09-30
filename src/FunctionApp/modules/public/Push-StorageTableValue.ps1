function Push-StorageTableValue {
    Param (
        [string]$ClientId,
        [string]$StorageAccountName,
        [string]$TableName,
        [datetime]$DateTimeValue = (Get-Date).AddHours(-1).ToUniversalTime().ToString("R")
    )
<#
  The function is hardcoded to retrieve the value of 'lastUpdated' from the nominated Storage Account table.

#>

    $resource = "https://storage.azure.com/"

    Write-Debug "(Push-StorageTableValue) calling Get-AzureADToken -resource $($resource) -clientId $($ClientId)"
    $token = Get-AzureADToken -resource $resource -clientId $ClientId

    $Date = (Get-Date).ToUniversalTime().ToString("R")

    $authHeader = @{
        "Authorization" = "Bearer $($token)"
        "Content-Type" = "application/json"
        'Accept' = 'application/json;odata=nometadata'
        "x-ms-version" = "2020-08-04"
        "x-ms-date" = $Date
    }

    $entity = @{
        lastUpdated = $DateTimeValue
    }

    $body = ConvertTo-Json -InputObject $entity


    $uri = "https://$($StorageAccountName).table.core.windows.net/$($TableName)(PartitionKey='$($TableName)',RowKey='lastUpdated')"

    try {
        Write-Debug "(Push-StorageTableValue) calling-Uri $($uri )"
        $response = Invoke-RestMethod -Uri $uri -Headers $authHeader -Method PUT -Body $body
        Write-Debug "(Push-StorageTableValue) response.value received $($response.value)"
        return $response.value

    } catch {
            Write-Error "Failed to update entity: $_"
    }

}

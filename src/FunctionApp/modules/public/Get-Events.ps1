function Get-Events {
    param (
        [Parameter(Mandatory=$false)]
        [string]$Starttime
    )
    # Retrieve Okta events using API
    try {
        $Token = Get-Token

        $headers = @{
            "Authorization" = "SSWS $Token"
            "Accept"        = "application/json"
            "User-Agent"    = "OktaIngestor/1.0"
        }

     # ensure ISO  ISO 8601 is used with datetime  
    $starttime =   ([System.DateTime]$($starttime)).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ")

#        $Url = "$($env:QUERYENDPOINT)?since=$($starttime)&order=asc&limit=1000"
        $Url = "$($env:QUERYENDPOINT)?limit=1000"
#write-information "Calling Okta endpoint with header= $($headers | convertto-json)"
write-debug "Okta Query URL = $($Url)"
        # Check if the script is running in PowerShell Core

        $useSkipHeaderValidation = $($PSVersionTable.PSEdition) -eq 'Core'
    $allOktaEvents = @()

    while ($Url) {
        write-debug "Querying Okta with URL: $Url"

        # Invoke the API call with or without SkipHeaderValidation based on PowerShell edition
        if ($useSkipHeaderValidation) {
            $response = Invoke-RestMethod -Uri $Url -Headers $headers -Method Get -SkipHeaderValidation -Verbose
        } else {
            $response = Invoke-RestMethod -Uri $Url -Headers $headers -Method Get -Verbose
        }

        # Store the received events
        $allOktaEvents += $response

        # Check for the 'Link' header to find the 'next' page link
        $linkHeader = $response.PSObject.Properties["Link"].Value
        if ($linkHeader -match '<(.*?)>; rel="next"') {
            $Url = $matches[1]
        } else {
            # No next link, so exit the loop
            $Url = $null
        }
    }

    } catch {
        Write-Error "Error retrieving events: $_"
        throw
    }

     return $allOktaEvents
}
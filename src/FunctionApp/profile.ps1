# Azure Functions profile.ps1
#
# This profile.ps1 will get executed every "cold start" of your Function App.
# "cold start" occurs when:
#
# * A Function App starts up for the very first time
# * A Function App starts up after being de-allocated due to inactivity
#

Write-Information "Function App starting up - Profile.ps1 executing"
Write-Information "PowerShell Version: $($PSVersionTable.PSVersion)"

# Check if we're in Azure Functions environment
if ($env:WEBSITE_SITE_NAME) {
    Write-Information "Running in Azure Functions: $($env:WEBSITE_SITE_NAME)"
}
else {
    Write-Information "Running in local development environment"
}

#
# Initialize SubscriptionExporter Module
#

# Get the path to the current script directory
$scriptDirectory = $PSScriptRoot
Write-Debug "Script Directory: $scriptDirectory"
    
# Define the relative path to the modules directory
$modulesPath = Join-Path $scriptDirectory 'modules'
Write-Debug "Modules Path: $modulesPath"
    
# Check if the modules directory exists
if (Test-Path $modulesPath) {
    # Resolve the full path to the modules directory
    $resolvedModulesPath = (Get-Item $modulesPath).FullName
    Write-Debug "Resolved Modules Path: $resolvedModulesPath"
    
    # Import the main SubscriptionExporter module
    $mainModulePath = Join-Path $resolvedModulesPath "SubscriptionExporter.psm1"
    if (Test-Path $mainModulePath) {
        try {
            Write-Information "Importing main module: SubscriptionExporter.psm1"
            Import-Module $mainModulePath -Force -Verbose:$false
            Write-Information "Successfully imported SubscriptionExporter module"
        }
        catch {
            Write-Error "Failed to import SubscriptionExporter module: $($_.Exception.Message)"
            throw
        }
    }
    else {
        Write-Error "SubscriptionExporter.psm1 not found at: $mainModulePath"
        throw "Critical module file missing"
    }
    
    # Import any additional PowerShell modules (.psm1 files) in subdirectories
    $additionalModules = Get-ChildItem -Path $resolvedModulesPath -Filter *.psm1 -Recurse | 
        Where-Object { $_.Name -ne "SubscriptionExporter.psm1" }
    
    if ($additionalModules) {
        Write-Information "Found $($additionalModules.Count) additional module(s)"
        foreach ($module in $additionalModules) {
            try {
                Write-Debug "Importing additional module: $($module.FullName)"
                Import-Module $module.FullName -Force -Verbose:$false
                Write-Information "Successfully imported module: $($module.Name)"
            }
            catch {
                Write-Warning "Failed to import module $($module.Name): $($_.Exception.Message)"
            }
        }
    }
}
else {
    Write-Error "Modules directory not found at: $modulesPath"
    throw "Critical modules directory missing"
}

# Load required .NET assemblies
try {
    [Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null
    Write-Debug "System.Web assembly loaded successfully"
}
catch {
    Write-Warning "Failed to load System.Web assembly: $($_.Exception.Message)"
}

# Verify critical environment variables are present (informational only)
$requiredEnvVars = @('CLIENTID', 'EVENTHUBNAMESPACE', 'EVENTHUBNAME', 'SUBSCRIPTION_ID')
$presentVars = @()
$missingVars = @()

foreach ($envVar in $requiredEnvVars) {
    if (Get-ChildItem env: | Where-Object { $_.Name -eq $envVar }) {
        $presentVars += $envVar
    }
    else {
        $missingVars += $envVar
    }
}

Write-Information "Environment Variables Status:"
Write-Information "  Present: $($presentVars -join ', ')"
if ($missingVars.Count -gt 0) {
    Write-Warning "  Missing: $($missingVars -join ', ')"
}

# Verify critical functions are available
$criticalFunctions = @('Invoke-SubscriptionDataExport', 'Get-AzureARMToken', 'Send-EventsToEventHub')
$availableFunctions = @()
$missingFunctions = @()

foreach ($func in $criticalFunctions) {
    if (Get-Command -Name $func -ErrorAction SilentlyContinue) {
        $availableFunctions += $func
    }
    else {
        $missingFunctions += $func
    }
}

Write-Information "Critical Functions Status:"
Write-Information "  Available: $($availableFunctions -join ', ')"
if ($missingFunctions.Count -gt 0) {
    Write-Warning "  Missing: $($missingFunctions -join ', ')"
}

Write-Information "Profile.ps1 execution completed successfully"
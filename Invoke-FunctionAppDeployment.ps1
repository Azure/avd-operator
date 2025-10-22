param (
    [Parameter()]
    [bool]
    $GovCloud = $true,

    [Parameter(Mandatory=$false)]
    [string]
    $FunctionAppPath = "function-app",

    [Parameter(Mandatory=$false)]
    [string]
    $ParamFilePath = ".\bicep\main.dev.bicepparam",

    [Parameter()]
    [switch]
    $UpgradeBicep
)

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$InformationPreference = [System.Management.Automation.ActionPreference]::Continue
$WarningPreference     = [System.Management.Automation.ActionPreference]::Continue

if ($UpgradeBicep) {
    Write-Output "Upgrading bicep"
    az bicep upgrade
}

# Parse bicep param file to retrieve host pool and subscription id, so that we can dynamically authenticate and set the right
# subscription context. We also set the function app name and resource group name dynamically based on the bicep param file.
Write-Information "Parsing Bicep parameter file '$($ParamFilePath)'"
$jsonFileName = $ParamFilePath.Replace('.bicepparam', '.json')
try {
    az bicep build-params -f $ParamFilePath --outfile $jsonFileName
}
catch {
    throw "Failed to build bicep parameters from file '$($ParamFilePath)': $($_.Exception.Message)"
}
$parameters = Get-Content -Path $jsonFileName -Raw | ConvertFrom-Json
Remove-Item -Path $jsonFileName -Force

# Check to see if the current subscription matches the host pool subscription id, otherwise login and set the right subscription
if ($(az account show --query "id" -o tsv) -ne $parameters.parameters.pHostPool.value.subscriptionId) {
    Write-Output "Please login to Azure"
    if ($GovCloud) {
        Write-Output "Setting cloud to 'AzureUSGovernment'"
        az cloud set --name 'AzureUSGovernment'
    }
    try {
        az login
    }
    catch {
        throw "Azure login failed: $($_.Exception.Message)"
    }
    Write-Output "Set subscription to '$($parameters.parameters.pHostPool.value.subscriptionId)'"
    az account set --subscription $parameters.parameters.pHostPool.value.subscriptionId
}

# Function app name matches host pool name
$functionAppName = $parameters.parameters.pHostPool.value.name 
$resourceGroupName = $parameters.parameters.pFunctionAppResourceGroupName.value
Write-Output "Target function app name:   '$($functionAppName)'"
Write-Output "Target resource group name: '$($resourceGroupName)'"

Write-Output "Deploying functions to function app '$($functionAppName)' in resource group '$($resourceGroupName)'"
Compress-Archive -Path ".\$FunctionAppPath\*" -DestinationPath 'function-app.zip' -Force
az functionapp deployment source config-zip -g $resourceGroupName -n $functionAppName --src 'function-app.zip'
Remove-Item -Path 'function-app.zip' -Force

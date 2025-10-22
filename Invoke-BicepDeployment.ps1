<#
    .SYNOPSIS
        Deploys a Bicep template to Azure, to deploy the required resources for AVD Operator.

    .DESCRIPTION
        This script parses the passed-in Bicep parameter file, sets the appropriate Azure
        subscription context, optionally upgrades Bicep, and deploys the template to the
        specified resource group.

    .PARAMETER BicepTemplatePath
        Path to the Bicep template file.

    .PARAMETER DownloadRDAgents
        Indicates whether to download RD Agent binaries to the specified storage account.

    .PARAMETER GovCloud
        Indicates whether to use Azure US Government cloud.

    .PARAMETER ParamFilePath
        Path to the Bicep parameter file.

    .PARAMETER UpgradeBicep
        Switch to upgrade Bicep CLI before deployment.

    .EXAMPLE
        $params = @{
            BicepTemplatePath = ".\bicep\main.bicep"
            DownloadRDAgents  = $true
            GovCloud          = $true
            ParamFilePath     = ".\bicep\main.dev.bicepparam"
            UpgradeBicep      = $false
        }
        .\Invoke-BicepDeployment.ps1 @params

        Deploys the Bicep template using the specified parameter file in Azure US Government cloud,
        upgrading Bicep CLI before deployment.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]
    $BicepTemplatePath,

    [Parameter()]
    [switch]
    $DownloadRDAgents,

    [Parameter()]
    [bool]
    $GovCloud = $true,

    [Parameter()]
    [string]
    $ParamFilePath,

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
# subscription context. We also set the resource group name dynamically based on the bicep param file.
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
$resourceGroupName = $parameters.parameters.pFunctionAppResourceGroupName.value
Write-Output "Deploying bicep to resource group '$($resourceGroupName)' using parameter file '$($ParamFilePath)'"
az deployment group create `
    --name $resourceGroupName `
    --resource-group $resourceGroupName `
    --template-file $BicepTemplatePath `
    --mode "Incremental" `
    --output none `
    --parameters $ParamFilePath

if ($LASTEXITCODE -ne 0) {
    throw "Bicep deployment failed"
}
Write-Output "Bicep deployment completed successfully."

if ($DownloadRDAgents) {
    $params = @{
        AssetStorageAccountName              = $parameters.parameters.pAssetStorageAccount.value.name
        AssetStorageAccountResourceGroupName = $parameters.parameters.pAssetStorageAccount.value.resourceGroupName
    }
    Write-Output "Downloading RD Agent binaries to Storage Account '$($params.AssetStorageAccountName)' in Resource Group '$($params.AssetStorageAccountResourceGroupName)'"
    .\Invoke-RdAgentDownload.ps1 @params
}

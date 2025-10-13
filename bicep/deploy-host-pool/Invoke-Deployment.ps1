[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [String] $ResourceGroupName,

    [Parameter(Mandatory)]
    [String] $SubscriptionId
)

Write-Output "Upgrading bicep"
az bicep upgrade

Write-Output "Getting Azure tags"
$AzureTags = $env:AZURE_TAGS | ConvertFrom-Json -AsHashtable -Depth 100
$AzureTags.deployment_tool = "Bicep"

Write-Output "Getting deployment locations"
$DeploymentLocationsJsonFilePath = Join-Path -Path $PWD -ChildPath "deployment-locations.json"
if (-not (Test-Path $DeploymentLocationsJsonFilePath)) {
    throw "Failed to find deployment locations file at '$DeploymentLocationsJsonFilePath'"
}
$DeploymentLocations = Get-Content -Path $DeploymentLocationsJsonFilePath | ConvertFrom-Json -AsHashtable -Depth 100

Write-Output "Deploying bicep to resource group '${ResourceGroupName}'"
az deployment group create `
    --name "geekly-host-pool" `
    --resource-group $ResourceGroupName `
    --template-file "./bicep/deploy-host-pool/main.bicep" `
    --mode "Incremental" `
    --output none `
    --parameters `
    pAssetStorageAccount=$($env:ASSET_STORAGE_ACCOUNT | ConvertFrom-Json -AsHashtable -Depth 100 | ConvertTo-Json -Depth 100 -Compress) `
    pAuthKeyVault=$($env:AUTH_KEY_VAULT | ConvertFrom-Json -AsHashtable -Depth 100 | ConvertTo-Json -Depth 100 -Compress) `
    pDeploymentLocations=$($DeploymentLocations | ConvertTo-Json -Depth 100 -Compress) `
    pEntraIdSecurityDeviceGroupName=$env:ENTRA_ID_SECURITY_DEVICE_GROUP_NAME `
    pGalleryImageDefinition=$($env:GALLERY_IMAGE_DEFINITION | ConvertFrom-Json -AsHashtable -Depth 100 | ConvertTo-Json -Depth 100 -Compress) `
    pLogAnalyticsWorkspace=$($env:LOG_ANALYTICS_WORKSPACE | ConvertFrom-Json -AsHashtable -Depth 100 | ConvertTo-Json -Depth 100 -Compress) `
    pScalingPlans=$($env:SCALING_PLANS | ConvertFrom-Json -AsHashtable -Depth 100 | ConvertTo-Json -Depth 100 -Compress) `
    pTags=$($AzureTags | ConvertTo-Json -Depth 100 -Compress) `
    pVirtualMachineSKUSize=$env:VIRTUAL_MACHINE_SIZE `

if ($LASTEXITCODE -ne 0) {
    throw "Bicep deployment failed"
    exit 1
}

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [String] $AppConfigurationStoreName,

    [Parameter(Mandatory)]
    [String] $FunctionAppName,

    [Parameter(Mandatory)]
    [String] $ResourceGroupName
)

Write-Output "Upgrading bicep"
az bicep upgrade

Write-Output "Getting Azure tags"
$AzureTags = $env:AZURE_TAGS | ConvertFrom-Json -AsHashtable -Depth 100
$AzureTags.deployment_tool = "Bicep"

Write-Output "Deploying bicep to resource group '${ResourceGroupName}'"
az deployment group create `
    --name "geekly-function-app-$($FunctionAppName)" `
    --resource-group $ResourceGroupName `
    --template-file "./bicep/deploy-function-app/main.bicep" `
    --mode "Incremental" `
    --output none `
    --parameters `
    pAppConfigurationStoreName=$AppConfigurationStoreName `
    pAuthKeyVault=$($env:AUTH_KEY_VAULT | ConvertFrom-Json -AsHashtable -Depth 100 | ConvertTo-Json -Depth 100 -Compress) `
    pFunctionAppName=$FunctionAppName `
    pLocation=$env:LOCATION `
    pLogAnalyticsWorkspace=$($env:LOG_ANALYTICS_WORKSPACE | ConvertFrom-Json -AsHashtable -Depth 100 | ConvertTo-Json -Depth 100 -Compress) `
    pTags=$($AzureTags | ConvertTo-Json -Depth 100 -Compress) `

if ($LASTEXITCODE -ne 0) {
    throw "Bicep deployment failed"
    exit 1
}

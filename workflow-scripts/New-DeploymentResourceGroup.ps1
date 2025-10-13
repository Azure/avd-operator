[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [String] $DeveloperUsername,

    [Parameter(Mandatory)]
    [String] $Location,

    [Parameter(Mandatory)]
    [String] $PullRequestNumber
)

function New-ResourceGroup {
    [OutputType()]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Object] $AzureTags,

        [Parameter(Mandatory, ValueFromPipeline)]
        [Object] $ResourceGroup
    )

    begin {}

    process {
        $OriginalSubscriptionContext = Get-AzContext
        Set-AzContext -Subscription $ResourceGroup.SubscriptionId | Out-Null

        Write-Output "Checking if resource group '$($ResourceGroup.Name)' already exists"
        $ExistingResourceGroup = Get-AzResourceGroup -Name $ResourceGroup.Name -ErrorAction SilentlyContinue
        if ($null -ne $ExistingResourceGroup) {
            try {
                Write-Output "Successfully found resource group '$($ResourceGroup.Name)'"
                Write-Output "Enforcing tags on existing resource group '$($ResourceGroup.Name)'"
                Update-AzTag -ResourceId $ExistingResourceGroup.ResourceId -Tag $AzureTags -Operation "Merge"
            } catch {
                Write-Warning "Failed to update tags on existing resource group '$($ResourceGroup.Name)'"
                throw $PSItem
            }
        } else {
            try {
                Write-Output "Creating resource group '$($ResourceGroup.Name)'"
                New-AzResourceGroup -Name $ResourceGroup.Name -Location $ResourceGroup.Location -Tag $AzureTags -Force
            } catch {
                Write-Warning "Failed to create resource group '$($ResourceGroup.Name)'"
                throw $PSItem
            }
            Write-Output "Successfully created resource group '$($ResourceGroup.Name)'"
        }

        $OriginalSubscriptionContext | Set-AzContext | Out-Null
    }

    end {}
}

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

$EnvironmentAbbreivations = @{
    SBX  = "S"
    DEV  = "D"
    PROD = "P"
}

$LocationAbbreivations = @{
    usdodeast     = "DE"
    usgovarizona  = "AZ"
    usgovtexas    = "TX"
    usgovvirginia = "VA"
}

try {
    $AzureTags = $env:AZURE_TAGS | ConvertFrom-Json -AsHashtable
    if ($null -eq $AzureTags) {
        throw "Failed to find Azure tags"
    } else {
        $AzureTags.developer_username = $DeveloperUsername
        $AzureTags.pull_request_number = $PullRequestNumber
    }

    $DeploymentLocations = $env:DEPLOYMENT_LOCATIONS | ConvertFrom-Json -AsHashtable -Depth 100
    $EnvironmentAbbreivation = $EnvironmentAbbreivations.$($AzureTags.environment)
    $MainLocationAbbreivation = $LocationAbbreivations.$env:LOCATION

    $Characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    $RandomIdentifier = ""
    Get-Random -SetSeed $PullRequestNumber | Out-Null
    for ($i = 0; $i -lt 3; $i++) {
        $RandomIdentifier += $Characters[(Get-Random -Maximum $Characters.Length)]
    }
    Write-Output "Generated random identifier '$RandomIdentifier' based on pull request number '$PullRequestNumber'"

    $ResourceGroupsToCreate = [System.Collections.Generic.List[Object]]::new()
    foreach ($DeploymentLocation in $DeploymentLocations) {
        $LocationAbbreivation = $LocationAbbreivations.$($DeploymentLocation.location)
        $DeploymentLocation.sessionHostNamePrefix = "AVD${LocationAbbreivation}GKY${RandomIdentifier}".toUpper()
        $DeploymentLocation.computeResourceGroup = @{
            name           = "${EnvironmentAbbreivation}-AVD-AUTO-${LocationAbbreivation}-GKY${RandomIdentifier}-VM".toUpper()
            subscriptionId = $DeploymentLocation.virtualNetworkSubnet.subscriptionId
        }

        $ResourceGroupsToCreate.Add(@{
                Name           = $DeploymentLocation.computeResourceGroup.name
                Location       = $DeploymentLocation.location
                SubscriptionId = $DeploymentLocation.computeResourceGroup.subscriptionId
            }
        )
    }

    $HostPoolResourceGroup = @{
        Name           = "${EnvironmentAbbreivation}-AVD-AUTO-${MainLocationAbbreivation}-GKY${RandomIdentifier}-HP".toUpper()
        Location       = $env:LOCATION
        SubscriptionId = $env:HOST_POOL_SUBSCRIPTION_ID
    }
    $ResourceGroupsToCreate.Add($HostPoolResourceGroup)

    $FunctionAppResourceGroup = @{
        Name           = "${EnvironmentAbbreivation}-AVD-AUTO-${MainLocationAbbreivation}-GKY${RandomIdentifier}-FC".toUpper()
        Location       = $env:LOCATION
        SubscriptionId = $env:HOST_POOL_SUBSCRIPTION_ID
    }
    $ResourceGroupsToCreate.Add($FunctionAppResourceGroup)

    $ResourceGroupsToCreate | New-ResourceGroup -AzureTags $AzureTags
    $DeploymentLocationsJsonFilePath = Join-Path -Path $PWD -ChildPath "deployment-locations.json"
    $DeploymentLocations | ConvertTo-Json -AsArray -Compress -Depth 100 | Out-File -FilePath $DeploymentLocationsJsonFilePath -Encoding "utf8" -Force

    Write-Output "Adding pull request number '$PullRequestNumber' to GitHub outputs"
    Write-Output "PULL_REQUEST_NUMBER=$PullRequestNumber" >> $env:GITHUB_OUTPUT

    Write-Output "Adding random identifier '$RandomIdentifier' to GitHub outputs"
    Write-Output "RANDOM_IDENTIFIER=$RandomIdentifier" >> $env:GITHUB_OUTPUT

    Write-Output "Adding host pool resource group name '$($HostPoolResourceGroup.Name)' to GitHub outputs"
    Write-Output "HOST_POOL_RESOURCE_GROUP_NAME=$($HostPoolResourceGroup.Name)" >> $env:GITHUB_OUTPUT

    Write-Output "Adding function app resource group name '$($FunctionAppResourceGroup.Name)' to GitHub outputs"
    Write-Output "FUNCTION_APP_RESOURCE_GROUP_NAME=$($FunctionAppResourceGroup.Name)" >> $env:GITHUB_OUTPUT
} catch {
    $ErrorScript = $PSItem.InvocationInfo.ScriptName
    $ErrorScriptLine = "$($PSItem.InvocationInfo.ScriptLineNumber):$($PSItem.InvocationInfo.OffsetInLine)"
    $ErrorMessage = "$($PSItem.Exception.Message) Error Script: $ErrorScript, Error Line: $ErrorScriptLine"
    Write-Error -Message $ErrorMessage -Exception $PSItem.Exception
}
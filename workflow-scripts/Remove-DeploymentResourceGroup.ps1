[CmdletBinding(DefaultParameterSetName = "Commit")]
param(
    [Parameter(Mandatory, ParameterSetName = "Commit")]
    [String] $CommitMessage,

    [Parameter(Mandatory, ParameterSetName = "PullRequest")]
    [String] $PullRequestNumber
)

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

try {
    Write-Output "Getting pull request number"
    if ($PSCmdlet.ParameterSetName -eq "Commit") {
        $CommitMessage -match "#(\d+)" | Out-Null
        $PullRequestNumber = $Matches[1]
    }
    Write-Output "Found pull request number '$PullRequestNumber'"

    $Subscriptions = @{
        "Compute"   = $env:COMPUTE_SUBSCRIPTION_ID
        "Host Pool" = $env:HOST_POOL_SUBSCRIPTION_ID
    }

    foreach ($Subscription in $Subscriptions.GetEnumerator()) {
        Set-AzContext -Subscription $Subscription.Value | Out-Null

        Write-Output "Getting resource groups with tag 'pull_request_number:${PullRequestNumber}' in the $($Subscription.Name.ToLower()) subscription"
        $ResourceGroups = Get-AzResourceGroup -Tag @{ pull_request_number = $PullRequestNumber }
        Write-Output "Found $($ResourceGroups.Count) resource groups with tag 'pull_request_number:${PullRequestNumber}' in the $($Subscription.Name.ToLower()) subscription"
        if ($ResourceGroups.Count -gt 0) {
            $ResourceGroups | ForEach-Object -ThrottleLimit 50 -Parallel {
                try {
                    Write-Output "Attempting to remove resource group '$($PSItem.ResourceGroupName)'"
                    Remove-AzResource -ResourceId $PSItem.ResourceId -Force | Out-Null
                } catch {
                    Write-Warning "Failed to remove resource groups with tag 'pull_request_number:${PullRequestNumber}'"
                    throw $PSItem
                }
                Write-Output "Successfully removed resource group '$($PSItem.ResourceGroupName)'"
            }

            $PossibleAppConfigurationNames = $ResourceGroups.ResourceGroupName.where({ $PSItem -ilike "*-hp" })
            if ($PossibleAppConfigurationNames.Count -gt 0) {
                $DeletedAppConfigurations = (Get-AzAppConfigurationDeletedStore).where({ $PossibleAppConfigurationNames -icontains $PSItem.Name })
                Write-Output "Found $($DeletedAppConfigurations.Count) deleted app configurations"
                foreach ($DeletedAppConfiguration in $DeletedAppConfigurations) {
                    try {
                        Write-Output "Attempting to purge deleted app configuration '$($DeletedAppConfiguration.Name)'"
                        $DeletedAppConfiguration | Clear-AzAppConfigurationDeletedStore
                        Write-Output "Waiting 60 seconds for purge of app configuration '$($DeletedAppConfiguration.Name)' to propagate"
                        Start-Sleep -Seconds 60
                        Write-Output "Successfully purged deleted app configuration '$($DeletedAppConfiguration.Name)'"
                    } catch {
                        Write-Warning "Failed to purge deleted app configuration '$($DeletedAppConfiguration.Name)'"
                        throw $PSItem
                    }
                }
            }
        } else {
            Write-Warning "Found 0 resource groups to cleanup"
        }
    }
} catch {
    $ErrorScript = $PSItem.InvocationInfo.ScriptName
    $ErrorScriptLine = "$($PSItem.InvocationInfo.ScriptLineNumber):$($PSItem.InvocationInfo.OffsetInLine)"
    $ErrorMessage = "$($PSItem.Exception.Message) Error Script: $ErrorScript, Error Line: $ErrorScriptLine"
    Write-Error -Message $ErrorMessage -Exception $PSItem.Exception
}
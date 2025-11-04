function Get-Context {
    param(
        [Parameter(Mandatory)]
        [String] $SubscriptionId
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $Context = (Get-AzContext -ListAvailable).where({ $PSItem.Subscription.Id -eq $SubscriptionId })[0]
    return (Get-AzContext -Name $Context.Name)
}
Export-ModuleMember -Function Get-Context

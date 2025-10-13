function Remove-ShutdownSessionHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Object] $HostPool,

        [Parameter(Mandatory)]
        [Int] $SessionHostsToRemoveCount
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Write-Log "Getting session hosts"
    $AzWvdSessionHostParameters = @{
        HostPoolName      = $HostPool.Name
        ResourceGroupName = $HostPool.ResourceGroupName
        SubscriptionId    = $HostPool.SubscriptionId
    }
    $SessionHosts = Get-AzWvdSessionHost @AzWvdSessionHostParameters
    $ShutdownSessionHosts = $SessionHosts.Where({ $PSItem.Status -ieq "Shutdown" })
    Write-Log "Found $($ShutdownSessionHosts.Count) session host(s) that are shutdown out of $($SessionHosts.Count) total session host(s)"

    if ($ShutdownSessionHosts.Count -eq 0) {
        Write-Log "No session hosts will be removed because there are 0 session hosts that are shutdown"
        return
    }

    $SessionHostsQueuedForCleanupCount = 0
    $SessionHostsFailedTagCount = 0
    foreach ($SessionHost in $ShutdownSessionHosts) {
        try {
            $VirtualMachine = $SessionHost.ResourceId | Get-ResourceInformation
            $VirtualMachineContext = Get-Context -SubscriptionId $VirtualMachine.SubscriptionId

            # TODO: What if exclude from scaling
            # tagged virtual machines don't
            # get cleaned up?

            $AzTagParameters = @{
                DefaultProfile = $VirtualMachineContext
                ErrorAction    = "Stop"
                Operation      = "Merge"
                ResourceId     = $VirtualMachine.Id
                Tag            = @{ ExcludeFromScaling = $true }
            }
            Update-AzTag @AzTagParameters | Out-Null
        } catch {
            Write-Log "Failed to add 'ExcludeFromScaling' tag to session host '$($VirtualMachine.Name)' due to error $($PSItem.Exception.Message), session host will not be queued for cleanup" -LogLevel 'WARN'
            $SessionHostsFailedTagCount++
            continue
            # TODO: Should we WARN and continue or use ERRORSTOP to force the function to re-try?
            # if we WARN and continue but there is an ongoing issue with Azure preventing
            # tags from updating then potentially nothing could get queued, if we ERRORSTOP
            # then we could be holding up an entire group of shutdown virtual machines from
            # being cleaned up while waiting on a few problematic virtual machines
        }

        Write-Log "Queueing session host '$($VirtualMachine.Name)' for cleanup because it is no longer needed"
        $OutputQueueCleanup = @{
            Name  = "OutputQueueCleanup"
            Value = @{
                Data = @{
                    SessionHost    = $SessionHost.Id | Get-ResourceInformation
                    VirtualMachine = $VirtualMachine
                }
                Type = "Session Host"
            }
        }
        Push-OutputBinding @OutputQueueCleanup

        $SessionHostsQueuedForCleanupCount++
        if ($SessionHostsQueuedForCleanupCount -eq $SessionHostsToRemoveCount) {
            break
        }
    }

    if (
        ($SessionHostsQueuedForCleanupCount -eq 0) -and
        ($SessionHostsFailedTagCount -gt 0)
    ) {
        # TODO: Is this an extreme edge case? Apparently not as logs show this error in app insights
        # Happened previously because an invalid parameter error occured for the 'Get-ResourceInformation' module
        # but it wasn't considered a terminating error even when we set $ErrorActionPreference globally
        Write-Log "Failed to queue any shutdown session hosts for cleanup" -LogLevel 'ERRORSTOP'
    }
}
Export-ModuleMember -Function Remove-ShutdownSessionHost
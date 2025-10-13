function Remove-SessionHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Object] $SessionHost,

        [Parameter(Mandatory)]
        [Object] $VirtualMachine
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $RemoveResources = $false
    $SessionHostRelatedResources = @($SessionHost, $VirtualMachine) | Get-RelatedResource
    Write-Log "Found $($SessionHostRelatedResources.Count) resource(s) related to session host '$($SessionHost.Name)'"
    if ($SessionHostRelatedResources.Count -gt 0) {
        # Virtual machine resources found above may not always include VM object itself but only related
        # resources (Disks, NICs, etc) if prior cleanup was interrupted or failed to complete successfully

        if ($SessionHostRelatedResources.Type -icontains "Microsoft.Compute/virtualMachines") {
            $VirtualMachineContext = Get-Context -SubscriptionId $VirtualMachine.SubscriptionId

            # Enforcing power status check to ensure only
            # deallocated virtual machines get removed
            $AzVMParameters = @{
                DefaultProfile = $VirtualMachineContext
                ResourceId     = $VirtualMachine.Id
                Status         = $true
            }
            $VirtualMachinePowerState = (Get-AzVM @AzVMParameters).Statuses.where({ $PSItem.Code -ilike "PowerState*" }).DisplayStatus
            Write-Log "Found virtual machine for session host '$($SessionHost.Name)' with power state '${VirtualMachinePowerState}'"

            switch ($VirtualMachinePowerState) {
                "VM running" {
                    Write-Log "Resources of running session host virtual machine '$($SessionHost.Name)' cannot be removed, skipping"
                }

                "VM deallocating" {
                    # TODO: Timeout too long or too short?
                    $Timeout = New-TimeSpan -Minutes 10
                    $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
                    do {
                        Write-Log "Waiting 30 seconds for session host '$($SessionHost.Name)' to become deallocated with current status '${VirtualMachinePowerState}'"
                        Start-Sleep -Seconds 30
                        $VirtualMachinePowerState = (Get-AzVM @AzVMParameters).Statuses.where({ $PSItem.Code -ilike "PowerState*" }).DisplayStatus
                    } until (
                        ($StopWatch.Elapsed -ge $Timeout) -or
                        ($VirtualMachinePowerState -eq "VM deallocated")
                    )
                    $StopWatch.Stop()

                    if ($VirtualMachinePowerState -ne "VM deallocated") {
                        Write-Log "$($Timeout.Minutes) minute wait period exceeded for session host '$($SessionHost.Name)' with power state '${VirtualMachinePowerState}', skipping"
                    } else {
                        $RemoveResources = $true
                    }
                }

                "VM deallocated" {
                    $RemoveResources = $true
                }

                default {
                    Write-Log "Found virtual machine for session host '$($SessionHost.Name)' with unknown power state '${VirtualMachinePowerState}', skipping"
                }
            }
        } else {
            $RemoveResources = $true
        }

        if ($RemoveResources) {
            Write-Log "Removing $($SessionHostRelatedResources.Count) resource(s) related to session host '$($SessionHost.Name)' that are no longer needed"
            $SessionHostRelatedResources | Remove-Resource

            return @{
                SessionHost    = $SessionHost
                VirtualMachine = $VirtualMachine
                Status         = $true
            }
        } else {
            return @{
                SessionHost    = $SessionHost
                VirtualMachine = $VirtualMachine
                Status         = $false
            }
        }
    }
}
Export-ModuleMember -Function Remove-SessionHost
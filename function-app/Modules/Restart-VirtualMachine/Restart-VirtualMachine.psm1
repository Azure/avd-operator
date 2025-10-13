function Restart-VirtualMachine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Object] $VirtualMachine
    )

    begin {
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    }

    process {
        Write-Log "Restarting virtual machine '$($VirtualMachine.Name)'"
        $VirtualMachineContext = Get-Context -SubscriptionId $VirtualMachine.SubscriptionId
        $RestartedVirtualMachine = Restart-AzVM -Id $VirtualMachine.id -DefaultProfile $VirtualMachineContext
        if ($RestartedVirtualMachine.Status -ine "Succeeded") {
            Write-Log "Restarting Virtual Machine Output: $($RestartedVirtualMachine | ConvertTo-Json -Depth 100 -Compress)" -LogLevel 'ERROR'
            Write-Log "Failed to restart virtual machine '$($VirtualMachine.Name)' due to error '$($RestartedVirtualMachine.Error)'" -LogLevel 'ERRORSTOP'
        }

        # TODO: Timeout too long or too short?
        $Timeout = New-TimeSpan -Minutes 5
        $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
        while (($VirtualMachineGuestAgentStatus -ne "Ready") -and ($StopWatch.Elapsed -lt $Timeout)) {
            Start-Sleep -Seconds 30
            $AzVMParameters = @{
                DefaultProfile = $VirtualMachineContext
                ResourceId     = $VirtualMachine.Id
                Status         = $true
            }
            $VirtualMachineGuestAgentStatus = (Get-AzVM @AzVMParameters).VMAgent.Statuses.DisplayStatus
            if ($VirtualMachineGuestAgentStatus -ne "Ready") {
                Write-Log "Waiting for virtual machine '$($VirtualMachine.Name)' guest agent to be ready with current status '$($VirtualMachineGuestAgentStatus)'"
            }
        }
        $StopWatch.Stop()

        if ($VirtualMachineGuestAgentStatus -eq "Ready") {
            Write-Log "Virtual machine '$($VirtualMachine.Name)' guest agent is ready"
            return $true
        } else {
            Write-Log "Virtual machine '$($VirtualMachine.Name)' guest agent did not become ready before timeout period with current status '$VirtualMachineGuestAgentStatus'" -LogLevel 'ERRORSTOP'
        }
    }
}
Export-ModuleMember -Function Restart-VirtualMachine

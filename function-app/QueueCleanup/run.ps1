param($InputQueue, $TriggerMetadata)

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$InformationPreference = [System.Management.Automation.ActionPreference]::Continue
$WarningPreference = [System.Management.Automation.ActionPreference]::Continue

try {
    $Settings = Get-Settings
    $env:LogPrefix = $Settings.HostPool.Name
    $env:EntraIdSecurityDeviceGroupName = $Settings.EntraIdSecurityDeviceGroupName

    Write-Log "Starting Geekly cleanup"

    if (-not ($Settings.ChangesAllowed)) {
        Write-Log "Geekly is not allowed to make changes"
        return
    }

    switch ($InputQueue.Type) {
        "Resource" {
            $RemovedResources = $InputQueue.Data | Remove-Resource
            $SuccessfulCleanup = (-not ($RemovedResources.Status.Contains($false)))
        }

        "Session Host" {
            $SessionHostParameters = $InputQueue.Data
            $RemovedSessionHost = Remove-SessionHost @SessionHostParameters
            $SuccessfulCleanup = ($RemovedSessionHost.Status -eq $true)
        }

        default {
            Write-Log "Unrecognized cleanup type $($InputQueue.Type)" -LogLevel 'ERRORSTOP'
        }
    }

    if ($null -ne $InputQueue.Rebuild) {
        if ($SuccessfulCleanup) {
            Write-Log "Queueing virtual machine '$($InputQueue.Rebuild.VirtualMachine.Name)' for creation in resource group '$($InputQueue.Rebuild.DeploymentLocation.ComputeResourceGroup.Name)' and network '$($InputQueue.Rebuild.DeploymentLocation.Subnet.Name)'"
            $OutputQueueCreation = @{
                Name  = "OutputQueueCreation"
                Value = @{
                    DeploymentLocation = $InputQueue.Rebuild.DeploymentLocation
                    VirtualMachineName = $InputQueue.Rebuild.VirtualMachine.Name
                }
            }
            Push-OutputBinding @OutputQueueCreation
        }
    }

    Write-Log "Completed Geekly cleanup"
} catch {
    $ErrorScript = $PSItem.InvocationInfo.ScriptName
    $ErrorScriptLine = "$($PSItem.InvocationInfo.ScriptLineNumber):$($PSItem.InvocationInfo.OffsetInLine)"
    $ErrorMessage = "$($PSItem.Exception.Message) Error Script: $ErrorScript, Error Line: $ErrorScriptLine"
    Write-Log $ErrorMessage -Exception $PSItem.Exception -LogLevel 'ERRORSTOP'
}
param($InputQueue, $TriggerMetadata)

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$InformationPreference = [System.Management.Automation.ActionPreference]::Continue
$WarningPreference = [System.Management.Automation.ActionPreference]::Continue

try {
    $Settings = Get-Settings
    $env:LogPrefix = $Settings.HostPool.Name
    $env:EntraIdSecurityDeviceGroupName = $Settings.EntraIdSecurityDeviceGroupName

    Write-Log "Starting Geekly registration function for virtual machine '$($InputQueue.VirtualMachine.Name)'"

    if (-not ($Settings.ChangesAllowed)) {
        Write-Log "Geekly is not allowed to make changes for virtual machine '$($InputQueue.VirtualMachine.Name)'"
        return
    }

    $SessionHostRegistrationStatusParameters = @{
        HostPool           = $Settings.HostPool
        VirtualMachineName = $InputQueue.VirtualMachine.Name
    }
    $SessionHostRegistrationStatus = Get-SessionHostRegistrationStatus @SessionHostRegistrationStatusParameters -PreRegistrationCheck
    if (-not ($SessionHostRegistrationStatus)) {
        $RegistrationTokenParameters = @{
            HostPoolName      = $Settings.HostPool.Name
            ResourceGroupName = $Settings.HostPool.ResourceGroupName
            SubscriptionId    = $Settings.HostPool.SubscriptionId
        }
        $ExistingHostPoolRegistrationInfo = Get-AzWvdHostPoolRegistrationToken @RegistrationTokenParameters
        if ($null -eq $ExistingHostPoolRegistrationInfo) {
            Write-Log "Existing host pool registration token not found, creating a new token to register virtual machine '$($InputQueue.VirtualMachine.Name)' to host pool as a session host"
            $RegistrationTokenParameters.ExpirationTime = (Get-Date).ToUniversalTime().AddHours(24).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
            $HostPoolRegistrationToken = (New-AzWvdRegistrationInfo @RegistrationTokenParameters).Token
        } elseif ($ExistingHostPoolRegistrationInfo.ExpirationTime -lt (Get-Date).ToUniversalTime().AddHours(1).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')) {
            Write-Log "Existing host pool registration token is expiring within the hour, creating a new token to register virtual machine '$($InputQueue.VirtualMachine.Name)' to host pool as a session host"
            $RegistrationTokenParameters.ExpirationTime = (Get-Date).ToUniversalTime().AddHours(24).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
            $HostPoolRegistrationToken = (New-AzWvdRegistrationInfo @RegistrationTokenParameters).Token
        } else {
            Write-Log "Existing host pool registration token will be used to register virtual machine '$($InputQueue.VirtualMachine.Name)' to host pool as a session host"
            $HostPoolRegistrationToken = $ExistingHostPoolRegistrationInfo.Token
        }

        $WVDrdagentBlobName = "Microsoft.RDInfra.RDAgent.Installer-x64.msi"
        $WVDrdagentbootloaderBlobName = "Microsoft.RDInfra.RDAgentBootLoader.Installer-x64.msi"
        $StorageBlobSasUriParameters = @{
            ContainerName  = "rdagent-installers"
            StorageAccount = $Settings.AssetStorageAccount
        }
        $StorageBlobSasUri = @($WVDrdagentBlobName, $WVDrdagentbootloaderBlobName) | Get-StorageBlobSasUri @StorageBlobSasUriParameters

        $RunCommandParameters = @(
            @{
                Name  = "HostPoolName"
                Value = $Settings.HostPool.Name
            }
        )
        if ($TriggerMetadata.DequeueCount -gt 1) {
            $RunCommandParameters += @{
                Name  = "Reregister"
                Value = "True"
            }
        }
        $RunCommandProtectedParameters = @(
            @{
                Name  = "RegistrationToken"
                Value = $HostPoolRegistrationToken
            }
            @{
                Name  = "RemoteDesktopAgentUri"
                Value = $StorageBlobSasUri.where({ $PSItem.Name -eq $WVDrdagentBlobName }).Uri
            }
            @{
                Name  = "RemoteDesktopAgentBootLoaderUri"
                Value = $StorageBlobSasUri.where({ $PSItem.Name -eq $WVDrdagentbootloaderBlobName }).Uri
            }
        )

        Write-Log "Registering virtual machine '$($InputQueue.VirtualMachine.Name)' to host pool as a session host"
        $VirtualMachineRunCommandParameters = @{
            Location                     = $InputQueue.DeploymentLocation.Subnet.Location
            Name                         = "WvdJoinSessionHost"
            Parameter                    = $RunCommandParameters
            ProtectedParameter           = $RunCommandProtectedParameters
            ResourceGroupName            = $InputQueue.DeploymentLocation.ComputeResourceGroup.Name
            RunCommandLogsStorageAccount = $Settings.AssetStorageAccount
            ScriptPath                   = "./Scripts/Invoke-HostPoolRegistration.ps1"
            SubscriptionId               = $InputQueue.DeploymentLocation.ComputeResourceGroup.SubscriptionId
            VirtualMachineName           = $InputQueue.VirtualMachine.Name
        }
        $VirtualMachineRunCommand = Set-VirtualMachineRunCommand @VirtualMachineRunCommandParameters

        # TODO: registration fails sometimes but with built-in function retries the
        # registration usually works anyway

        # TODO: Refactor this script to return JSON data so
        # we can check status from returned output as well
        # this would allow us to handle more complex errors
        # rather then it just failing and retrying

        if ($VirtualMachineRunCommand.ProvisioningState -ine "Succeeded") {
            Write-Log "Registration Run Command Output: $($VirtualMachineRunCommand | ConvertTo-Json -Depth 100 -Compress)" -LogLevel 'ERROR'
            Write-Log "Failed to register virtual machine '$($InputQueue.VirtualMachine.Name)' to host pool" -LogLevel 'ERRORSTOP'
        }

        Get-SessionHostRegistrationStatus @SessionHostRegistrationStatusParameters | Out-Null
    }

    Write-Log "Completed Geekly registration function for virtual machine '$($InputQueue.VirtualMachine.Name)'"
} catch {
    $ErrorScript = $PSItem.InvocationInfo.ScriptName
    $ErrorScriptLine = "$($PSItem.InvocationInfo.ScriptLineNumber):$($PSItem.InvocationInfo.OffsetInLine)"
    $ErrorMessage = "$($PSItem.Exception.Message) Error Script: $ErrorScript, Error Line: $ErrorScriptLine"
    Write-Log $ErrorMessage -Exception $PSItem.Exception -LogLevel 'ERRORSTOP'
}
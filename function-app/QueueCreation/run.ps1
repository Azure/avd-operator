param($InputQueue, $TriggerMetadata)

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$InformationPreference = [System.Management.Automation.ActionPreference]::Continue
$WarningPreference = [System.Management.Automation.ActionPreference]::Continue

try {
    $Settings = Get-Settings
    $env:LogPrefix = $Settings.HostPool.Name
    $env:EntraIdSecurityDeviceGroupName = $Settings.EntraIdSecurityDeviceGroupName
    $ComputeContext = Get-Context -SubscriptionId $InputQueue.DeploymentLocation.ComputeResourceGroup.SubscriptionId

    Write-Log "Starting Geekly creation function for virtual machine '$($InputQueue.VirtualMachineName)'"

    if (-not ($Settings.ChangesAllowed)) {
        Write-Log "Geekly is not allowed to make changes"
        return
    }

    $AzureTags = @{
        deployment_source = "Geekly"
        deployment_tool   = "PowerShell"
        environment       = $Settings.Environment
        owner             = "Temp"
        project           = "Geekly"
    }

    $VirtualMachineParameters = @{
        AuthKeyVault                      = $Settings.AuthKeyVault
        DiskEncryptionSetId               = $InputQueue.DeploymentLocation.DiskEncryptionSet.Id
        Environment                       = $Settings.Environment
        FslogixStorageAccountName         = $InputQueue.DeploymentLocation.FSLogixStorageAccountName
        GalleryImageDefinitionId          = $Settings.GalleryImageDefinition.Id
        GalleryImageDefinitionVersionName = $Settings.GalleryImageDefinitionVersionName
        Location                          = $InputQueue.DeploymentLocation.Subnet.Location
        Name                              = $InputQueue.VirtualMachineName
        ResourceGroup                     = $InputQueue.DeploymentLocation.ComputeResourceGroup
        SkuSize                           = $Settings.VirtualMachineSKUSize
        Subnet                            = $InputQueue.DeploymentLocation.Subnet
        Tags                              = $AzureTags
    }
    $VirtualMachine = New-VirtualMachine @VirtualMachineParameters

    $VirtualMachineRestarted = $false
    $VirtualMachineReadyForPostProcess = $false
    # TODO: Timeout too long or too short?
    $TimeoutBeforeRestart = New-TimeSpan -Minutes 5
    $TimeoutAfterRestart = New-TimeSpan -Minutes 5
    $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        $AzVMParameters = @{
            DefaultProfile = $ComputeContext
            ResourceId     = $VirtualMachine.Id
            Status         = $true
        }
        $VirtualMachineStatus = Get-AzVM @AzVMParameters
        $VirtualMachineGuestAgentStatus = $VirtualMachineStatus.VMAgent.Statuses.DisplayStatus
        $VirtualMachinePowerState = $VirtualMachineStatus.Statuses.where({ $PSItem.Code -ilike "PowerState*" }).DisplayStatus
        Write-Log "Found virtual machine '$($VirtualMachine.Name)' with power state '${VirtualMachinePowerState}' and guest agent status '${VirtualMachineGuestAgentStatus}'"
        if ($VirtualMachinePowerState -ieq "VM deallocated") {
            $VirtualMachine | Start-AzVM | Out-Null
        }

        if (
            (($VirtualMachinePowerState -eq "VM running") -and ($VirtualMachineGuestAgentStatus -eq "Ready")) -or
            ($StopWatch.Elapsed -ge $TimeoutAfterRestart)
        ) {
            break
        } else {
            Write-Log "Waiting 60 seconds for virtual machine '$($VirtualMachine.Name)' to stablize"
            Start-Sleep -Seconds 60
        }

        # TODO: Expand logic below to determine how and when to send VMs to registration queue
        if ((-not ($VirtualMachineRestarted)) -and ($StopWatch.Elapsed -ge $TimeoutBeforeRestart)) {
            Write-Log "Virtual machine '$($VirtualMachine.Name)' needs to be restarted because guest agent is not ready"
            $VirtualMachineRestarted = $VirtualMachine | Restart-VirtualMachine

            Write-Log "Waiting 60 seconds for virtual machine '$($VirtualMachine.Name)' to stablize after restart"
            Start-Sleep -Seconds 60
            $StopWatch.Restart()
        }
    }
    $StopWatch.Stop()

    if (
        ($VirtualMachinePowerState -eq "VM running") -and
        ($VirtualMachineGuestAgentStatus -eq "Ready")
    ) {
        $VirtualMachineReadyForPostProcess = $true
    } else {
        # TODO: What should we do if the virtual machine
        # doesn't stablize after the timeout and 1 restart?
        # Queue for cleanup?
        Write-Log "Virtual machine '$($VirtualMachine.Name)' power status and guest agent status did not stablize after restart"
        $VirtualMachineRelatedResources = $VirtualMachine | Get-RelatedResource
        Write-Log "Queueing $($VirtualMachineRelatedResources.Count) resource(s) for cleanup related to virtual machine '$($VirtualMachine.Name)' that failed to stablize after restart"
        $OutputQueueCleanup = @{
            Name  = "OutputQueueCleanup"
            Value = @{
                Data = $VirtualMachineRelatedResources
                Type = "Resource"
            }
        }
        Push-OutputBinding @OutputQueueCleanup
        return
    }

    if ($VirtualMachineReadyForPostProcess) {
        $VirtualMachinePostProcessParameters = @{
            AssetStorageAccount = $Settings.AssetStorageAccount
            DeploymentLocation  = $InputQueue.DeploymentLocation
            VirtualMachine      = $VirtualMachine
        }
        Set-VirtualMachinePostProcess @VirtualMachinePostProcessParameters

        if ($Settings.EntraIdSecurityDeviceGroupJoinEnabled) {
            Write-Log "Adding virtual machine '$($VirtualMachine.Name)' to Entra ID security device group '$($Settings.EntraIdSecurityDeviceGroupName)'"
            $VirtualMachine.Name | Set-EntraIdDeviceGroupMembership -Action "Add" -DeviceGroupName $Settings.EntraIdSecurityDeviceGroupName

            Write-Log "Waiting 60 seconds for Entra ID security device group membership to propagate"
            Start-Sleep -Seconds 60

            Write-Log "Virtual machine '$($VirtualMachine.Name)' needs to be restarted after adding it to Entra ID security device group '$($Settings.EntraIdSecurityDeviceGroupName)'"
            $RestartedVirtualMachine = $VirtualMachine | Restart-VirtualMachine
            if ($RestartedVirtualMachine) {
                Write-Log "Restarted virtual machine '$($VirtualMachine.Name)' after adding it to Entra ID security device group '$($Settings.EntraIdSecurityDeviceGroupName)'"
            }
        }

        Write-Log "Queueing virtual machine '$($VirtualMachine.Name)' for registration"
        $OutputQueueRegistration = @{
            Name  = "OutputQueueRegistration"
            Value = @{
                DeploymentLocation = $InputQueue.DeploymentLocation
                VirtualMachine     = $VirtualMachine
            }
        }
        Push-OutputBinding @OutputQueueRegistration
    }

    Write-Log "Completed Geekly creation function for virtual machine '$($InputQueue.VirtualMachineName)'"
} catch {
    if (
        ($null -ne $VirtualMachine) -and
        ($TriggerMetadata.DequeueCount -eq 5)
    ) {
        $ErrorScript = $PSItem.InvocationInfo.ScriptName
        $ErrorScriptLine = "$($PSItem.InvocationInfo.ScriptLineNumber):$($PSItem.InvocationInfo.OffsetInLine)"
        $ErrorMessage = "$($PSItem.Exception.Message) Error Script: $ErrorScript, Error Line: $ErrorScriptLine"
        Write-Log $ErrorMessage -Exception $PSItem.Exception -LogLevel 'ERROR'

        # Build virtual machine ID in case we haven't had a successful
        # creation yet and wouldn't have the '$VirtualMachine' variable yet

        # TODO: Is this the best way to handle this? May be better to build
        # atomic cleanup function that encompasses this

        $VirtualMachineId = "/subscriptions/$($InputQueue.DeploymentLocation.ComputeResourceGroup.SubscriptionId)/resourceGroups/$($InputQueue.DeploymentLocation.ComputeResourceGroup.Name)/providers/Microsoft.Compute/virtualMachines/$($InputQueue.VirtualMachineName)"
        Write-Log "Getting related resources for virtual machine with ID '${VirtualMachineId}'"
        $VirtualMachineRelatedResources = $VirtualMachineId | Get-ResourceInformation | Get-RelatedResource
        Write-Log "Queueing $($VirtualMachineRelatedResources.Count) resource(s) for cleanup related to virtual machine '$($VirtualMachine.Name)' that failed to be created"
        if ($VirtualMachineRelatedResources.Count -gt 0) {
            $OutputQueueCleanup = @{
                Name  = "OutputQueueCleanup"
                Value = @{
                    Data = $VirtualMachineRelatedResources
                    Type = "Resource"
                }
            }
            Push-OutputBinding @OutputQueueCleanup
        }
    } else {
        $ErrorScript = $PSItem.InvocationInfo.ScriptName
        $ErrorScriptLine = "$($PSItem.InvocationInfo.ScriptLineNumber):$($PSItem.InvocationInfo.OffsetInLine)"
        $ErrorMessage = "$($PSItem.Exception.Message) Error Script: $ErrorScript, Error Line: $ErrorScriptLine"
        Write-Log $ErrorMessage -Exception $PSItem.Exception -LogLevel 'ERRORSTOP'
    }
}

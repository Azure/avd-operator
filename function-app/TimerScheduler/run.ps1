param($InputTimer, $TriggerMetadata)

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$InformationPreference = [System.Management.Automation.ActionPreference]::Continue
$WarningPreference = [System.Management.Automation.ActionPreference]::Continue

try {
    $Settings = Get-Settings
    $env:LogPrefix = $Settings.HostPool.Name

    Write-Log "Starting Geekly session host scheduler"

    Write-Log "Checking for session host deployment status"
    $ExistingVirtualMachinesQueries = foreach ($ComputeResourceGroup in $Settings.ComputeResourceGroup) {
        @(
            "resources"
            "| where subscriptionId =~ '$($ComputeResourceGroup.LabeledValue.SubscriptionId)'"
            "| where resourceGroup =~ '$($ComputeResourceGroup.LabeledValue.Name)'"
            "| where ['type'] =~ 'Microsoft.Compute/virtualMachines'"
            "| project ['id']"
        ) | Out-String
    }
    $ExistingVirtualMachinesQueriesResults = $ExistingVirtualMachinesQueries | Search-AzGraphPaging
    [Object[]] $ExistingVirtualMachines = if ($ExistingVirtualMachinesQueriesResults.Count -gt 0) {
        $ExistingVirtualMachinesQueriesResults.id | Get-ResourceInformation | Sort-Object -Property Name
    }

    $AzWvdSessionHostParameters = @{
        HostPoolName      = $Settings.HostPool.Name
        ResourceGroupName = $Settings.HostPool.ResourceGroupName
        SubscriptionId    = $Settings.HostPool.SubscriptionId
    }
    $SessionHosts = Get-AzWvdSessionHost @AzWvdSessionHostParameters

    [PSCustomObject[]] $StaleSessionHosts = if ($SessionHosts.Count -gt 0) {
        foreach ($SessionHost in $SessionHosts) {
            $VirtualMachine = $SessionHost.ResourceId | Get-ResourceInformation
            $VirtualMachineContext = Get-Context -SubscriptionId $VirtualMachine.SubscriptionId
            $AzResourceParameters = @{
                DefaultProfile = $VirtualMachineContext
                ResourceId     = $VirtualMachine.Id
                ErrorAction    = "SilentlyContinue"
            }
            $ExistingSessionHost = Get-AzResource @AzResourceParameters
            if ($null -eq $ExistingSessionHost) {
                [PSCustomObject]@{
                    SessionHost    = $SessionHost.Id | Get-ResourceInformation
                    VirtualMachine = $SessionHost.ResourceId | Get-ResourceInformation
                }
            }
        }
    }
    [Int] $SessionHostsWithoutStaleCount = $SessionHosts.Count - $StaleSessionHosts.Count

    [Object[]] $UnregisteredExistingVirtualMachines = if ($ExistingVirtualMachines.Count -gt 0) {
        if ($SessionHosts.Count -gt 0) {
            $ExistingVirtualMachines.where({ $SessionHosts.ResourceId -inotcontains $PSItem.Id })
        } else {
            $ExistingVirtualMachines
        }
    }

    switch ($Settings.ScalingPlanMode) {
        "Cleanup" { $TargetSessionHostCount = 0 }
        default { [Int] $TargetSessionHostCount = $Settings.TargetSessionHostCount }
    }

    $SessionHostDeploymentStatusMessage = @(
        "Target: ${TargetSessionHostCount}"
        "Created: $($ExistingVirtualMachines.Count)"
        "Registered: $($SessionHostsWithoutStaleCount)"
        "Unregistered: $($UnregisteredExistingVirtualMachines.Count)"
        "Stale: $($StaleSessionHosts.Count)"
    )

    Write-Log "Replacement method is set to '$($Settings.ReplacementMethod)'"
    switch ($Settings.ReplacementMethod) {
        "Tags" {
            [Object[]] $ReplacementMethodTagsRebuildVirtualMachines = $ExistingVirtualMachines.where({ $null -ne $PSItem.Tags.rebuild })
            $SessionHostDeploymentStatusMessage += "Tags:Rebuild: $($ReplacementMethodTagsRebuildVirtualMachines.Count)"
        }

        default {
            Write-Log "Unrecognized replacement method '$($Settings.ReplacementMethod)'" -LogLevel 'ERRORSTOP'
        }
    }

    Write-Log "$($SessionHostDeploymentStatusMessage -join ', ')"

    if (-not ($Settings.ChangesAllowed)) {
        Write-Log "Geekly is not allowed to make changes"
        return
    }

    Write-Log "Enforcing host pool scaling plan mode"
    Set-HostPoolScalingPlanMode -Settings $Settings

    if ($StaleSessionHosts.Count -gt 0) {
        foreach ($StaleSessionHost in $StaleSessionHosts) {
            # Double check for any related resources that may need to be cleanedup
            # If a session host is considered stale it just means the virtual machine
            # resource itself is missing but disks or network interfaces could still
            # exist that need to be cleaned up
            $SessionHostRelatedResources = @($StaleSessionHost.SessionHost, $StaleSessionHost.VirtualMachine) | Get-RelatedResource
            Write-Log "Found $($SessionHostRelatedResources.Count) resource(s) related to session host '$($StaleSessionHost.SessionHost.Name)'"
            if ($SessionHostRelatedResources.Count -gt 0) {
                Write-Log "Queueing $($SessionHostRelatedResources.Count) resource(s) for cleanup related to session host '$($StaleSessionHost.SessionHost.Name)' that are no longer needed"
                $OutputQueueCleanup = @{
                    Name  = "OutputQueueCleanup"
                    Value = @{
                        Data = $SessionHostRelatedResources
                        Type = "Resource"
                    }
                }
                Push-OutputBinding @OutputQueueCleanup
            }
        }
    }

    if ($SessionHostsWithoutStaleCount -lt $TargetSessionHostCount) {
        # Creation

        Write-Log "Current session host count ${SessionHostsWithoutStaleCount} is less than target count ${TargetSessionHostCount}"
        [Int] $MissingSessionHostCount = $TargetSessionHostCount - $SessionHostsWithoutStaleCount
        Write-Log "Need $MissingSessionHostCount more session host(s) to match target count ${TargetSessionHostCount}"

        $DeploymentLocationParameters = @{
            MissingSessionHostCount = $MissingSessionHostCount
            Settings                = $Settings
        }

        if ($SessionHosts.Count -gt 0) {
            $DeploymentLocationParameters.ExistingSessionHostNames = [System.Collections.Generic.List[String]]::new()

            # Use regular session host count instead of without stale count
            # to ensure we don't attempt to deploy a new session host
            # using a stale sesson host name before stale session hosts are cleaned up
            $SessionHostNames = ($SessionHosts.Id | Get-ResourceInformation).Name
            foreach ($SessionHostName in $SessionHostNames) {
                if (-not ($DeploymentLocationParameters.ExistingSessionHostNames.Contains($SessionHostName))) {
                    $DeploymentLocationParameters.ExistingSessionHostNames.Add($SessionHostName)
                }
            }
        }

        if ($DeployedVirtualMachines.Count -gt 0) {
            # Attempt to find previously Entra ID joined virtual machines to build
            # an exclusion list when generating new session host names which includes
            # stale Entra ID device name cleanup
            $EntraIdJoinedVirtualMachines = $DeployedVirtualMachines.where({ (-not ([String]::IsNullOrWhiteSpace($PSItem.Tags.EntraIdDeviceId))) })
            if ($EntraIdJoinedVirtualMachines.Count -gt 0) {
                $DeploymentLocationParameters.EntraIdJoinedVirtualMachineNames = [System.Collections.Generic.List[String]]::new()

                foreach ($VirtualMachine in $EntraIdJoinedVirtualMachines) {
                    if (-not ($DeploymentLocationParameters.EntraIdJoinedVirtualMachineNames.Contains($VirtualMachine.Name))) {
                        $DeploymentLocationParameters.EntraIdJoinedVirtualMachineNames.Add($VirtualMachine.Name)
                    }
                }
            }
        }

        $DeploymentLocations = Get-DeploymentLocation @DeploymentLocationParameters
        foreach ($DeploymentLocation in $DeploymentLocations) {
            Write-Log "Queueing $($DeploymentLocation.SessionHostNames.Count) virtual machine(s) for creation in resource group '$($DeploymentLocation.ComputeResourceGroup.Name)' and network '$($DeploymentLocation.Subnet.Name)'"

            foreach ($SessionHostName in $DeploymentLocation.SessionHostNames) {
                Write-Log "Queueing virtual machine '${SessionHostName}' for creation in resource group '$($DeploymentLocation.ComputeResourceGroup.Name)' and network '$($DeploymentLocation.Subnet.Name)'"
                $OutputQueueCreation = @{
                    Name  = "OutputQueueCreation"
                    Value = @{
                        DeploymentLocation = $DeploymentLocation
                        VirtualMachineName = $SessionHostName
                    }
                }
                Push-OutputBinding @OutputQueueCreation
            }
        }
    } elseif ($ReplacementMethodTagsRebuildVirtualMachines.Count -gt 0) {
        # Rebuild

        # TODO: Rebuild before cleanup means if mass VMs
        # need cleanup they will be left alone, increasing costs,
        # until rebuild is done

        Write-Log "Found $($ReplacementMethodTagsRebuildVirtualMachines.Count) virtual machine(s) that were tagged for rebuild"
        foreach ($VirtualMachine in $ReplacementMethodTagsRebuildVirtualMachines) {
            $SessionHost = $SessionHosts.where({ $PSItem.ResourceId -ieq $VirtualMachine.Id })
            if ($null -eq $SessionHost) {
                $VirtualMachineRelatedResources = $VirtualMachine | Get-RelatedResource
                Write-Log "Queueing $($VirtualMachineRelatedResources.Count) resource(s) for cleanup related to virtual machine '$($VirtualMachine.Name)' because they were tagged for rebuild"
                $OutputQueueCleanup = @{
                    Name  = "OutputQueueCleanup"
                    Value = @{
                        Data    = $VirtualMachineRelatedResources
                        Rebuild = @{
                            DeploymentLocation = Get-DeploymentLocation -Settings $Settings -VirtualMachineId $VirtualMachine.Id
                            VirtualMachine     = $VirtualMachine
                        }
                        Type    = "Resource"
                    }
                }
                Push-OutputBinding @OutputQueueCleanup
            } else {
                # TODO: Add check for running VM status here?
                # Or wait until it gets to the queue?
                Write-Log "Queueing session host '$($VirtualMachine.Name)' for cleanup because it was tagged for rebuild"
                $OutputQueueCleanup = @{
                    Name  = "OutputQueueCleanup"
                    Value = @{
                        Data    = @{
                            SessionHost    = $SessionHost.Id | Get-ResourceInformation
                            VirtualMachine = $VirtualMachine
                        }
                        Rebuild = @{
                            DeploymentLocation = Get-DeploymentLocation -Settings $Settings -VirtualMachineId $VirtualMachine.Id
                            VirtualMachine     = $VirtualMachine
                        }
                        Type    = "Session Host"
                    }
                }
                Push-OutputBinding @OutputQueueCleanup
            }
        }
    } elseif ($SessionHostsWithoutStaleCount -gt $TargetSessionHostCount) {
        # Cleanup

        Write-Log "Current session host count ${SessionHostsWithoutStaleCount} is greater than target count ${TargetSessionHostCount}"
        [Int] $SessionHostsToRemoveCount = $SessionHostsWithoutStaleCount - $TargetSessionHostCount
        Write-Log "Found ${SessionHostsToRemoveCount} more session host(s) than target count ${TargetSessionHostCount}"

        Write-Log "Checking host pool for ${SessionHostsToRemoveCount} shutdown session host(s)"
        $ShutdownSessionHostParameters = @{
            HostPool                  = $Settings.HostPool
            SessionHostsToRemoveCount = $SessionHostsToRemoveCount
        }
        Remove-ShutdownSessionHost @ShutdownSessionHostParameters
    } elseif ($UnregisteredExistingVirtualMachines.Count -gt 0) {
        Write-Log "Found $($UnregisteredExistingVirtualMachines.Count) unregistered virtual machine(s) that are deployed but no longer needed"

        foreach ($VirtualMachine in $UnregisteredExistingVirtualMachines) {
            $VirtualMachineRelatedResources = $VirtualMachine | Get-RelatedResource
            Write-Log "Queueing $($VirtualMachineRelatedResources.Count) resource(s) for cleanup related to unregistered virtual machine '$($VirtualMachine.Name)' that are no longer needed"
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
        # No action
        Write-Log "Current session host count ${SessionHostsWithoutStaleCount} matches target count ${TargetSessionHostCount}"
    }

    Write-Log "Completed Geekly session host scheduler"
} catch {
    $ErrorScript = $PSItem.InvocationInfo.ScriptName
    $ErrorScriptLine = "$($PSItem.InvocationInfo.ScriptLineNumber):$($PSItem.InvocationInfo.OffsetInLine)"
    $ErrorMessage = "$($PSItem.Exception.Message) Error Script: $ErrorScript, Error Line: $ErrorScriptLine"
    Write-Log $ErrorMessage -Exception $PSItem.Exception -LogLevel 'ERRORSTOP'
}
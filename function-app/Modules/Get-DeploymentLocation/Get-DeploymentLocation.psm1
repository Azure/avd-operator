function Invoke-SubnetRegionalVirtualCPUQuotaCheck {
    [OutputType([System.Collections.Generic.List[Hashtable]])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Int] $DesiredCount,

        [Parameter(Mandatory)]
        [String] $VirtualMachineSKUSize,

        [Parameter(Mandatory, ValueFromPipeline)]
        [Object] $Subnet
    )

    begin {
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

        $SubnetRegionVCPUQuota = [System.Collections.Generic.List[Hashtable]]::new()
    }

    process {
        Write-Log "Checking regional vCPU quota for subnet '$($Subnet.Name)'"
        $SubnetContext = Get-Context -SubscriptionId $Subnet.SubscriptionId

        $RegionalComputeSKUs = Get-AzComputeResourceSku -Location $Subnet.Location -DefaultProfile $SubnetContext
        $VirtualMachineSKU = $RegionalComputeSKUs.where({
                ($PSItem.ResourceType -eq "virtualMachines") -and
                ($PSItem.Name -eq $Settings.VirtualMachineSKUSize)
            }
        )
        $VirtualMachineSKUvCPUCount = [Int] $VirtualMachineSKU.Capabilities.where({ $PSItem.Name -eq "vCPUs" }).Value
        $RequiredVirtualMachinevCPUCount = $VirtualMachineSKUvCPUCount * $DesiredCount
        $RegionalVirtualMachineUsage = Get-AzVMUsage -Location $Subnet.Location -DefaultProfile $SubnetContext
        $VirtualMachineSKUvCPUUsage = $RegionalVirtualMachineUsage.where({ $PSItem.Name.Value -eq $VirtualMachineSKU.Family })
        [Int] $AvailableVirtualMachineSKUvCPUCount = $VirtualMachineSKUvCPUUsage.Limit - $VirtualMachineSKUvCPUUsage.CurrentValue
        $DeployableVirtualMachineCount = [Math]::Floor($AvailableVirtualMachineSKUvCPUCount / $VirtualMachineSKUvCPUCount)
        Write-Log "Regional vCPU quota for subnet '$($Subnet.Name)' - SKU: $($Settings.VirtualMachineSKUSize), Required: ${RequiredVirtualMachinevCPUCount}, Available: ${AvailableVirtualMachineSKUvCPUCount}, Max: $($VirtualMachineSKUvCPUUsage.Limit), Used: $($VirtualMachineSKUvCPUUsage.CurrentValue), Deployable: ${DeployableVirtualMachineCount}"

        $SubnetRegionVCPUQuota.Add(@{
                DeployableCount = $DeployableVirtualMachineCount
                Subnet          = $Subnet
            }
        )
    }

    end {
        return $SubnetRegionVCPUQuota
    }
}

function Invoke-SubnetIPAddressAvailabilityCheck {
    [OutputType([System.Collections.Generic.List[Hashtable]])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Int] $DesiredCount,

        [Parameter(Mandatory, ValueFromPipeline)]
        [Object] $Subnet
    )

    begin {
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

        $AzureReservedHostIPAddressCount = 5
        $SubnetIPAddressAvailability = [System.Collections.Generic.List[Hashtable]]::new()
    }

    process {
        Write-Log "Checking IP address availability for subnet '$($Subnet.Name)'"
        $SubnetContext = Get-Context -SubscriptionId $Subnet.SubscriptionId

        $SubnetConfig = Get-AzVirtualNetworkSubnetConfig -ResourceId $Subnet.Id -DefaultProfile $SubnetContext
        $SubnetCIDRPrefix = [Int] $SubnetConfig.AddressPrefix.Split("/")[1]
        [Int] $SubnetHostIPAddressCount = [Math]::Pow(2, (32 - $SubnetCIDRPrefix))
        [Int] $UsableSubnetHostIPAddressCount = $SubnetHostIPAddressCount - $AzureReservedHostIPAddressCount
        [Int] $AvailableSubnetHostIPAddressCount = $UsableSubnetHostIPAddressCount - $SubnetConfig.IpConfigurations.Count
        Write-Log "IP address availability for subnet '$($Subnet.Name)' - Available: ${AvailableSubnetHostIPAddressCount}, Max: ${UsableSubnetHostIPAddressCount}, Used: $($SubnetConfig.IpConfigurations.Count)"

        $SubnetIPAddressAvailability.Add(@{
                DeployableCount = $AvailableSubnetHostIPAddressCount
                Subnet          = $Subnet
            }
        )
    }

    end {
        return $SubnetIPAddressAvailability
    }
}

function Invoke-SubnetDeploymentLocationCapacityCheck {
    [OutputType([System.Collections.Generic.List[Hashtable]])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Int] $DesiredCount,

        [Parameter(Mandatory)]
        [String] $VirtualMachineSKUSize,

        [Parameter(Mandatory, ValueFromPipeline)]
        [Object] $Subnet
    )

    begin {
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

        $SubnetDeploymentLocationCapacity = [System.Collections.Generic.List[Hashtable]]::new()
    }

    process {
        $RegionalVirtualCPUQuota = $Subnet | Invoke-SubnetRegionalVirtualCPUQuotaCheck -DesiredCount $DesiredCount -VirtualMachineSKUSize $VirtualMachineSKUSize
        $IPAddressAvailability = $Subnet | Invoke-SubnetIPAddressAvailabilityCheck -DesiredCount $DesiredCount
        if (($RegionalVirtualCPUQuota.DeployableCount -gt 0) -and ($IPAddressAvailability.DeployableCount -gt 0)) {
            # Find least common denominator for deployable count
            $DeployableCount = if ($RegionalVirtualCPUQuota.DeployableCount -ne $IPAddressAvailability.DeployableCount) {
                if ($RegionalVirtualCPUQuota.DeployableCount -lt $IPAddressAvailability.DeployableCount) {
                    $RegionalVirtualCPUQuota.DeployableCount
                } else {
                    $IPAddressAvailability.DeployableCount
                }
            } else {
                $RegionalVirtualCPUQuota.DeployableCount
            }

            $SubnetDeploymentLocation = @{
                DeployableCount = $DeployableCount
                Subnet          = $Subnet
            }
            if (-not ($SubnetDeploymentLocationCapacity.Contains($SubnetDeploymentLocation))) {
                $SubnetDeploymentLocationCapacity.Add($SubnetDeploymentLocation)
            }
        }
    }

    end {
        Write-Log "Found capacity to deploy ${DesiredCount} session hosts across $($SubnetDeploymentLocationCapacity.Count) subnets"
        if ($SubnetDeploymentLocationCapacity.Count -eq 0) {
            Write-Log "Failed to find subnets with capacity to deploy any session hosts" -LogLevel 'ERRORSTOP'
        } else {
            return $SubnetDeploymentLocationCapacity
        }
    }
}

function Get-SubnetDeploymentLocationSetting {
    [OutputType()]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Object[]] $Settings,

        [Parameter(Mandatory, ValueFromPipeline)]
        [Object] $DeploymentLocation
    )

    begin {
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

        $LocationSettingKeys = @(
            "ComputeResourceGroup"
            "DiskEncryptionSet"
            "FSLogixStorageAccountName"
            "SessionHostNamePrefix"
        )
    }

    process {
        # This function does not return new data but instead edits the value from pipeline

        Write-Log "Getting deployment location settings for subnet '$($DeploymentLocation.Subnet.Name)'"
        foreach ($LocationSettingKey in $LocationSettingKeys) {
            $LocationSettingKeyValue = $Settings.$LocationSettingKey.where({ $PSItem.Label -eq $DeploymentLocation.Subnet.Location }).LabeledValue
            if ($null -eq $LocationSettingKeyValue) {
                Write-Log "Failed to find value for location setting '${LocationSettingKey}', value is null" -LogLevel 'ERRORSTOP'
            }

            $DeploymentLocation.$LocationSettingKey = $LocationSettingKeyValue
        }
    }

    end {}
}

function Get-AvailableSessionHostName {
    [OutputType()]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Object] $DeploymentLocation,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]] $ExistingSessionHostNames,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String[]] $EntraIdJoinedVirtualMachineNames,

        [Parameter()]
        [Int] $IndexStart = 1,

        [Parameter()]
        [Int] $IndexStop = 999,

        [Parameter()]
        [Int] $IndexPadding = 3
    )

    begin {
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    }

    process {
        # This function does not return new data but instead edits the value from pipeline

        $AvailableSessionHostNames = [System.Collections.Generic.List[String]]::new()

        Write-Log "Generating new session host names for subnet '$($DeploymentLocation.Subnet.Name)' using prefix '$($DeploymentLocation.SessionHostNamePrefix)'"
        for ($i = $IndexStart; $i -le $IndexStop; $i++) {
            $Suffix = "{0:d$IndexPadding}" -f $i
            $NewSessionHostName = "$($DeploymentLocation.SessionHostNamePrefix)${Suffix}"

            $AddNewSessionHostName = $false
            if (
                ($PSBoundParameters.ContainsKey("ExistingSessionHostNames")) -and
                ($ExistingSessionHostNames.Count -gt 0)
            ) {
                if ($ExistingSessionHostNames -inotcontains $NewSessionHostName) {
                    $AddNewSessionHostName = $true
                }
            } else {
                $AddNewSessionHostName = $true
            }

            if ($AddNewSessionHostName) {
                if (
                    ($PSBoundParameters.ContainsKey("EntraIdJoinedVirtualMachineNames")) -and
                    ($EntraIdJoinedVirtualMachineNames.Count -gt 0) -and
                    ($EntraIdJoinedVirtualMachineNames -icontains $NewSessionHostName)
                ) {
                    Write-Log "Newly generated session host name '${NewSessionHostName}' is an existing joined Entra ID device name, skipping cleanup"
                } else {
                    try {
                        Write-Log "Checking if newly generated session host name '${NewSessionHostName}' requires cleanup within Entra ID and Intune"
                        $NewSessionHostName | Remove-EntraIdIntuneDevice -DeviceCleanupPermissionErrorAction "ERRORSTOP"
                    } catch {
                        Write-Log "Failed Entra ID and Intune cleanup of session host name '${NewSessionHostName}', generated name will not be added to list for deployment, due to error '$($PSItem.Exception.Message)'" -LogLevel 'ERROR'
                    }
                }

                Write-Log "Adding newly generated session host name '${NewSessionHostName}' to list for deployment"
                $AvailableSessionHostNames.Add($NewSessionHostName)
            }

            if ($AvailableSessionHostNames.Count -eq $DeploymentLocation.SuggestedDeploymentCount) {
                break
            }
        }

        if ($AvailableSessionHostNames.Count -lt $DeploymentLocation.SuggestedDeploymentCount) {
            Write-Log "Expected $($DeploymentLocation.SuggestedDeploymentCount) available session host names but only got $($AvailableSessionHostNames.Count)" -LogLevel 'WARN'
        }

        Write-Log "Available Session Host Names to Be Used for Deployment: $($AvailableSessionHostNames -join ', ')"
        $DeploymentLocation.SessionHostNames = $AvailableSessionHostNames
    }

    end {}
}

function Get-ResourceGroupFromId {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [String] $ResourceId
    )

    begin {
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

        $ResourceGroups = [System.Collections.Generic.List[Object]]::new()
    }

    process {
        if ($ResourceId -ilike "*/resourceGroups/*") {
            $ResourceGroupIdSections = $ResourceId.Split('/resourceGroups/')
            $ResourceGroupSubscriptionId = $ResourceGroupIdSections[0]
            $ResourceGroupName = $ResourceGroupIdSections[1].Split('/')[0]
            $ResourceGroup = "${ResourceGroupSubscriptionId}/resourceGroups/${ResourceGroupName}" | Get-ResourceInformation
            $ResourceGroups.Add($ResourceGroup)
        }
    }

    end {
        return $ResourceGroups
    }
}

function Get-DeploymentLocation {
    [CmdletBinding(DefaultParameterSetName = "New")]
    [OutputType([System.Collections.Generic.List[Hashtable]])]
    param(
        [Parameter(Mandatory, ParameterSetName = "New")]
        [Int] $MissingSessionHostCount,

        [Parameter(Mandatory, ParameterSetName = "New")]
        [Parameter(Mandatory, ParameterSetName = "Existing")]
        [Object[]] $Settings,

        [Parameter(ParameterSetName = "New")]
        [ValidateNotNullOrEmpty()]
        [String[]] $ExistingSessionHostNames,

        [Parameter(ParameterSetName = "New")]
        [ValidateNotNullOrEmpty()]
        [String[]] $EntraIdJoinedVirtualMachineNames,

        [Parameter(ParameterSetName = "Existing")]
        [ValidateNotNullOrEmpty()]
        [String] $VirtualMachineId
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    switch ($PSCmdlet.ParameterSetName) {
        "Existing" {
            $VirtualMachine = $VirtualMachineId | Get-ResourceInformation
            Write-Log "Getting deployment location for virtual machine '$($VirtualMachine.Name)'"
            $VirtualMachineContext = Get-Context -SubscriptionId $VirtualMachine.SubscriptionId

            $AzVMParameters = @{
                DefaultProfile = $VirtualMachineContext
                ResourceId     = $VirtualMachine.Id
            }
            $VirtualMachine = Get-AzVM @AzVMParameters

            $AzNetworkInterfaceParameters = @{
                DefaultProfile = $VirtualMachineContext
                ResourceId     = $VirtualMachine.NetworkProfile.NetworkInterfaces.Id
            }
            $NetworkInterface = Get-AzNetworkInterface @AzNetworkInterfaceParameters
            $Subnet = $NetworkInterface.IpConfigurations.Subnet.Id | Get-ResourceInformation
            $ResourceGroup = $VirtualMachineId | Get-ResourceGroupFromId

            $DiskEncryptionSet = (Get-AzDiskEncryptionSet -DefaultProfile $VirtualMachineContext).where({ $PSItem.Location -eq $Subnet.Location })
            $AzNetworkInterfaceParameters = @{
                DefaultProfile        = $VirtualMachineContext
                DiskEncryptionSetName = $DiskEncryptionSet.name
                ResourceGroupName     = $DiskEncryptionSet.ResourceGroupName
            }
            $DiskEncryptionSetAssociatedResources = Get-AzDiskEncryptionSetAssociatedResource @AzNetworkInterfaceParameters
            if ($DiskEncryptionSetAssociatedResources.Count -eq 0) {
                Write-Log "Failed to find associated resources for disk encryption set '$($DiskEncryptionSet.name)' in region '$($Subnet.Location)' for virtual machine '$($VirtualMachine.Name)'" -LogLevel 'ERRORSTOP'
            }

            $DiskEncryptionSet = if ($DiskEncryptionSetAssociatedResources.Contains($VirtualMachine.StorageProfile.OsDisk.ManagedDisk.Id)) {
                $DiskEncryptionSet.Id | Get-ResourceInformation
            } else {
                Write-Log "Failed to find OS disk in associated resources for disk encryption set '$($DiskEncryptionSet.name)' in region '$($Subnet.Location)' for virtual machine '$($VirtualMachine.Name)'" -LogLevel 'ERRORSTOP'
            }

            return @{
                ComputeResourceGroup      = $ResourceGroup
                DiskEncryptionSet         = $DiskEncryptionSet
                FSLogixStorageAccountName = $Settings.FSLogixStorageAccountName.where({ $PSItem.Label -eq $Subnet.Location }).LabeledValue
                Subnet                    = $Subnet
            }
        }

        "New" {
            # Do not change order
            $RegionalComputePriorityOrder = @(
                "usgovvirginia"
                "usgovarizona"
                "usdodeast"
                "usgovtexas"
            )

            $DeployableLocations = $Settings.Subnet.LabeledValue | Invoke-SubnetDeploymentLocationCapacityCheck -DesiredCount $MissingSessionHostCount -VirtualMachineSKUSize $Settings.VirtualMachineSKUSize
            if ($DeployableLocations.Count -gt 0) {
                $SelectedDeployableLocations = [System.Collections.Generic.List[Hashtable]]::new()
                switch ($Settings.DeploymentLocationModel) {
                    "Centralize" {
                        Write-Log "Deployment model is '$($Settings.DeploymentLocationModel)', session hosts will be deployed to as few deployment locations as possible"
                        [Object[]] $SortedDeployableLocations = $DeployableLocations | Sort-Object { $RegionalComputePriorityOrder.IndexOf($PSItem.Subnet.Location) }
                        foreach ($SortedDeployableLocation in $SortedDeployableLocations) {
                            if ($SortedDeployableLocation.DeployableCount -ge $MissingSessionHostCount) {
                                [Int] $SortedDeployableLocation.SuggestedDeploymentCount = $MissingSessionHostCount
                                Write-Log "Deploying $($SortedDeployableLocation.SuggestedDeploymentCount) session hosts to $($SortedDeployableLocation.Subnet.Name)"
                                $SelectedDeployableLocations.Add($SortedDeployableLocation)
                                break
                            } else {
                                [Int] $SortedDeployableLocation.SuggestedDeploymentCount = $SortedDeployableLocation.DeployableCount
                                $SelectedDeployableLocations.Add($SortedDeployableLocation)
                            }

                            # Overwrite '$MissingSessionHostCount' with remaining desired count
                            [Int] $MissingSessionHostCount = $MissingSessionHostCount - $SortedDeployableLocation.DeployableCount
                        }
                    }

                    "Distribute" {
                        Write-Log "Deployment model is '$($Settings.DeploymentLocationModel)', this option is not available" -LogLevel 'ERRORSTOP'
                        # TODO: add feature to distribute VMs across subnets instead of centralizing them
                    }

                    default {
                        Write-Log "Unrecognized deployment model '$($Settings.DeploymentLocationModel)', this option is not available" -LogLevel 'ERRORSTOP'
                    }
                }

                Write-Log "Selected deployment location subnets: $($SelectedDeployableLocations.Subnet.Name -join ', ')"
                $SelectedDeployableLocations | Get-SubnetDeploymentLocationSetting -Settings $Settings

                if (
                    ($PSBoundParameters.ContainsKey("ExistingSessionHostNames")) -or
                    ($PSBoundParameters.ContainsKey("EntraIdJoinedVirtualMachineNames"))
                ) {
                    $AvailableSessionHostNameParameters = @{}

                    if (
                        ($PSBoundParameters.ContainsKey("ExistingSessionHostNames")) -and
                        ($ExistingSessionHostNames.Count -gt 0)
                    ) {
                        Write-Log "Found $($ExistingSessionHostNames.Count) existing session host name(s) for host pool - $($ExistingSessionHostNames -join ', ')"
                        $AvailableSessionHostNameParameters["ExistingSessionHostNames"] = $ExistingSessionHostNames
                    }

                    if (
                        ($PSBoundParameters.ContainsKey("EntraIdJoinedVirtualMachineNames")) -and
                        ($EntraIdJoinedVirtualMachineNames.Count -gt 0)
                    ) {
                        Write-Log "Found $($EntraIdJoinedVirtualMachineNames.Count) Entra ID joined virtual machine name(s) - $($EntraIdJoinedVirtualMachineNames -join ', ')"
                        $AvailableSessionHostNameParameters["EntraIdJoinedVirtualMachineNames"] = $EntraIdJoinedVirtualMachineNames
                    }

                    $SelectedDeployableLocations | Get-AvailableSessionHostName @AvailableSessionHostNameParameters
                } else {
                    $SelectedDeployableLocations | Get-AvailableSessionHostName
                }

                return $SelectedDeployableLocations
            }
        }
    }
}
Export-ModuleMember -Function Get-DeploymentLocation

function Set-VirtualMachineExtensionJoinEntraId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Object] $AssetStorageAccount,

        [Parameter(Mandatory)]
        [Object] $DeploymentLocation,

        [Parameter(Mandatory)]
        [Object] $VirtualMachine
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $JoinToEntraID = $false

    # TODO: Should we check for device within Intune as well?
    # TODO: Is there a way to handle all these nested
    # if conditions in a nicer cleaner way?
    Write-Log "Checking for existing Entra ID device(s) with the name '$($VirtualMachine.Name)'"
    [Object[]] $EntraIDDevices = Get-MgDevice -Filter "DisplayName eq '$($VirtualMachine.Name)'"
    Write-Log "Found $($EntraIDDevices.Count) existing Entra ID device(s) with the name '$($VirtualMachine.Name)'"
    if ($EntraIDDevices.Count -gt 0) {
        Write-Log "Checking for existing Entra ID device ID tag on virtual machine '$($VirtualMachine.Name)'"
        if ([String]::IsNullOrWhiteSpace($VirtualMachine.Tags.EntraIdDeviceId)) {
            Write-Log "Entra ID device ID tag does not exist on virtual machine '$($VirtualMachine.Name)', cleaning up stale Entra ID device(s)"
            $VirtualMachine.Name | Remove-EntraIdIntuneDevice
            $JoinToEntraID = $true
        } else {
            Write-Log "Found existing Entra ID device ID tag on virtual machine '$($VirtualMachine.Name)' with device ID '$($VirtualMachine.Tags.EntraIdDeviceId)'"
            $ActiveEntraIdDevice = $EntraIDDevices.where({ $PSItem.DeviceId -ieq $VirtualMachine.Tags.EntraIdDeviceId })
            if ($null -eq $ActiveEntraIdDevice) {
                Write-Log "Existing Entra ID device(s) does not include an active device for virtual machine '$($VirtualMachine.Name)' with device ID '$($VirtualMachine.Tags.EntraIdDeviceId)', cleaning up stale Entra ID device(s)"
                $VirtualMachine.Name | Remove-EntraIdIntuneDevice
                $JoinToEntraID = $true
            } else {
                $StaleEntraIdDevices = $EntraIDDevices.where({ $PSItem.DeviceId -ine $VirtualMachine.Tags.EntraIdDeviceId })
                if ($StaleEntraIdDevices.Count -gt 0) {
                    Write-Log "Found an active Entra ID device for virtual machine '$($VirtualMachine.Name)' with device ID '$($VirtualMachine.Tags.EntraIdDeviceId)', cleaning up stale Entra ID device(s)"
                    foreach ($StaleEntraIdDevice in $StaleEntraIdDevices) {
                        Remove-EntraIdIntuneDevice -DeviceId $StaleEntraIdDevice.DeviceId
                    }
                } else {
                    Write-Log "Found an active Entra ID device for virtual machine '$($VirtualMachine.Name)' with device ID '$($VirtualMachine.Tags.EntraIdDeviceId)'"
                }
            }
        }
    } else {
        $JoinToEntraID = $true
    }

    if ($JoinToEntraID) {
        $VirtualMachineContext = Get-Context -SubscriptionId $VirtualMachine.SubscriptionId
        $AzVMExtensionParameters = @{
            DefaultProfile    = $VirtualMachineContext
            ErrorAction       = "SilentlyContinue"
            Name              = "AADLoginForWindows"
            ResourceGroupName = $VirtualMachine.ResourceGroupName
            VMName            = $VirtualMachine.Name
        }
        $ExistingEntraIdExtension = Get-AzVMExtension @AzVMExtensionParameters
        if ($null -ne $ExistingEntraIdExtension) {
            Write-Log "Removing existing Entra ID extension on virtual machine '$($VirtualMachine.Name)' prior to joining it to Entra ID"
            $AzVMExtensionParameters = @{
                Confirm           = $false
                DefaultProfile    = $VirtualMachineContext
                ErrorAction       = "Stop"
                Force             = $true
                Name              = "AADLoginForWindows"
                ResourceGroupName = $VirtualMachine.ResourceGroupName
                VMName            = $VirtualMachine.Name
            }
            Remove-AzVMExtension @AzVMExtensionParameters
        }

        try {
            Write-Log "Joining virtual machine '$($VirtualMachine.Name)' to Entra ID"
            $AzVMExtensionParameters = @{
                Confirm                        = $false
                DefaultProfile                 = $VirtualMachineContext
                DisableAutoUpgradeMinorVersion = $false
                EnableAutomaticUpgrade         = $false
                ErrorAction                    = "Stop"
                ExtensionType                  = "AADLoginForWindows"
                Location                       = $DeploymentLocation.Subnet.Location
                Name                           = "AADLoginForWindows"
                Publisher                      = "Microsoft.Azure.ActiveDirectory"
                ResourceGroupName              = $VirtualMachine.ResourceGroupName
                Settings                       = $null #TODO: Make mdmId = "0000000a-0000-0000-c000-000000000000" optional
                TypeHandlerVersion             = "2.0"
                VMName                         = $VirtualMachine.Name
            }
            $AADLoginForWindows = Set-AzVMExtension @AzVMExtensionParameters
            if (-not ($AADLoginForWindows.IsSuccessStatusCode)) {
                Write-Log "Entra ID Extension Output: $($AADLoginForWindows | ConvertTo-Json -Depth 100 -Compress)" -LogLevel 'ERROR'
                Write-Log "Failed to join virtual machine '$($VirtualMachine.Name)' to Entra ID due to error '$($AADLoginForWindows.ReasonPhrase)'" -LogLevel 'ERRORSTOP'
            }
        } catch {
            Write-Log "Failed to join virtual machine '$($VirtualMachine.Name)' to Entra ID due to error '$($PSItem.Exception.Message)'" -LogLevel 'ERRORSTOP'
        }

        $EntraIdDeviceAuthStatusParameters = @{
            Location                     = $DeploymentLocation.Subnet.Location
            Name                         = "DeviceStatusCheck"
            ResourceGroupName            = $VirtualMachine.ResourceGroupName
            RunCommandLogsStorageAccount = $AssetStorageAccount
            ScriptPath                   = "./Scripts/Get-EntraIdDeviceAuthStatus.ps1"
            SubscriptionId               = $VirtualMachine.SubscriptionId
            VirtualMachineName           = $VirtualMachine.Name
        }
        $EntraIdDeviceAuthStatus = Set-VirtualMachineRunCommand @EntraIdDeviceAuthStatusParameters
        if ($EntraIdDeviceAuthStatus.ProvisioningState -ine "Succeeded") {
            Write-Log "Failed to run script to get Entra ID device authentication status after joining virtual machine '$($VirtualMachine.Name)' to Entra ID" -LogLevel 'ERROR'
            Write-Log ($EntraIdDeviceAuthStatus.Error | Out-String) -LogLevel 'ERRORSTOP'
        }

        $EntraIdDeviceAuthStatusLogs = $EntraIdDeviceAuthStatus.Output | ConvertFrom-Json -Depth 100
        if ($EntraIdDeviceAuthStatusLogs.Status -ieq "Failed") {
            Write-Log "Failed to get Entra ID device authentication status after joining virtual machine '$($VirtualMachine.Name)' to Entra ID due to error '$($EntraIdDeviceAuthStatusLogs.Message)'" -LogLevel 'ERRORSTOP'
        }

        if ($EntraIdDeviceAuthStatusLogs.DeviceAuthStatus -ine "SUCCESS") {
            # If this isn't success then we fail and the function re-tries
            # which goes through the Entra ID check above again and that
            # will check for any existing devices, remove the extension, etc
            Write-Log "Found invalid Entra ID device authentication status '$($EntraIdDeviceAuthStatusLogs.DeviceAuthStatus)' after joining virtual machine '$($VirtualMachine.Name)' to Entra ID" -LogLevel 'ERRORSTOP'
        }

        Write-Log "Found virtual machine '$($VirtualMachine.Name)' with device ID '$($EntraIdDeviceAuthStatusLogs.DeviceId)' after joining it to Entra ID"
        try {
            $AzTagParameters = @{
                DefaultProfile = $VirtualMachineContext
                ErrorAction    = "Stop"
                Operation      = "Merge"
                ResourceId     = $VirtualMachine.Id
                Tag            = @{ EntraIdDeviceId = $EntraIdDeviceAuthStatusLogs.DeviceId }
            }
            Update-AzTag @AzTagParameters | Out-Null
        } catch {
            Write-Log "Failed to add 'EntraIdDeviceId' tag to virtual machine '$($VirtualMachine.Name)' due to error '$($PSItem.Exception.Message)'" -LogLevel 'ERRORSTOP'
        }
    } else {
        Write-Log "Virtual machine '$($VirtualMachine.Name)' already joined to Entra ID"
    }
}

function Set-VirtualMachineRunCommandDiskConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Object] $AssetStorageAccount,

        [Parameter(Mandatory)]
        [Object] $DeploymentLocation,

        [Parameter(Mandatory)]
        [Object] $VirtualMachine
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Write-Log "Configuring disks on virtual machine '$($VirtualMachine.Name)'"

    $DiskConfigurationParameters = @{
        Location                     = $DeploymentLocation.Subnet.Location
        Name                         = "DiskConfiguration"
        ResourceGroupName            = $VirtualMachine.ResourceGroupName
        RunCommandLogsStorageAccount = $AssetStorageAccount
        ScriptPath                   = "./Scripts/Invoke-DiskConfiguration.ps1"
        SubscriptionId               = $VirtualMachine.SubscriptionId
        VirtualMachineName           = $VirtualMachine.Name
    }
    $DiskConfiguration = Set-VirtualMachineRunCommand @DiskConfigurationParameters
    if ($DiskConfiguration.ProvisioningState -ine "Succeeded") {
        # TODO: Refactor this script to return JSON data so
        # we can check status from returned output as well
        # this would allow us to handle more complex errors
        # rather then it just failing and retrying
        Write-Log "Disk Configuration Run Command Output: $($DiskConfiguration | ConvertTo-Json -Depth 100 -Compress)" -LogLevel 'ERROR'
        Write-Log "Failed to run script to configure disks on virtual machine '$($VirtualMachine.Name)'" -LogLevel 'ERRORSTOP'
    }
}

function Set-VirtualMachineRunCommandHostsFileConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Object] $AssetStorageAccount,

        [Parameter(Mandatory)]
        [Object] $DeploymentLocation,

        [Parameter(Mandatory)]
        [Object] $VirtualMachine
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Write-Log "Configuring hosts file on virtual machine '$($VirtualMachine.Name)'"

    $HostsFileConfigurationParameters = @{
        Location                     = $DeploymentLocation.Subnet.Location
        Name                         = "HostsFileConfiguration"
        ResourceGroupName            = $VirtualMachine.ResourceGroupName
        RunCommandLogsStorageAccount = $AssetStorageAccount
        ScriptPath                   = "./Scripts/Invoke-HostsFileConfiguration.ps1"
        SubscriptionId               = $VirtualMachine.SubscriptionId
        VirtualMachineName           = $VirtualMachine.Name
    }
    $HostsFileConfiguration = Set-VirtualMachineRunCommand @HostsFileConfigurationParameters
    if ($HostsFileConfiguration.ProvisioningState -ine "Succeeded") {
        # TODO: Refactor this script to return JSON data so
        # we can check status from returned output as well
        # this would allow us to handle more complex errors
        # rather then it just failing and retrying

        Write-Log "Hosts File Configuration Run Command Output: $($HostsFileConfiguration | ConvertTo-Json -Depth 100 -Compress)" -LogLevel 'ERROR'
        Write-Log "Failed to run script to configure hosts file on virtual machine '$($VirtualMachine.Name)'" -LogLevel 'ERRORSTOP'
    }
}

function Set-VirtualMachineRunCommandNTFSPermissionConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Object] $AssetStorageAccount,

        [Parameter(Mandatory)]
        [Object] $DeploymentLocation,

        [Parameter(Mandatory)]
        [Object] $VirtualMachine
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Write-Log "Configuring NTFS permissions on virtual machine '$($VirtualMachine.Name)'"

    $NTFSPermissionConfigurationParameters = @{
        Location                     = $DeploymentLocation.Subnet.Location
        Name                         = "HostsFileConfiguration"
        ResourceGroupName            = $VirtualMachine.ResourceGroupName
        RunCommandLogsStorageAccount = $AssetStorageAccount
        ScriptPath                   = "./Scripts/Invoke-NTFSPermissionConfiguration.ps1"
        SubscriptionId               = $VirtualMachine.SubscriptionId
        VirtualMachineName           = $VirtualMachine.Name
    }
    $NTFSPermissionConfiguration = Set-VirtualMachineRunCommand @NTFSPermissionConfigurationParameters
    if ($NTFSPermissionConfiguration.ProvisioningState -ine "Succeeded") {
        # TODO: Refactor this script to return JSON data so
        # we can check status from returned output as well
        # this would allow us to handle more complex errors
        # rather then it just failing and retrying
        Write-Log "NTFS Permission Configuration Run Command Output: $($NTFSPermissionConfiguration | ConvertTo-Json -Depth 100 -Compress)" -LogLevel 'ERROR'
        Write-Log "Failed to run script to configure NTFS permissions on virtual machine '$($VirtualMachine.Name)'" -LogLevel 'ERRORSTOP'
    }
}

function Set-VirtualMachineRunCommandFSLogixConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Object] $AssetStorageAccount,

        [Parameter(Mandatory)]
        [Object] $DeploymentLocation,

        [Parameter(Mandatory)]
        [Object] $VirtualMachine
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    Write-Log "Configuring FSLogix on virtual machine '$($VirtualMachine.Name)'"

    $FSLogixConfigurationParameters = @{
        Location                     = $DeploymentLocation.Subnet.Location
        Name                         = "FSLogixConfiguration"
        Parameter                    = @(
            @{
                Name  = "FSLogixStorageAccountName"
                Value = $DeploymentLocation.FSLogixStorageAccountName
            }
        )
        ResourceGroupName            = $VirtualMachine.ResourceGroupName
        RunCommandLogsStorageAccount = $AssetStorageAccount
        ScriptPath                   = "./Scripts/Invoke-FSLogixConfiguration.ps1"
        SubscriptionId               = $VirtualMachine.SubscriptionId
        VirtualMachineName           = $VirtualMachine.Name
    }
    $FSLogixConfiguration = Set-VirtualMachineRunCommand @FSLogixConfigurationParameters
    if ($FSLogixConfiguration.ProvisioningState -ine "Succeeded") {
        # TODO: Refactor this script to return JSON data so
        # we can check status from returned output as well
        # this would allow us to handle more complex errors
        # rather then it just failing and retrying
        Write-Log "FSLogix Configuration Run Command Output: $($FSLogixConfiguration | ConvertTo-Json -Depth 100 -Compress)" -LogLevel 'ERROR'
        Write-Log "Failed to run script to configure FSLogix on virtual machine '$($VirtualMachine.Name)'" -LogLevel 'ERRORSTOP'
    }
}

function Set-VirtualMachinePostProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Object] $AssetStorageAccount,

        [Parameter(Mandatory)]
        [Object] $DeploymentLocation,

        [Parameter(Mandatory)]
        [Object] $VirtualMachine
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    # TODO: Do we want to make it so some of these
    # post process steps run in parallel like Bicep did?

    $PostProcessParameters = @{
        AssetStorageAccount = $AssetStorageAccount
        DeploymentLocation  = $DeploymentLocation
        VirtualMachine      = $VirtualMachine
    }
    Set-VirtualMachineExtensionJoinEntraId @PostProcessParameters
    Set-VirtualMachineRunCommandDiskConfiguration @PostProcessParameters
    Set-VirtualMachineRunCommandHostsFileConfiguration @PostProcessParameters
    Set-VirtualMachineRunCommandNTFSPermissionConfiguration @PostProcessParameters
    Set-VirtualMachineRunCommandFSLogixConfiguration @PostProcessParameters
}
Export-ModuleMember -Function Set-VirtualMachinePostProcess

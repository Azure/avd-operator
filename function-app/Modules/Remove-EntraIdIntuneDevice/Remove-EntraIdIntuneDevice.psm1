function Remove-Device {
    [OutputType([String[]])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Object] $Device,

        [Parameter()]
        [ValidateSet("EntraId", "Intune")]
        [String] $Type = "EntraId",

        [Parameter()]
        [ValidateSet("ERROR", "ERRORSTOP", "WARN")]
        [String] $DeviceCleanupPermissionErrorAction = "WARN"
    )

    begin {
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    }

    process {
        switch ($Type) {
            "EntraId" {
                try {
                    Write-Log "Removing device '$($Device.DisplayName)' with ID '$($Device.Id)' from Entra ID"
                    Remove-MgDevice -DeviceId $Device.Id -ErrorAction Stop
                } catch {
                    if ($PSItem.Exception.Message -ilike "*Insufficient privileges to complete the operation*") {
                        Write-Log "Device '$($Device.DisplayName)' with ID '$($Device.Id)' is not within AVD administrative unit, identity did not have permission to remove the device from Entra ID" -LogLevel $DeviceCleanupPermissionErrorAction
                    } else {
                        Write-Log "Failed to remove device '$($Device.DisplayName)' with ID '$($Device.Id)' from Entra ID" -LogLevel 'ERROR'
                        Write-Log $PSItem.Exception.Message -Exception $PSItem.Exception -LogLevel 'ERRORSTOP'
                    }
                }
            }

            "Intune" {
                try {
                    Write-Log "Removing device '$($Device.DeviceName)' with ID '$($Device.Id)' from Intune"
                    Remove-MgDeviceManagementManagedDevice -ManagedDeviceId $Device.Id -ErrorAction Stop
                } catch {
                    Write-Log "Failed to remove device '$($Device.DeviceName)' with ID '$($Device.Id)' from Intune" -LogLevel 'ERROR'
                    Write-Log $PSItem.Exception.Message -Exception $PSItem.Exception -LogLevel 'ERRORSTOP'
                }
            }
        }
    }

    end {}
}

# TODO: Re-evaluate if this function is still needed
# This function is no longer being actively used because
# the extension attributes used to check for the permissions
# do not consistently exist and so instead we are catching
# the error above in another function
function Get-EntraIdDevicePermission {
    [CmdletBinding()]
    [OutputType([Bool])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Object] $Device
    )

    begin {
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

        $DevicePermission = [System.Collections.Generic.List[Object]]::new()
    }

    process {
        $DeviceExtensionAttributes = $Device.AdditionalProperties.extensionAttributes

        if (
            ($null -ne $DeviceExtensionAttributes) -and
            ($DeviceExtensionAttributes.extensionAttribute6 -eq "ArmyAVD") -and
            ($DeviceExtensionAttributes.extensionAttribute7 -eq "AVD")
        ) {
            $Permission = $true
        } else {
            Write-Log "Device '$($Device.DisplayName)' with ID '$($Device.Id)' is not within AVD administrative unit, identity will not have permission to remove the device from Entra ID" -LogLevel 'ERROR'
            $Permission = $false
        }

        $DevicePermission.Add(@{
                Device     = $Device
                Permission = $Permission
            }
        )
    }

    end {
        return $DevicePermission
    }
}

function Remove-EntraIdIntuneDevice {
    [CmdletBinding(DefaultParameterSetName = "Name")]
    [OutputType([String[]])]
    param(
        [Parameter(Mandatory, ParameterSetName = "Name", ValueFromPipeline)]
        [String] $DeviceName,

        [Parameter(Mandatory, ParameterSetName = "Prefix")]
        [String] $DeviceNamePrefix,

        [Parameter(Mandatory, ParameterSetName = "Id")]
        [String] $DeviceId,

        [Parameter()]
        [ValidateSet("ERROR", "ERRORSTOP")]
        [String] $DeviceCleanupPermissionErrorAction = "ERROR"
    )

    begin {
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    }

    process {
        switch ($PSCmdlet.ParameterSetName) {
            "Name" {
                Write-Log "Getting device '${DeviceName}' from Entra ID"
                [Object[]] $EntraIDDevices = Get-MgDevice -Filter "DisplayName eq '${DeviceName}'"
                Write-Log "Found $($EntraIDDevices.Count) matching object(s) for device '${DeviceName}' in Entra ID "

                # TODO: get Intune permissions assigned to function
                # Identity doesn't have Intune permissions yet

                # Write-Log "Getting device '${DeviceName}' from Intune"
                # [Object[]] $IntuneDevices = Get-MgDeviceManagementManagedDevice -Filter "DeviceName eq '${DeviceName}'"
                # Write-Log "Found $($IntuneDevices.Count) matching object(s) for device '${DeviceName}' in Intune"
            }

            "Prefix" {
                Write-Log "Getting Entra ID devices using prefix '${DeviceNamePrefix}'"
                [Object[]] $EntraIDDevices = Get-MgDevice -All -Filter "StartsWith(DisplayName, '${DeviceNamePrefix}')"
                Write-Log "Found $($EntraIDDevices.Count) matching Entra ID devices using prefix '${DeviceNamePrefix}'"

                # TODO: get Intune permissions assigned to function
                # Identity doesn't have Intune permissions yet

                # Write-Log "Getting Intune devices using prefix '${DeviceNamePrefix}'"
                # [Object[]] $IntuneDevices = Get-MgDeviceManagementManagedDevice -All -Filter "StartsWith(DeviceName, '${DeviceNamePrefix}')"
                # Write-Log "Found $($IntuneDevices.Count) matching Intune devices using prefix '${DeviceNamePrefix}'"
            }

            "Id" {
                Write-Log "Getting device with ID '${DeviceId}' from Entra ID"
                [Object[]] $EntraIDDevices = Get-MgDevice -DeviceId $DeviceId
                Write-Log "Found $($EntraIDDevices.Count) matching object(s) for device with ID '${DeviceId}' in Entra ID "
            }
        }

        if ($EntraIDDevices.Count -gt 0) {
            # TODO: Re-evaluate if this permission check functionality is still needed
            # $EntraIDDevicesWithPermission = ($EntraIDDevices | Get-EntraIdDevicePermission).where({ $PSItem.Permission }).Device
            # if ($EntraIDDevicesWithPermission.Count -gt 0) {
            #     $EntraIDDevicesWithPermission | Remove-Device -DeviceCleanupPermissionErrorAction $DeviceCleanupPermissionErrorAction -Type "EntraId"
            # }

            $EntraIDDevices | Remove-Device -DeviceCleanupPermissionErrorAction $DeviceCleanupPermissionErrorAction -Type "EntraId"
        }

        # TODO: get Intune permissions assigned to function
        # Identity doesn't have Intune permissions yet

        # if ($IntuneDevices.Count -gt 0) {
        #     $IntuneDevices | Remove-Device -DeviceCleanupPermissionErrorAction $DeviceCleanupPermissionErrorAction -Type "Intune"
        # }
    }
}
Export-ModuleMember -Function Remove-EntraIdIntuneDevice
function Invoke-EntraIdDeviceGroupMemberAction {
    [CmdletBinding()]
    [OutputType()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Object] $Device,

        [Parameter(Mandatory)]
        [Object] $DeviceGroup,

        [Parameter(Mandatory)]
        [ValidateSet("Add", "Remove")]
        [String] $Action
    )

    begin {
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    }

    process {
        $AzADGroupMemberParameters = @{
            ErrorAction    = "Stop"
            MemberObjectId = $Device.Id
            WarningAction  = "Ignore"
        }

        # AzADGroupMember cmdlets are using preview API for
        # Microsoft Graph, using 'WarningAction Ignore' to
        # suppress this warning message which clutters the output on console
        Write-Log "Refreshing membership of Entra ID security device group '$($DeviceGroup.DisplayName)' for Entra ID device '$($Device.DisplayName)' with ID '$($Device.Id)'"
        $DeviceGroupMembers = Get-AzADGroupMember -GroupObjectId $DeviceGroup.Id -WarningAction Ignore
        if ($DeviceGroupMembers.Id -contains $Device.Id) {
            switch ($Action) {
                "Add" {
                    Write-Log "Entra ID device '$($Device.DisplayName)' with ID '$($Device.Id)' is already a member of Entra ID security device group '$($DeviceGroup.DisplayName)'"
                }

                "Remove" {
                    Write-Log "Entra ID device '$($Device.DisplayName)' with ID '$($Device.Id)' is a member of Entra ID security device group '$($DeviceGroup.DisplayName)'"
                    Write-Log "Removing Entra ID device '$($Device.DisplayName)' with ID '$($Device.Id)' from Entra ID security device group '$($DeviceGroup.DisplayName)'"
                    Remove-AzADGroupMember @AzADGroupMemberParameters -GroupObjectId $DeviceGroup.Id
                }
            }
        } else {
            Write-Log "Entra ID device '$($Device.DisplayName)' with ID '$($Device.Id)' is not a member of Entra ID security device group '$($DeviceGroup.DisplayName)'"
            if ($Action -eq "Add") {
                Write-Log "Adding Entra ID device '$($Device.DisplayName)' with ID '$($Device.Id)' to Entra ID security device group '$($DeviceGroup.DisplayName)'"
                Add-AzADGroupMember @AzADGroupMemberParameters -TargetGroupObjectId $DeviceGroup.Id
            }
        }
    }

    end {}
}

function Set-EntraIdDeviceGroupMembership {
    [CmdletBinding()]
    [OutputType()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [String] $DeviceName,

        [Parameter(Mandatory)]
        [String] $DeviceGroupName,

        [Parameter(Mandatory)]
        [ValidateSet("Add", "Remove")]
        [String] $Action
    )

    begin {
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

        Write-Log "Getting Entra ID security device group '${DeviceGroupName}'"
        $DeviceGroup = Get-AzADGroup -DisplayName $DeviceGroupName
        if ($null -eq $DeviceGroup) {
            Write-Log "Failed to find Entra ID security device group '${DeviceGroupName}'" -LogLevel 'ERRORSTOP'
        }
    }

    process {
        Write-Log "Getting unique ID(s) for Entra ID device '${DeviceName}'"
        $Devices = Get-MgDevice -Filter "DisplayName eq '${DeviceName}'"
        Write-Log "Found $($Devices.Count) unique ID(s) for Entra ID device '${DeviceName}'"
        if ($Devices.Count -gt 0) {
            $Devices | Invoke-EntraIdDeviceGroupMemberAction -DeviceGroup $DeviceGroup -Action $Action
        } else {
            switch ($Action) {
                "Add" {
                    Write-Log "Failed to find unique ID(s) for Entra ID device '${DeviceName}'" -LogLevel 'ERRORSTOP'
                }

                "Remove" {
                    Write-Log "Entra ID device '${DeviceName}' does not exist, therefore, Entra ID security device group membership removal is not necessary"
                }
            }
        }
    }

    end {}
}
Export-ModuleMember -Function Set-EntraIdDeviceGroupMembership
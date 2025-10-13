function Update-HostPoolAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Object[]] $Settings,

        [Parameter()]
        [Object] $NewAssignment
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    # AzWvdScalingPlan commands within this module don't support -DefaultProfile
    # they also don't work correctly with -SubscriptionId so we are using
    # Set-AzContext to configure the subscription context for the commands

    Set-AzContext -Subscription $Settings.HostPool.SubscriptionId | Out-Null

    Write-Log "Checking if host pool is assigned to a scaling plan"
    $AssignedScalingPlan = Get-AzWvdScalingPlan | Where-Object { $PSItem.HostPoolReference.HostPoolArmPath -contains $Settings.HostPool.Id }
    if ($null -eq $AssignedScalingPlan) {
        Write-Log "Host pool is not assigned to a scaling plan"
    } else {
        try {
            Write-Log "Host pool is assigned to scaling plan '$($AssignedScalingPlan.Name)'"
            Write-Log "Unassigning host pool from scaling plan '$($AssignedScalingPlan.Name)'"

            $HostPoolAssignmentToRemove = $AssignedScalingPlan.HostPoolReference | Where-Object { $PSItem.HostPoolArmPath -eq $Settings.HostPool.Id }
            $UpdatedHostPoolAssignment = $AssignedScalingPlan.HostPoolReference | Where-Object { $PSItem -ne $HostPoolAssignmentToRemove }
            if ($null -eq $UpdatedHostPoolAssignment) {
                Update-AzWvdScalingPlan -InputObject $AssignedScalingPlan -HostPoolReference @{}
            } else {
                Update-AzWvdScalingPlan -InputObject $AssignedScalingPlan -HostPoolReference $UpdatedHostPoolAssignment
            }
        } catch {
            Write-Log "Failed to unassign host pool from scaling plan '$($AssignedScalingPlan.Name)' due to error '$($PSItem.Exception.Message)'" -LogLevel 'ERRORSTOP'
        }
    }

    if (
        $PSBoundParameters.ContainsKey("NewAssignment") -and
        ($null -ne $NewAssignment)
    ) {
        try {
            $ScalingPlan = Get-AzWvdScalingPlan -Name $NewAssignment.Name -ResourceGroupName $NewAssignment.ResourceGroupName
            Write-Log "Assigning host pool to scaling plan '$($ScalingPlan.Name)'"
            $UpdatedHostPoolAssignment = $ScalingPlan.HostPoolReference += @{'HostPoolArmPath' = "$($Settings.HostPool.Id)"; 'ScalingPlanEnabled' = $true; }
            Update-AzWvdScalingPlan -InputObject $ScalingPlan -HostPoolReference $UpdatedHostPoolAssignment
            Write-Log "Assigned host pool to scaling plan '$($ScalingPlan.Name)'"
        } catch {
            Write-Log "Failed to assign host pool to scaling plan '$($ScalingPlan.Name)' due to error '$($PSItem.Exception.Message)'" -LogLevel 'ERRORSTOP'
        }
    } else {
        Write-Log "A new scaling plan assignment for the host pool has not been provided"
    }
}

function Update-DisconnectedUsersFunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("true", "false")]
        [String] $Disabled,

        [Parameter(Mandatory)]
        [Object[]] $Settings
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $GetAzFunctionAppSettingParameters = @{
        Name              = $Settings.FunctionAppName
        ResourceGroupName = $Settings.FunctionAppResourceGroupName
        SubscriptionId    = $env:_FunctionAppSubscriptionId
    }
    $TimerDisconnectedUsersCleanupFunctionDisabled = (Get-AzFunctionAppSetting @GetAzFunctionAppSettingParameters)."AzureWebJobs.TimerDisconnectedUsersCleanup.Disabled"
    if ($TimerDisconnectedUsersCleanupFunctionDisabled -eq $Disabled) {
        Write-Log "Disconnected users cleanup function disabled status is already set to '${Disabled}'"
    } else {
        try {
            $UpdateAzFunctionAppSettingParameters = @{
                AppSetting        = @{ "AzureWebJobs.TimerDisconnectedUsersCleanup.Disabled" = $Disabled }
                Name              = $Settings.FunctionAppName
                ResourceGroupName = $Settings.FunctionAppResourceGroupName
                SubscriptionId    = $env:_FunctionAppSubscriptionId
            }
            Write-Log "Disconnected users cleanup function disabled status is currently '${TimerDisconnectedUsersCleanupFunctionDisabled}' and will be updated to '${Disabled}'"
            Update-AzFunctionAppSetting @UpdateAzFunctionAppSettingParameters
        } catch {
            Write-Log "Failed to update disabled status for disconnected users cleanup function due to error '$($PSItem.Exception.Message)'" -LogLevel 'ERRORSTOP'
        }

    }
}

function Get-HostPoolAssignments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Object[]] $Settings
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $HostPoolReference = @{}
    $ScalingPlans = @($Settings.BakeScalingPlan, $Settings.CompliantScalingPlan, $Settings.CleanupScalingPlan)

    Set-AzContext -Subscription $Settings.HostPool.SubscriptionId | Out-Null

    foreach ($ScalingPlan in $ScalingPlans) {
        Write-Log "Getting host pool assignments for scaling plan '$($ScalingPlan.Name)'"
        $AzWvdScalingPlanParameters = @{
            Name              = $ScalingPlan.Name
            ResourceGroupName = $ScalingPlan.ResourceGroupName
        }
        $ScalingPlan = Get-AzWvdScalingPlan @AzWvdScalingPlanParameters
        $AssignedHostPools = $ScalingPlan.HostPoolReference.HostPoolArmPath

        if ($Settings.HostPool.Id -in $AssignedHostPools) {
            $HostPoolReference.$($ScalingPlan.Name) = $true
        } else {
            $HostPoolReference.$($ScalingPlan.Name) = $false
        }
    }
    return $HostPoolReference
}

function Set-HostPoolScalingPlanMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Object[]] $Settings
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    try {
        Write-Log "Scaling plan mode is set to '$($Settings.ScalingPlanMode)'"
        if ($Settings.Environment -ne "PROD") {
            $PSTTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneID([datetime]::UtcNow, 'Pacific Standard Time').ToString('HH:mm')
            if (($PSTTime -gt "18:00") -or ($PSTTime -lt "04:00")) {
                foreach ($setting in $Settings) {
                    if ($setting.ContainsKey('ScalingPlanMode')) {
                        $Setting['ScalingPlanMode'] = "Off"
                        Write-Log "Scaling plan mode has been reset to '$($Settings.ScalingPlanMode)' for autoshutdown."
                    }
                }
            }
        }

        switch ($Settings.ScalingPlanMode) {
            "Off" {
                Update-HostPoolAssignment -Settings $Settings
            }

            "Bake" {
                $Assignments = Get-HostPoolAssignments -Settings $Settings
                if ($Assignments.$($Settings.BakeScalingPlan.Name)) {
                    Write-Log "Host pool is already assigned to scaling plan '$($Settings.BakeScalingPlan.Name)'"
                } else {
                    Write-Log "Host pool is not assigned to scaling plan '$($Settings.BakeScalingPlan.Name)'"
                    Update-HostPoolAssignment -NewAssignment $Settings.BakeScalingPlan -Settings $Settings
                }
            }

            "Compliant" {
                $Assignments = Get-HostPoolAssignments -Settings $Settings
                if ($Assignments.$($Settings.CompliantScalingPlan.Name)) {
                    Write-Log "Host pool is already assigned to scaling plan '$($Settings.CompliantScalingPlan.Name)'"
                } else {
                    Write-Log "Host pool is not assigned to scaling plan '$($Settings.CompliantScalingPlan.Name)'"
                    Update-HostPoolAssignment -NewAssignment $Settings.CompliantScalingPlan -Settings $Settings
                }
            }

            "Cleanup" {
                $Assignments = Get-HostPoolAssignments -Settings $Settings
                if ($Assignments.$($Settings.CleanupScalingPlan.Name)) {
                    Write-Log "Host pool is already assigned to scaling plan '$($Settings.CleanupScalingPlan.Name)'"
                } else {
                    Write-Log "Host pool is not assigned to scaling plan '$($Settings.CleanupScalingPlan.Name)'"
                    Update-HostPoolAssignment -NewAssignment $Settings.CleanupScalingPlan -Settings $Settings
                }
            }

            default {
                Write-Log "Unrecognized scaling plan mode '$($Settings.ScalingPlanMode)'" -LogLevel 'ERRORSTOP'
            }
        }
    } finally {
        switch ($Settings.ScalingPlanMode) {
            "Cleanup" {
                Update-DisconnectedUsersFunction -Disabled "false" -Settings $Settings
            }

            default {
                Update-DisconnectedUsersFunction -Disabled "true" -Settings $Settings
            }
        }
    }
}
Export-ModuleMember -Function Set-HostPoolScalingPlanMode
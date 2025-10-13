function Get-SessionHostRegistrationStatus {
    param(
        [Parameter(Mandatory)]
        [Object] $HostPool,

        [Parameter(Mandatory)]
        [String] $VirtualMachineName,

        [Parameter()]
        [Switch] $PreRegistrationCheck
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $AzWvdSessionHostParameters = @{
        ErrorAction       = "SilentlyContinue"
        HostPoolName      = $HostPool.Name
        Name              = $VirtualMachineName
        ResourceGroupName = $HostPool.ResourceGroupName
        SubscriptionId    = $HostPool.SubscriptionId
    }

    if (
        ($PSBoundParameters.ContainsKey("PreRegistrationCheck")) -and
        ($PreRegistrationCheck)
    ) {
        $RecentlyRegisteredSessionHost = Get-AzWvdSessionHost @AzWvdSessionHostParameters
        if ($null -ne $RecentlyRegisteredSessionHost) {
            Write-Log "Virtual machine '${VirtualMachineName}' is registered to host pool as a session host with status '$($RecentlyRegisteredSessionHost.Status)'"
            if ($RecentlyRegisteredSessionHost.Status -ieq "Available") {
                return $true
            } else {
                return $false
            }
        } else {
            Write-Log "Virtual machine '${VirtualMachineName}' is not registered to host pool as a session host"
            return $false
        }
    } else {
        $Timeout = New-TimeSpan -Minutes 7
        $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
        do {
            $RecentlyRegisteredSessionHost = Get-AzWvdSessionHost @AzWvdSessionHostParameters
            if ($null -ne $RecentlyRegisteredSessionHost) {
                Write-Log "Virtual machine '${VirtualMachineName}' has been recently registered to host pool with status '$($RecentlyRegisteredSessionHost.Status)'"
            } else {
                Write-Log "Virtual machine '${VirtualMachineName}' does not have a registration status yet in host pool" -LogLevel 'WARN'
            }

            if ($RecentlyRegisteredSessionHost.Status -ine "Available") {
                Write-Log "Waiting 30 seconds for status of recently registered virtual machine '${VirtualMachineName}' in host pool"
                Start-Sleep -Seconds 30
            }
        } until (
            ($RecentlyRegisteredSessionHost.Status -ieq "Available") -or
            ($StopWatch.Elapsed -ge $Timeout)
        )
        $StopWatch.Stop()

        # TODO: how should we handle failed status, attempt reregister?
        # Remove from host pool and delete? Get status from host pool and
        # understand why it's not "Available"?
        if ($RecentlyRegisteredSessionHost.Status -ieq "Available") {
            return $true
        } elseif ($null -eq $RecentlyRegisteredSessionHost.Status) {
            Write-Log "Failed to find status for recently registered virtual machine '${VirtualMachineName}' in host pool" -LogLevel 'ERRORSTOP'
        } else {
            Write-Log "Failed to wait for status after timeout for recently registered virtual machine '${VirtualMachineName}' in host pool with current status '$($RecentlyRegisteredSessionHost.Status)'" -LogLevel 'ERRORSTOP'
        }
    }
}
Export-ModuleMember -Function Get-SessionHostRegistrationStatus
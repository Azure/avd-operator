param($InputTimer, $TriggerMetadata)

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$InformationPreference = [System.Management.Automation.ActionPreference]::Continue
$WarningPreference = [System.Management.Automation.ActionPreference]::Continue

try {
    $Settings = Get-Settings
    $env:LogPrefix = $Settings.HostPool.Name

    Write-Log "Starting Geekly disconnected users cleanup"

    $HostPoolContext = Get-Context -SubscriptionId $Settings.HostPool.SubscriptionId
    $AzWvdSessionHostParameters = @{
        HostPoolName      = $Settings.HostPool.Name
        ResourceGroupName = $Settings.HostPool.ResourceGroupName
        SubscriptionId    = $Settings.HostPool.SubscriptionId
    }

    if ($Settings.DisconnectUsersOnlyOnDrainedSessionHosts) {
        Write-Log "Getting drained session hosts for host pool '$($Settings.HostPool.Name)'"
        $SessionHosts = Get-AzWvdSessionHost @AzWvdSessionHostParameters
        $SessionHosts = $SessionHosts.Where({ $PSItem.AllowNewSession -eq $false })
        Write-Log "Found $($SessionHosts.Count) drained session hosts within host pool '$($Settings.HostPool.Name)'"
    } else {
        Write-Log "Getting session hosts for host pool '$($Settings.HostPool.Name)'"
        $SessionHosts = Get-AzWvdSessionHost @AzWvdSessionHostParameters
        Write-Log "Found $($SessionHosts.Count) session hosts within host pool '$($Settings.HostPool.Name)'"
    }

    if (-not ($Settings.ChangesAllowed)) {
        Write-Log "Geekly is not allowed to make changes"
        return
    }

    foreach ($SessionHost in $SessionHosts) {
        try {
            $SessionHostName = ($SessionHost.Id | Get-ResourceInformation).Name
            $env:LogPrefix = "$($Settings.HostPool.Name)/${SessionHostName}"

            $AzWvdUserSessionParameters = @{
                HostPoolName      = $Settings.HostPool.Name
                ResourceGroupName = $Settings.HostPool.ResourceGroupName
                SessionHostName   = $SessionHostName
                SubscriptionId    = $Settings.HostPool.SubscriptionId
            }
            $UserSessions = Get-AzWvdUserSession @AzWvdUserSessionParameters
            Write-Log "Found $($UserSessions.Count) user session(s)"

            if ($UserSessions.Count -gt 0) {
                $DisconnectedUserSessions = $UserSessions.Where({ $PSItem.SessionState -ne "Active" })
                Write-Log "Found $($DisconnectedUserSessions.Count) disconnected user session(s)"

                if ($DisconnectedUserSessions.Count -gt 0) {
                    $DisconnectedUserSessions | ForEach-Object -ThrottleLimit 50 -Parallel {
                        Write-Log "Removing disconnected user session '$($PSItem.UserPrincipalName)'"
                        $PSItem | Remove-AzWvdUserSession -Force -DefaultProfile $HostPoolContext
                    }
                }
            }
        } finally {
            $env:LogPrefix = $Settings.HostPool.Name
        }
    }

    Write-Log "Completed Geekly disconnected users cleanup"
} catch {
    $ErrorScript = $PSItem.InvocationInfo.ScriptName
    $ErrorScriptLine = "$($PSItem.InvocationInfo.ScriptLineNumber):$($PSItem.InvocationInfo.OffsetInLine)"
    $ErrorMessage = "$($PSItem.Exception.Message) Error Script: $ErrorScript, Error Line: $ErrorScriptLine"
    Write-Log $ErrorMessage -Exception $PSItem.Exception -LogLevel 'ERRORSTOP'
}
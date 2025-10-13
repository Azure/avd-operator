param($InputTimer, $TriggerMetadata)

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$InformationPreference = [System.Management.Automation.ActionPreference]::Continue
$WarningPreference = [System.Management.Automation.ActionPreference]::Continue

try {
    $Settings = Get-Settings
    $env:LogPrefix = $Settings.HostPool.Name
    Write-Log "Starting Geekly dynamic target host count function"
    Write-Log "Calculating target session host count based on recent host pool capacity usage"

    $AppConfigurationEndPoint = $env:_AppConfigURI
    $TargetSessionHostCountSettingsKey = 'TargetDynamicSessionHostCount'

    $HostPoolContext = Get-Context -SubscriptionId $Settings.HostPool.SubscriptionId
    $WorkspaceContext = Get-Context -SubscriptionId $Settings.Workspace.SubscriptionId

    # TODO: Ensure DefaultProfile works here because the logs suggest otherwise
    $SessionHostCount = (Get-AzWvdSessionHost -ResourceGroupName $Settings.HostPool.ResourceGroupName -HostPoolName $Settings.HostPool.Name -DefaultProfile $HostPoolContext).Count
    $UserSessionCount = (Get-AzWvdUserSession -ResourceGroupName $Settings.HostPool.ResourceGroupName -HostPoolName $Settings.HostPool.Name -DefaultProfile $HostPoolContext).Count

    if ($SessionHostCount -eq 0 -or $UserSessionCount -eq 0) {
        Write-Log "Found $($SessionHostCount) session hosts and $($UserSessionCount) user sessions."
        $HostPoolName = Switch-Slice -HostPoolName $Settings.HostPool.Name
        Write-Log "Switching to swapped slice for LAW data."

        # TODO: Ensure DefaultProfile works here because the logs suggest otherwise
        $SessionHostCount = (Get-AzWvdSessionHost -ResourceGroupName $Settings.HostPool.ResourceGroupName -HostPoolName $HostPoolName -DefaultProfile $HostPoolContext).Count
        $UserSessionCount = (Get-AzWvdUserSession -ResourceGroupName $Settings.HostPool.ResourceGroupName -HostPoolName $HostPoolName -DefaultProfile $HostPoolContext).Count

        if ($SessionHostCount -eq 0 -and $UserSessionCount -eq 0) {
            Write-Log "Both slices contain $($SessionHostCount) session hosts and $($UserSessionCount) user sessions. Target session host count could not be calculated."
            Write-Log "Completed Geekly dynamic target host count function"
            return
        }
    }

    $wvdQuery = @(
        "let MaxAllowedSessionsPerHost = $($Settings.MaxAllowedSessionsPerHost);"
        "WVDAgentHealthStatus"
        "| where _ResourceId has '$($HostPoolName.toLower())'"
        "| where AllowNewSessions == true and Status == 'Available'"
        "| summarize arg_max(TimeGenerated, *) by SessionHostName, _ResourceId"
        "| summarize PeakSessionsByHost=max(toint(ActiveSessions)) + max(toint(InactiveSessions)) by SessionHostName, _ResourceId"
        "| summarize TotalSessions=sum(PeakSessionsByHost) by _ResourceId"
        "| join kind=inner ("
        "WVDAgentHealthStatus"
        "| where AllowNewSessions == true and Status == 'Available'"
        "| summarize arg_max(TimeGenerated, *) by SessionHostName, _ResourceId"
        "| summarize PeakSessionsByHost=max(toint(ActiveSessions)) + max(toint(InactiveSessions)) by SessionHostName, _ResourceId"
        "| summarize SessionHostCount=count() by _ResourceId"
        "| project"
        "MaxAllowedSessions=SessionHostCount * MaxAllowedSessionsPerHost, _ResourceId"
        ")"
        "on _ResourceId"
        "| project"
        "HostPoolName = toupper(split(_ResourceId, '/')[-1]),"
        "TotalSessions,"
        "MaxAllowedSessions,"
        "AvailableSessionsThreshold = MaxAllowedSessions * 0.85,"
        "_ResourceId"
        "| where TotalSessions > AvailableSessionsThreshold"
    ) | Out-String

    Write-Log "Invoking capacity query on '$($Settings.Workspace.Name)' to determine target host count for host pool."
    # TODO: Ensure DefaultProfile works here because the logs suggest otherwise
    $lawQuery = Invoke-AzOperationalInsightsQuery -WorkspaceId $Settings.WorkspaceIdentifier -Query $wvdQuery -Timespan (New-TimeSpan -Hours 24) -DefaultProfile $WorkspaceContext

    if ($null -ne $lawQuery.Results.Length) {
        $HostPool = $lawQuery.Results

        if ($lawQuery.Results.HostPoolName -notcontains $HostPoolName) {
            Write-Log "Host Pool capacity query returned results, but host pool data was not returned in query."
            return
        }

        $TotalSessions = $HostPool.TotalSessions
        $MaxAllowedSessions = $HostPool.MaxAllowedSessions
        $UsagePercentage = [Math]::Round(($TotalSessions / $MaxAllowedSessions) * 100, 2)

        Write-Log "Current total sessions are $($TotalSessions) with a max allowed sessions limit of $($MaxAllowedSessions), and a usage percentage of $($UsagePercentage)%"

        switch ($UsagePercentage) {
            { $PSItem -ge 0 -and $PSItem -le 39 } {
                Write-Log "Session hosts are being underutilized with a usage percentage of $($UsagePercentage)%"
            }
            { $PSItem -ge 40 -and $PSItem -le 84 } {
                Write-Log "Session host usage is at an acceptable usage percentage of $($UsagePercentage)%."
            }
            { $PSItem -ge 85 } {
                # TODO: Ensure DefaultProfile works here because the logs suggest otherwise
                $SessionHostCount = [Int](Get-AzAppConfigurationKeyValue -Endpoint $AppConfigurationEndPoint -Key $TargetSessionHostCountSettingsKey -DefaultProfile $HostPoolContext).Value
                Write-Log "Current Target Session Host Count from app configuration is $($SessionHostCount)"

                $Buffer = [Math]::Round($SessionHostCount + ($SessionHostCount * $Settings.SessionHostBuffer))
                $BufferPercentage = [Math]::Round((($Buffer - $SessionHostCount) / $SessionHostCount) * 100, 0)

                Write-Log "Calculating new $($BufferPercentage)% buffer to account for user session growth."

                Write-Log "New Target Session Host count with $($BufferPercentage)% buffer : $([Math]::Round($($Buffer) / 5) * 5)"
                Write-Log "$($([Math]::Round(($Buffer) / 5) * 5) - $($SessionHostCount)) new Session Hosts will be deployed."

                $NewMaxAllowedSessions = ($Buffer * 16)
                Write-Log "New Maximum allowed Sessions count with $($BufferPercentage)% buffer : $($NewMaxAllowedSessions)"

                $UsagePercentage = [Math]::Round(($TotalSessions / $NewMaxAllowedSessions) * 100, 2)
                Write-Log "New Host Pool usage percentage with $($BufferPercentage)% buffer : $($UsagePercentage)%"

                Write-Log "Updating Target Host Count in app configuration"
                # TODO: Ensure DefaultProfile works here because the logs suggest otherwise
                Set-AzAppConfigurationKeyValue -Endpoint $AppConfigurationEndPoint -Key $TargetSessionHostCountSettingsKey -Value $TargetHostCount -DefaultProfile $HostPoolContext
            }
        }
    } else {
        Write-Log "Host Pool capacity query returned no results."
    }
    Write-Log "Completed Geekly dynamic target host count function"
} catch {
    $ErrorScript = $PSItem.InvocationInfo.ScriptName
    $ErrorScriptLine = "$($PSItem.InvocationInfo.ScriptLineNumber):$($PSItem.InvocationInfo.OffsetInLine)"
    $ErrorMessage = "$($PSItem.Exception.Message) Error Script: $ErrorScript, Error Line: $ErrorScriptLine"
    Write-Log $ErrorMessage -Exception $PSItem.Exception -LogLevel 'ERRORSTOP'
}

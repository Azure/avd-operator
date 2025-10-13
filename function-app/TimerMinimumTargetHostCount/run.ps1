param($InputTimer, $TriggerMetadata)

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$InformationPreference = [System.Management.Automation.ActionPreference]::Continue
$WarningPreference = [System.Management.Automation.ActionPreference]::Continue

try {
    $Settings = Get-Settings
    $env:LogPrefix = $Settings.HostPool.Name

    Write-Log "Starting Geekly minimum target host count function"
    Write-Log "Calculating minimum target session host count based on average past user session count"

    $AppConfigurationEndPoint = $env:_AppConfigURI
    $TargetSessionHostCountSettingsKey = 'TargetMinimumSessionHostCount'

    $HostPoolContext = Get-Context -SubscriptionId $Settings.HostPool.SubscriptionId
    $WorkspaceContext = Get-Context -SubscriptionId $Settings.Workspace.SubscriptionId

    if ($Settings.HostPool.Name -match "INT|PLT|BRD") {
        $OppositeSliceHostPoolName = Switch-Slice -HostPoolName $Settings.HostPool.Name
        Write-Log "Switching to swapped slice for LAW data."
    } else {
        $OppositeSliceHostPoolName = ''
    }

    $wvdQuery = @(
        "let HostPoolName = '$($Settings.HostPool.Name.toLower())';"
        "let OppositeSliceHostPoolName = '$($OppositeSliceHostPoolName.toLower())';"
        "WVDAgentHealthStatus"
        "| where TimeGenerated >=  startofday(ago(30d))"
        "| where _ResourceId has HostPoolName or (OppositeSliceHostPoolName != '' and _ResourceId has OppositeSliceHostPoolName)"
        "| summarize TotalSessionsPerHost = max(toint(ActiveSessions) + toint(InactiveSessions)) by bin(TimeGenerated, 1d), SessionHostName"
        "| summarize DailyTotalSessions = sum(TotalSessionsPerHost) by TimeGenerated"
        "| summarize TotalSessions = sum(DailyTotalSessions), AvgSessionsPerDay  = toint(avg(DailyTotalSessions))"
    ) | Out-String

    Write-Log "Invoking query on '$($Settings.Workspace.Name)' to determine the minimum target session host count based on past user session data."
    # TODO: Ensure DefaultProfile works here because the logs suggest otherwise
    $lawQuery = Invoke-AzOperationalInsightsQuery -WorkspaceId $Settings.WorkspaceIdentifier -Query $wvdQuery -DefaultProfile $WorkspaceContext

    $AvgSessionsPerDay = [Int]$lawQuery.Results.AvgSessionsPerDay
    if ($AvgSessionsPerDay -lt 16) {
        $TargetHostCount = 1
    } else {
        $TargetHostCount = [Int][Math]::Round($AvgSessionsPerDay / 16)
    }

    if ($TargetHostCount -gt 2) {
        #Anything less than 2 will be rounded down to zero without this check
        $TargetHostCount = [Math]::Round($($TargetHostCount) / 5) * 5
    }

    $buffer = $($TargetHostCount + [Int]($TargetHostCount * $Settings.SessionHostBuffer))
    $BufferPercentage = [Math]::Round((($Buffer - $TargetHostCount) / $TargetHostCount) * 100)
    # TODO: Ensure DefaultProfile works here because the logs suggest otherwise
    $CurrentTargetHostCount = [Int](Get-AzAppConfigurationKeyValue -Endpoint $AppConfigurationEndPoint -Key $TargetSessionHostCountSettingsKey -DefaultProfile $HostPoolContext).Value
    Write-Log "Average Sessions per day for the last 30 days was $($AvgSessionsPerDay)"
    Write-Log "Current Target host count from app configuration is $($CurrentTargetHostCount)"
    Write-Log "New minimum target count without $($BufferPercentage)% buffer : $($TargetHostCount)"
    Write-Log "New minimum target count with $($BufferPercentage)% buffer : $($buffer)"

    if ($TargetHostCount -eq $CurrentTargetHostCount) {
        Write-Log "New minimum target count is the same as the current target host count found in app configuration."
    } else {
        Write-Log "Updating the target host count to $($TargetHostCount) in app configuration."
        # TODO: Ensure DefaultProfile works here because the logs suggest otherwise
        Set-AzAppConfigurationKeyValue -Endpoint $AppConfigurationEndPoint -Key $TargetSessionHostCountSettingsKey -Value $TargetHostCount -DefaultProfile $HostPoolContext
    }
    Write-Log "Completed Geekly minimum target host count function"
} catch {
    $ErrorScript = $PSItem.InvocationInfo.ScriptName
    $ErrorScriptLine = "$($PSItem.InvocationInfo.ScriptLineNumber):$($PSItem.InvocationInfo.OffsetInLine)"
    $ErrorMessage = "$($PSItem.Exception.Message) Error Script: $ErrorScript, Error Line: $ErrorScriptLine"
    Write-Log $ErrorMessage -Exception $PSItem.Exception -LogLevel 'ERRORSTOP'
}
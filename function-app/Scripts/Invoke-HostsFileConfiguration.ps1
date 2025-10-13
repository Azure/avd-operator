[Cmdletbinding()]
param()

# All errors are terminating errors
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$InformationPreference = [System.Management.Automation.ActionPreference]::Continue
$WarningPreference = [System.Management.Automation.ActionPreference]::Continue

$ScriptName = "Hosts File Configuration"

try {
    $LogFileName = $ScriptName -replace "\s+", "-"
    $LogFilePath = Join-Path -Path $env:windir -ChildPath "Logs\run-cmd-${LogFileName}.log"
    Start-Transcript -Path $LogFilePath -Append -Force
    Write-Output "Starting $ScriptName Script - $(Get-Date -Format "yyyyMMdd-HH:mm")"
    Write-Output "PowerShell Language Mode: $($ExecutionContext.SessionState.LanguageMode)"

    ###

    ##########################
    ## Configure Hosts File ##
    ##########################

    try {
        Write-Output "Attempting to configure hosts file"

        $HostEntries = @(
            @{
                IPAddress = "52.127.58.160"
                FQDN      = "power-apis-usdod-001.azure-apihub.us"
            }
        )

        $HostsFilePath = Join-Path -Path $env:windir -ChildPath "System32\drivers\etc\hosts"
        $UTCDateTime = Get-Date (Get-Date).ToUniversalTime() -UFormat '+%Y%m%dT%H%MZ'
        $HostsFilePath = "$env:windir\System32\drivers\etc\hosts"
        $BackupHostsFilePath = "${HostsFilePath}.${UTCDateTime}.bak"
        Move-Item -Path $HostsFilePath -Destination $BackupHostsFilePath -Force

        foreach ($HostEntry in $HostEntries) {
            $HostEntry = "$($HostEntry.IPAddress.Trim()) $($HostEntry.FQDN.Trim())"
            Write-Output "Adding entry '$HostEntry' to host file"
            $HostEntry | Tee-Object -FilePath $HostsFilePath -Append
        }

        Write-Output "Completed configuration of hosts file"
    } catch {
        Write-Warning "Failed to configure hosts file"
        Write-Error -Message $PSItem.Exception.Message -Exception $PSItem.Exception -ErrorAction Stop
    }

    ###

    Write-Output "Completed $ScriptName Script - $(Get-Date -Format "yyyyMMdd-HH:mm")"
} finally {
    Stop-Transcript -ErrorAction SilentlyContinue
}

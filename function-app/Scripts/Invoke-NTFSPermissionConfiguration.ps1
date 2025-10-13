[Cmdletbinding()]
param()

# All errors are terminating errors
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$InformationPreference = [System.Management.Automation.ActionPreference]::Continue
$WarningPreference = [System.Management.Automation.ActionPreference]::Continue

$ScriptName = "NTFS Permission Configuration"

try {
    $LogFileName = $ScriptName -replace "\s+", "-"
    $LogFilePath = Join-Path -Path $env:windir -ChildPath "Logs\run-cmd-${LogFileName}.log"
    Start-Transcript -Path $LogFilePath -Append -Force
    Write-Output "Starting $ScriptName Script - $(Get-Date -Format "yyyyMMdd-HH:mm")"
    Write-Output "PowerShell Language Mode: $($ExecutionContext.SessionState.LanguageMode)"

    ###

    ################################
    ## Configure NTFS Permissions ##
    ################################

    try {
        Write-Output "Attempting to configure NTFS permissions"

        Write-Output "Configuring NTFS permissions on 'C:\users\Public'"
        icacls ("C:\users\Public") /reset
        icacls ("C:\users\Public") /grant ("SYSTEM" + ":(OI)(CI)F")
        icacls ("C:\users\Public") /grant ("administrators" + ":(OI)(CI)F")

        Write-Output "Completed configuration of NTFS permissions"
    } catch {
        Write-Warning "Failed to configure NTFS permissions"
        Write-Error -Message $PSItem.Exception.Message -Exception $PSItem.Exception -ErrorAction Stop
    }

    ###

    Write-Output "Completed $ScriptName Script - $(Get-Date -Format "yyyyMMdd-HH:mm")"
} finally {
    Stop-Transcript -ErrorAction SilentlyContinue
}

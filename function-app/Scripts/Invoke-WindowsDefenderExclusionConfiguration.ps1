[CmdletBinding()]
param()

# All errors are terminating errors
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$InformationPreference = [System.Management.Automation.ActionPreference]::Continue
$WarningPreference = [System.Management.Automation.ActionPreference]::Continue

$ScriptName = "Windows Defender Exclusion Configuration"

try {
    $LogFileName = $ScriptName -replace "\s+", "-"
    $LogFilePath = Join-Path -Path $env:windir -ChildPath "Logs\run-cmd-${LogFileName}.log"
    Start-Transcript -Path $LogFilePath -Append -Force
    Write-Output "Starting $ScriptName Script - $(Get-Date -Format "yyyyMMdd-HH:mm")"
    Write-Output "PowerShell Language Mode: $($ExecutionContext.SessionState.LanguageMode)"

    ###

    ##########################################
    ## Configure Windows Defender Exclusion ##
    ##########################################

    try {
        Write-Output "Attempting to configure Windows Defender Exclusion"

        # Add-MpPreference -ExclusionPath "%ProgramData%\Tychon\*"
        # Add-MpPreference -ExclusionPath "%ProgramFiles%\Tychon\*"
        # Add-MpPreference -ExclusionPath "%ProgramFiles(x86)%\Tychon\*"

        Write-Output "Completed configuration of Windows Defender Exclusion"
    } catch {
        Write-Warning "Failed to configure Windows Defender Exclusion"
        Write-Error -Message $PSItem.Exception.Message -Exception $PSItem.Exception -ErrorAction Stop
    }

    ###

    Write-Output "Completed $ScriptName Script - $(Get-Date -Format "yyyyMMdd-HH:mm")"
} finally {
    Stop-Transcript -ErrorAction SilentlyContinue
}

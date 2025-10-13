[CmdletBinding()]
param()

# All errors are terminating errors
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$InformationPreference = [System.Management.Automation.ActionPreference]::Continue
$WarningPreference = [System.Management.Automation.ActionPreference]::Continue

$ScriptName = "Virtual Desktop Optimization Tool"

try {
    $LogFileName = $ScriptName -replace "\s+", "-"
    $LogFilePath = Join-Path -Path $env:windir -ChildPath "Logs\run-cmd-${LogFileName}.log"
    Start-Transcript -Path $LogFilePath -Append -Force
    Write-Output "Starting $ScriptName Script - $(Get-Date -Format "yyyyMMdd-HH:mm")"
    Write-Output "PowerShell Language Mode: $($ExecutionContext.SessionState.LanguageMode)"

    ###

    ###########################################
    ## Run Virtual Desktop Optimization Tool ##
    ###########################################

    try {
        $VdotDirectoryPath = "C:\virtual-desktop-optimization-tool\"
        $VdotScript = Get-ChildItem -Path $VdotDirectoryPath -Recurse -File -Filter "Windows_VDOT.ps1" -ErrorAction SilentlyContinue
        if ($null -ne $VdotScript) {
            Write-Output "Starting virtual desktop optimization tool"
            & $VdotScript.FullName -Optimizations "All" -AdvancedOptimizations "Edge" -AcceptEULA
            Write-Output "Completed virtual desktop optimization tool"

            Start-Sleep -Seconds 5
            Write-Output "Attempting cleanup of virtual desktop optimization tool"
            Remove-Item -Path $VdotDirectoryPath -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Write-Warning "Virtual desktop optimization tool was not found at '$VdotDirectoryPath'"
        }
    } catch {
        Write-Warning "Failed to run virtual desktop optimization tool"
        Write-Error -Message $PSItem.Exception.Message -Exception $PSItem.Exception -ErrorAction Stop
    }

    ###

    Write-Output "Completed $ScriptName Script - $(Get-Date -Format "yyyyMMdd-HH:mm")"
} finally {
    Stop-Transcript -ErrorAction SilentlyContinue
}

[CmdletBinding()]
param()

# All errors are terminating errors
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$InformationPreference = [System.Management.Automation.ActionPreference]::Continue
$WarningPreference = [System.Management.Automation.ActionPreference]::Continue

$ScriptName = "Registry Configuration"

try {
    $LogFileName = $ScriptName -replace "\s+", "-"
    $LogFilePath = Join-Path -Path $env:windir -ChildPath "Logs\run-cmd-${LogFileName}.log"
    Start-Transcript -Path $LogFilePath -Append -Force
    Write-Output "Starting $ScriptName Script - $(Get-Date -Format "yyyyMMdd-HH:mm")"
    Write-Output "PowerShell Language Mode: $($ExecutionContext.SessionState.LanguageMode)"

    ###

    ########################
    ## Configure Registry ##
    ########################

    try {
        Write-Output "Attempting to configure registry"

        $RegistryKeys = @{
            # "OneDrive" = @{
            #     Path          = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
            #     PropertyValue = '"C:\Program Files\Microsoft OneDrive\OneDrive.exe" /background'
            #     PropertyType  = "String"
            # }
        }

        Write-Output "Configuring registry"
        foreach ($RegistryKey in $RegistryKeys.GetEnumerator()) {
            Write-Output "Configuring registry with key: $($RegistryKey.Name), path: $($RegistryKey.Value.Path), value: $($RegistryKey.Value.PropertyValue)"
            if (-not (Test-Path $RegistryKey.Value.Path)) {
                New-Item -Path $RegistryKey.Value.Path -Force | Out-Null
            }

            New-ItemProperty `
                -Path $RegistryKey.Value.Path `
                -Name $RegistryKey.Name `
                -Value $RegistryKey.Value.PropertyValue `
                -PropertyType $RegistryKey.Value.PropertyType `
                -Force | Out-Null
        }

        Write-Output "Completed configuration of registry"
    } catch {
        Write-Warning "Failed to configure registry"
        Write-Error -Message $PSItem.Exception.Message -Exception $PSItem.Exception -ErrorAction Stop
    }

    ###

    Write-Output "Completed $ScriptName Script - $(Get-Date -Format "yyyyMMdd-HH:mm")"
} finally {
    Stop-Transcript -ErrorAction SilentlyContinue
}

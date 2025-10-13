[Cmdletbinding()]
param(
    [parameter(Mandatory)]
    [String] $FSLogixStorageAccountName
)

# All errors are terminating errors
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$InformationPreference = [System.Management.Automation.ActionPreference]::Continue
$WarningPreference = [System.Management.Automation.ActionPreference]::Continue

$ScriptName = "FSLogix Configuration"

try {
    $LogFileName = $ScriptName -replace "\s+", "-"
    $LogFilePath = Join-Path -Path $env:windir -ChildPath "Logs\run-cmd-${LogFileName}.log"
    Start-Transcript -Path $LogFilePath -Append -Force
    Write-Output "Starting $ScriptName Script - $(Get-Date -Format "yyyyMMdd-HH:mm")"
    Write-Output "PowerShell Language Mode: $($ExecutionContext.SessionState.LanguageMode)"

    ###

    ####################################
    ## Configure FSLogix Local Groups ##
    ####################################

    try {
        Write-Output "Attempting to configure FSLogix local groups"

        $FSLogixLocalAdministratorsGroupName = "Administrators"
        $FSLogixLocalAdministratorsUserName = "localadmin"
        $FSLogixLocalAdministratorsUserFullName = "${env:COMPUTERNAME}\${FSLogixLocalAdministratorsUserName}"
        $FSLogixLocalAdministratorsGroupFullName = "BUILTIN\${FSLogixLocalAdministratorsGroupName}"
        $FSLogixODFCExcludeGroupName = "FSLogix ODFC Exclude List"
        $FSLogixProfileExcludeGroupName = "FSLogix Profile Exclude List"

        Write-Output "Configure FSLogix local group membership"

        $FslogixProfileExcludeGroupMembers = Get-LocalGroupMember -Name $FSLogixProfileExcludeGroupName
        if ($FslogixProfileExcludeGroupMembers.Name -inotcontains $FSLogixLocalAdministratorsGroupFullName) {
            Write-Output "Excluding local group '$FSLogixLocalAdministratorsGroupName' from local group '$FSLogixProfileExcludeGroupName'"
            Add-LocalGroupMember -Group $FSLogixProfileExcludeGroupName -Member $FSLogixLocalAdministratorsGroupFullName | Out-Null
        }

        $FslogixODFCExcludeGroupMembers = Get-LocalGroupMember -Name $FSLogixODFCExcludeGroupName
        if ($FslogixODFCExcludeGroupMembers.Name -inotcontains $FSLogixLocalAdministratorsGroupFullName) {
            Write-Output "Excluding local group '$FSLogixLocalAdministratorsGroupName' from local group '$FSLogixODFCExcludeGroupName'"
            Add-LocalGroupMember -Group $FSLogixODFCExcludeGroupName -Member $FSLogixLocalAdministratorsGroupFullName | Out-Null
        }

        $FslogixProfileExcludeGroupMembers = Get-LocalGroupMember -Name $FSLogixProfileExcludeGroupName
        if ($FslogixProfileExcludeGroupMembers.Name -inotcontains $FSLogixLocalAdministratorsUserFullName) {
            Write-Output "Excluding local user '$FSLogixLocalAdministratorsUserName' from local group '$FSLogixProfileExcludeGroupName'"
            Add-LocalGroupMember -Group $FSLogixProfileExcludeGroupName -Member $FSLogixLocalAdministratorsUserFullName | Out-Null
        }

        $FslogixODFCExcludeGroupMembers = Get-LocalGroupMember -Name $FSLogixODFCExcludeGroupName
        if ($FslogixODFCExcludeGroupMembers.Name -inotcontains $FSLogixLocalAdministratorsUserFullName) {
            Write-Output "Excluding local user '$FSLogixLocalAdministratorsUserName' from local group '$FSLogixODFCExcludeGroupName'"
            Add-LocalGroupMember -Group $FSLogixODFCExcludeGroupName -Member $FSLogixLocalAdministratorsUserFullName | Out-Null
        }

        Write-Output "Completed configuration of FSLogix local groups"
    } catch {
        Write-Warning "Failed to configure FSLogix local groups"
        Write-Error -Message $PSItem.Exception.Message -Exception $PSItem.Exception -ErrorAction Stop
    }

    ################################
    ## Configure FSLogix Registry ##
    ################################

    try {
        Write-Output "Attempting to configure FSLogix registry"

        $FSLogixStorageAccountShareEndpoint = "\\${FSLogixStorageAccountName}.file.core.usgovcloudapi.net\profiles"
        $RegistryKeys = @{
            "CloudKerberosTicketRetrievalEnabled"  = @{
                Path          = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters"
                PropertyValue = 1
                PropertyType  = "DWORD"
            }
            "LoadCredKeyFromProfile"               = @{
                Path          = "HKLM:\Software\Policies\Microsoft\AzureADAccount"
                PropertyValue = 1
                PropertyType  = "DWORD"
            }
            "fEnableTimeZoneRedirection"           = @{
                Path          = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"
                PropertyValue = 1
                PropertyType  = "DWORD"
            }
            "DeleteLocalProfileWhenVHDShouldApply" = @{
                Path          = "HKLM:\SOFTWARE\FSLogix\Profiles"
                PropertyValue = 1
                PropertyType  = "DWORD"
            }
            "Enabled"                              = @{
                Path          = "HKLM:\SOFTWARE\FSLogix\Profiles"
                PropertyValue = 1
                PropertyType  = "DWORD"
            }
            "FlipFlopProfileDirectoryName"         = @{
                Path          = "HKLM:\SOFTWARE\FSLogix\Profiles"
                PropertyValue = 1
                PropertyType  = "DWORD"
            }
            "InstallAppxPackages"                  = @{
                Path          = "HKLM:\SOFTWARE\FSLogix\Profiles"
                PropertyValue = 0
                PropertyType  = "DWORD"
            }
            "PreventLoginWithFailure"              = @{
                Path          = "HKLM:\SOFTWARE\FSLogix\Profiles"
                PropertyValue = 1
                PropertyType  = "DWORD"
            }
            "PreventLoginWithTempProfile"          = @{
                Path          = "HKLM:\SOFTWARE\FSLogix\Profiles"
                PropertyValue = 1
                PropertyType  = "DWORD"
            }
            "RemoveOrphanedOSTFilesOnLogoff"       = @{
                Path          = "HKLM:\SOFTWARE\FSLogix\Profiles"
                PropertyValue = 1
                PropertyType  = "DWORD"
            }
            "ClearCacheOnLogoff"                   = @{
                Path          = "HKLM:\Software\Policies\FSLogix\ODFC"
                PropertyValue = 1
                PropertyType  = "DWORD"
            }
            "VHDXSectorSize"                       = @{
                Path          = "HKLM:\SOFTWARE\FSLogix\Profiles"
                PropertyValue = 4096
                PropertyType  = "DWORD"
            }
            "VolumeType"                           = @{
                Path          = "HKLM:\SOFTWARE\FSLogix\Profiles"
                PropertyValue = "vhdx"
                PropertyType  = "String"
            }
            "VHDLocations"                         = @{
                Path          = "HKLM:\SOFTWARE\FSLogix\Profiles"
                PropertyValue = $FSLogixStorageAccountShareEndpoint
                PropertyType  = "MultiString"
            }
            "IgnoreNonWVD"                         = @{
                Path          = "HKLM:\SOFTWARE\FSLogix\Profiles"
                PropertyValue = 1
                PropertyType  = "DWORD"
            }
            "RoamRecycleBin"                         = @{
                Path          = "HKLM:\SOFTWARE\FSLogix\Apps"
                PropertyValue = 0
                PropertyType  = "DWORD"
            }
            "RoamIdentity"                         = @{
                Path          = "HKLM:\SOFTWARE\FSLogix\Profiles"
                PropertyValue = 1
                PropertyType  = "DWORD"
            }
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

        Write-Output "Completed configuration of FSLogix registry"
    } catch {
        Write-Warning "Failed to configure FSLogix registry"
        Write-Error -Message $PSItem.Exception.Message -Exception $PSItem.Exception -ErrorAction Stop
    }

    ##############################################
    ## Configure FSLogix Redirection Exemptions ##
    ##############################################

    try {
        Write-Output "Attempting to configure of FSLogix redirection exemptions"

        $FSLogixDirectoryPath = "C:\Program Files\FSLogix"
        New-Item -Path "${FSLogixDirectoryPath}\RedirXMLSourceFolder\Redirections.xml" -ItemType File -Force -Value '
<?xml version="1.0" encoding="UTF-8"?>

<FrxProfileFolderRedirection ExcludeCommonFolders="0">

<Excludes>
    <Exclude Copy="0">AppData\Local\BraveSoftware\Brave-Browser\User Data\Default\Cache</Exclude>
    <Exclude Copy="0">AppData\Local\CrashDumps</Exclude>
    <Exclude Copy="0">AppData\Local\Downloaded Installations</Exclude>
    <Exclude Copy="0">AppData\Local\Google\Chrome\User Data\Default\Cache</Exclude>
    <Exclude Copy="0">AppData\Local\Google\Chrome\User Data\Default\Cached Theme Image</Exclude>
    <Exclude Copy="0">AppData\Local\Google\Chrome\User Data\Default\GPUCache</Exclude>
    <Exclude Copy="0">AppData\Local\Google\Chrome\User Data\Default\JumpListIcons</Exclude>
    <Exclude Copy="0">AppData\Local\Google\Chrome\User Data\Default\JumpListIconsOld</Exclude>
    <Exclude Copy="0">AppData\Local\Google\Chrome\User Data\Default\Local Storage</Exclude>
    <Exclude Copy="0">AppData\Local\Google\Chrome\User Data\Default\Media Cache</Exclude>
    <Exclude Copy="0">AppData\Local\Google\Chrome\User Data\Default\Pepper Data\Shockwave Flash\CacheWriteableAdobeRoot</Exclude>
    <Exclude Copy="0">AppData\Local\Google\Chrome\User Data\Default\SessionStorage</Exclude>
    <Exclude Copy="0">AppData\Local\Google\Chrome\User Data\Default\Storage</Exclude>
    <Exclude Copy="0">AppData\Local\Google\Chrome\User Data\Default\SyncData</Exclude>
    <Exclude Copy="0">AppData\Local\Google\Chrome\User Data\Default\SyncDataBackup</Exclude>
    <Exclude Copy="0">AppData\Local\Google\Chrome\User Data\Default\WebApplications</Exclude>
    <Exclude Copy="0">AppData\Local\Google\Chrome\User Data\EVWhitelist</Exclude>
    <Exclude Copy="0">AppData\Local\Google\Chrome\User Data\PepperFlash</Exclude>
    <Exclude Copy="0">AppData\Local\Google\Chrome\User Data\pnacl</Exclude>
    <Exclude Copy="0">AppData\Local\Google\Chrome\User Data\recovery</Exclude>
    <Exclude Copy="0">AppData\Local\Google\Chrome\User Data\ShaderCache</Exclude>
    <Exclude Copy="0">AppData\Local\Google\Chrome\User Data\SwiftShader</Exclude>
    <Exclude Copy="0">AppData\Local\Google\Chrome\User Data\SwReporter</Exclude>
    <Exclude Copy="0">AppData\Local\Google\Chrome\User Data\WidevineCDM</Exclude>
    <Exclude Copy="0">AppData\Local\Microsoft\Edge\User Data\Default\Cache</Exclude>
    <Exclude Copy="0">AppData\Local\Microsoft\MSOIdentityCRL\Tracing</Exclude>
    <Exclude Copy="0">AppData\Local\Microsoft\Office\16.0\Lync\Tracing</Exclude>
    <Exclude Copy="0">AppData\Local\Microsoft\OneNote\16.0\Backup</Exclude>
    <Exclude Copy="0">AppData\Local\Microsoft\Terminal Server Client\Cache</Exclude>
    <Exclude Copy="0">AppData\Local\Microsoft\Windows\WER</Exclude>
    <Exclude Copy="0">AppData\Local\Packages\Microsoft.MicrosoftEdge_8wekyb3d8bbwe\AC\MicrosoftEdge\Cache</Exclude>
    <Exclude Copy="0">AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\WV2Profile_dod\GPUCache</Exclude>
    <Exclude Copy="0">AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\WV2Profile_dod\WebStorage</Exclude>
    <Exclude Copy="0">AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\WV2Profile_tfw\GPUCache</Exclude>
    <Exclude Copy="0">AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\WV2Profile_tfw\WebStorage</Exclude>
    <Exclude Copy="0">AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\Logs</Exclude>
    <Exclude Copy="0">AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\PerfLog</Exclude>
    <Exclude Copy="0">AppData\Local\SquirrelTemp</Exclude>
    <Exclude Copy="0">AppData\Roaming\Downloaded Installations</Exclude>
</Excludes>

<Includes>
    <Include Copy="3">AppData\LocalLow\Sun\Java\Deployment\security</Include>
</Includes>

</FrxProfileFolderRedirection>'

        Set-ItemProperty -Path "HKLM:\SOFTWARE\FSLogix\Profiles" -Name "RedirXMLSourceFolder" -Value "${FSLogixDirectoryPath}\RedirXMLSourceFolder" -Force

        Write-Output "Completed configuration of FSLogix redirection exemptions"
    } catch {
        Write-Warning "Failed to configure of FSLogix redirection exemptions"
        Write-Error -Message $PSItem.Exception.Message -Exception $PSItem.Exception -ErrorAction Stop
    }

    ###################################################
    ## Configure FSLogix Windows Defender Exclusions ##
    ###################################################

    try {
        Write-Output "Attempting to configure FSLogix Windows Defender exclusions"

        Add-MpPreference -ExclusionPath "%ProgramData%\FSLogix\Cache\*.VHD"
        Add-MpPreference -ExclusionPath "%ProgramData%\FSLogix\Cache\*.VHDX"
        Add-MpPreference -ExclusionPath "%ProgramData%\FSLogix\Proxy\*.VHD"
        Add-MpPreference -ExclusionPath "%ProgramData%\FSLogix\Proxy\*.VHDX"
        Add-MpPreference -ExclusionPath "%ProgramFiles%\FSLogix\Apps\frxccd.sys"
        Add-MpPreference -ExclusionPath "%ProgramFiles%\FSLogix\Apps\frxdrv.sys"
        Add-MpPreference -ExclusionPath "%ProgramFiles%\FSLogix\Apps\frxdrvvt.sys"
        Add-MpPreference -ExclusionPath "%TEMP%\*.VHD"
        Add-MpPreference -ExclusionPath "%TEMP%\*.VHDX"
        Add-MpPreference -ExclusionPath "%Windir%\TEMP\*.VHD"
        Add-MpPreference -ExclusionPath "%Windir%\TEMP\*.VHDX"
        Add-MpPreference -ExclusionPath "C:\Program Files\FSLogix\**.VHD"
        Add-MpPreference -ExclusionPath "C:\Program Files\FSLogix\**.VHDX"
        Add-MpPreference -ExclusionProcess "%ProgramFiles%\FSLogix\Apps\frxccd.exe"
        Add-MpPreference -ExclusionProcess "%ProgramFiles%\FSLogix\Apps\frxccds.exe"
        Add-MpPreference -ExclusionProcess "%ProgramFiles%\FSLogix\Apps\frxsvc.exe"

        Write-Output "Completed configuration of FSLogix Windows Defender exclusions"
    } catch {
        Write-Warning "Failed to configure FSLogix Windows Defender exclusions"
        Write-Error -Message $PSItem.Exception.Message -Exception $PSItem.Exception -ErrorAction Stop
    }

    ###

    Write-Output "Completed $ScriptName Script - $(Get-Date -Format "yyyyMMdd-HH:mm")"
} finally {
    Stop-Transcript -ErrorAction SilentlyContinue
}

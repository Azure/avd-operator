[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [String] $HostPoolName,

    [Parameter(Mandatory)]
    [String] $RegistrationToken,

    [Parameter(Mandatory)]
    [String] $RemoteDesktopAgentUri,

    [Parameter(Mandatory)]
    [String] $RemoteDesktopAgentBootLoaderUri,

    [Parameter()]
    [String] $RemoteDesktopAgentBootLoaderFileName = "Microsoft.RDInfra.RDAgentBootLoader.Installer-x64.msi",

    [Parameter()]
    [String] $RemoteDesktopAgentFileName = "Microsoft.RDInfra.RDAgent.Installer-x64.msi",

    [Parameter()]
    [String] $RemoteDesktopAgentRegistryPath = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\RDInfraAgent",

    [Parameter()]
    [ValidateSet("False", "True")]
    [String] $Reregister = "False"
)

function Invoke-HostPoolRegistrationValidation {
    [OutputType()]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String] $RemoteDesktopAgentRegistryPath
    )

    $RemoteDesktopInfrastructureAgentRegistry = Get-ItemProperty -Path $RemoteDesktopAgentRegistryPath -ErrorAction SilentlyContinue
    if ($null -eq $RemoteDesktopInfrastructureAgentRegistry) {
        return @{
            Status  = $false
            Message = "Expected to find registry keys under path '${RemoteDesktopAgentRegistryPath}' but found null"
        }
    } else {
        switch ($RemoteDesktopInfrastructureAgentRegistry.RegistrationToken) {
            "INVALID_TOKEN" {
                # may not be valid syntax, but not expired either, possibly not a real token

                return @{
                    Status  = $false
                    Message = "Remote desktop agent registration token may have a syntax error, found registry key 'RegistrationToken' set to 'INVALID_TOKEN', current registration token is '${RegistrationToken}'"
                }
            }

            { (-not ([String]::IsNullOrWhiteSpace($PSItem))) } {
                # possibly expired token or previous registration attempt failed early

                return @{
                    Status  = $false
                    Message = "Remote desktop agent registration may have failed previously or was given an expired token, found registry key 'RegistrationToken' set to '$($RemoteDesktopInfrastructureAgentRegistry.RegistrationToken)' but it should be empty for a new registration or a previously successful registration"
                }
            }

            { ([String]::IsNullOrWhiteSpace($PSItem)) } {
                # If registry key 'RegistrationToken' is empty then the host has never
                # been registered before or the previous registration was successful

                switch ($RemoteDesktopInfrastructureAgentRegistry.IsRegistered) {
                    0 {
                        return @{
                            Status  = $false
                            Message = "Remote desktop agent is not registered, found registry key 'IsRegistered' set to 0"
                        }
                    }

                    1 {
                        return @{
                            Status = $true
                        }
                    }

                    default {
                        # Catching default to handle unknown values of registry key 'IsRegistered'

                        return @{
                            Status  = $false
                            Message = "Remote desktop agent registration status unknown, found registry key 'IsRegistered' set to '$($RemoteDesktopInfrastructureAgentRegistry.IsRegistered)'"
                        }
                    }
                }
            }

            default {
                # Catching default to handle unknown values of registry key 'RegistrationToken'

                return @{
                    Status  = $false
                    Message = "Remote desktop agent registration status unknown, found registry key 'RegistrationToken' set to '$($RemoteDesktopInfrastructureAgentRegistry.RegistrationToken)'"
                }
            }
        }
    }
}

function Invoke-InstallRemoteDesktopAgent {
    [OutputType()]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String] $HostPoolName,

        [Parameter(Mandatory)]
        [String] $RegistrationToken,

        [Parameter(Mandatory)]
        [String] $RemoteDesktopAgentBootLoaderFileName,

        [Parameter(Mandatory)]
        [String] $RemoteDesktopAgentFileName,

        [Parameter(Mandatory)]
        [String] $RemoteDesktopAgentUri,

        [Parameter(Mandatory)]
        [String] $RemoteDesktopAgentBootLoaderUri,

        [Parameter(Mandatory)]
        [String] $RemoteDesktopAgentRegistryPath
    )

    Write-Output "Installing remote desktop agent to allow registration to host pool '${HostPoolName}'"

    Write-Output "Downloading remote desktop agent file '${RemoteDesktopAgentFileName}'"
    $RemoteDesktopAgentFilePath = Join-Path -Path $env:temp -ChildPath $RemoteDesktopAgentFileName
    Invoke-WebRequest -Uri $RemoteDesktopAgentUri -OutFile $RemoteDesktopAgentFilePath
    if (-not (Test-Path $RemoteDesktopAgentFilePath)) {
        throw "Failed to find remote desktop agent file '${RemoteDesktopAgentFilePath}'"
    }

    Write-Output "Downloading remote desktop agent boot loader file '${RemoteDesktopAgentBootLoaderFileName}'"
    $RemoteDesktopAgentBootLoaderFilePath = Join-Path -Path $env:temp -ChildPath $RemoteDesktopAgentBootLoaderFileName
    Invoke-WebRequest -Uri $RemoteDesktopAgentBootLoaderUri -OutFile $RemoteDesktopAgentBootLoaderFilePath
    if (-not (Test-Path $RemoteDesktopAgentBootLoaderFilePath)) {
        throw "Failed to find remote desktop agent boot loader file '${RemoteDesktopAgentBootLoaderFilePath}'"
    }

    $RemoteDesktopAgentInstallArgumentList = "/i ${RemoteDesktopAgentFilePath} /qn /norestart REGISTRATIONTOKEN=${RegistrationToken}"
    $RemoteDesktopAgentInstall = Start-Process msiexec -ArgumentList $RemoteDesktopAgentInstallArgumentList -Wait -PassThru
    if ($RemoteDesktopAgentInstall.exitcode -eq 0) {
        Write-Output "Successfully installed remote desktop agent with registration token for host pool '${HostPoolName}'"
    } elseif ($RemoteDesktopAgentInstall.exitcode -eq 3010) {
        Write-Output "Successfully installed remote desktop agent with registration token for host pool '${HostPoolName}', reboot required to complete installation"
    } else {
        Write-Output "Exit Code Reference: https://learn.microsoft.com/en-us/windows/win32/msi/error-codes?redirectedfrom=MSDN"
        throw "Remote desktop agent failed to install, exit code: $($RemoteDesktopAgentInstall.exitcode)"
    }
    Start-Sleep -Seconds 5

    $RemoteDesktopAgentBootLoaderInstallArgumentList = "/i ${RemoteDesktopAgentBootLoaderFilePath} /qn /norestart"
    $RemoteDesktopAgentBootLoaderInstall = Start-Process msiexec -ArgumentList $RemoteDesktopAgentBootLoaderInstallArgumentList -Wait -PassThru
    if ($RemoteDesktopAgentBootLoaderInstall.exitcode -eq 0) {
        Write-Output "Successfully installed remote desktop agent boot loader for host pool '${HostPoolName}'"
    } elseif ($RemoteDesktopAgentBootLoaderInstall.exitcode -eq 3010) {
        Write-Output "Successfully installed remote desktop agent boot loader for host pool '${HostPoolName}', reboot required to complete installation"
    } else {
        Write-Output "Exit Code Reference: https://learn.microsoft.com/en-us/windows/win32/msi/error-codes?redirectedfrom=MSDN"
        throw "Remote desktop agent boot loader failed to install, exit code: $($RemoteDesktopAgentBootLoaderInstall.exitcode)"
    }
    Start-Sleep -Seconds 5
}

function Invoke-HostPoolRegistrationReregistration {
    [OutputType()]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String] $HostPoolName,

        [Parameter(Mandatory)]
        [String] $RegistrationToken,

        [Parameter(Mandatory)]
        [String] $RemoteDesktopAgentRegistryPath
    )

    Write-Output "Attempting to re-register remote desktop agent to host pool '${HostPoolName}'"

    Set-ItemProperty -Path $RemoteDesktopAgentRegistryPath -Name "RegistrationToken" -Value "$($RegistrationToken)" -Force
    Set-ItemProperty -Path $RemoteDesktopAgentRegistryPath -Name "IsRegistered" -Value 0 -Force
    Restart-Service -Name "RDAgentBootLoader"
    Start-Sleep -Seconds 5

    $HostPoolRegistrationValidation = Invoke-HostPoolRegistrationValidation -RemoteDesktopAgentRegistryPath $RemoteDesktopAgentRegistryPath
    if ($HostPoolRegistrationValidation.Status) {
        Write-Output "Remote desktop agent has been successfully re-registered to host pool '${HostPoolName}'"
    } else {
        throw "Remote desktop agent has failed to re-register to host pool '${HostPoolName}', error message: $($HostPoolRegistrationValidation.Message)"
    }
}

# All errors are terminating errors
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$InformationPreference = [System.Management.Automation.ActionPreference]::Continue
$WarningPreference = [System.Management.Automation.ActionPreference]::Continue

try {
    $CheckRDAgent = Get-Service -Name "RDAgent" -ErrorAction "SilentlyContinue"
    $CheckRDAgentBootLoader = Get-Service -Name "RDAgentBootLoader" -ErrorAction "SilentlyContinue"
    if (($Reregister -eq "True") -and ($null -ne $CheckRDAgent) -and ($null -ne $CheckRDAgentBootLoader)) {
        # To Do: If '$Reregister' is true but remote desktop
        # agent isn't installed then it fails?
        # Add function that checks if remote desktop agents are installed?

        $HostPoolRegistrationReregistrationParameters = @{
            HostPoolName                   = $HostPoolName
            RegistrationToken              = $RegistrationToken
            RemoteDesktopAgentRegistryPath = $RemoteDesktopAgentRegistryPath
        }
        Invoke-HostPoolRegistrationReregistration @HostPoolRegistrationReregistrationParameters
    } else {
        $HostPoolRegistrationValidation = Invoke-HostPoolRegistrationValidation -RemoteDesktopAgentRegistryPath $RemoteDesktopAgentRegistryPath
        if ($HostPoolRegistrationValidation.Status) {
            Write-Output "Remote desktop agent is already registered to host pool '${HostPoolName}'"
        } else {
            Write-Output "Remote desktop agent is not registered to host pool '${HostPoolName}', status message: $($HostPoolRegistrationValidation.Message)"

            $InstallRemoteDesktopAgentParameters = @{
                HostPoolName                         = $HostPoolName
                RegistrationToken                    = $RegistrationToken
                RemoteDesktopAgentBootLoaderFileName = $RemoteDesktopAgentBootLoaderFileName
                RemoteDesktopAgentBootLoaderUri      = $RemoteDesktopAgentBootLoaderUri
                RemoteDesktopAgentFileName           = $RemoteDesktopAgentFileName
                RemoteDesktopAgentRegistryPath       = $RemoteDesktopAgentRegistryPath
                RemoteDesktopAgentUri                = $RemoteDesktopAgentUri
            }
            Invoke-InstallRemoteDesktopAgent @InstallRemoteDesktopAgentParameters
            Start-Sleep -Seconds 5

            $HostPoolRegistrationValidation = Invoke-HostPoolRegistrationValidation -RemoteDesktopAgentRegistryPath $RemoteDesktopAgentRegistryPath
            if ($HostPoolRegistrationValidation.Status) {
                Write-Output "Remote desktop agent has been successfully registered to host pool '${HostPoolName}'"
            } else {
                throw "Remote desktop agent has failed to register to host pool '${HostPoolName}', error message: $($HostPoolRegistrationValidation.Message)"
            }
        }
    }
} catch {
    Write-Warning "Failed to register remote desktop agent to host pool '${HostPoolName}'"
    Write-Error -Message $PSItem.Exception.Message -Exception $PSItem.Exception -ErrorAction Stop
}

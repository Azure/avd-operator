[Cmdletbinding()]
param()

# All errors are terminating errors
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

function Write-ScriptLog {
    param(
        [Parameter(Position = 0, Mandatory)]
        [String] $Message,

        [Parameter(Position = 1)]
        [Object] $Property
    )

    $ScriptLog = @{
        Timestamp = [DateTime]::UtcNow.ToString('u')
        Message   = $Message
    }

    if ($PSBoundParameters.ContainsKey("Property")) {
        $ScriptLog = $ScriptLog + $Property
    }

    Write-Output "$($ScriptLog | ConvertTo-Json -Compress)"
}

try {
    $DsregcmdStatus = dsregcmd /status
    $EntraIdDeviceAuthStatus = ($DsregcmdStatus | Select-String -SimpleMatch 'DeviceAuthStatus').line.split(':')[-1].trim()
    $EntraIdDeviceId = ($DsregcmdStatus | Select-String -SimpleMatch 'DeviceId').line.split(':')[-1].trim()
    $ScriptLogParameters = @{
        Message  = "Successfully gathered Entra ID device status"
        Property = @{
            DeviceAuthStatus = $EntraIdDeviceAuthStatus
            DeviceId         = $EntraIdDeviceId
            Status           = "Succeeded"
        }
    }
    Write-ScriptLog @ScriptLogParameters
} catch {
    $ScriptLogParameters = @{
        Message  = "Failed to gather Entra ID device status due to error '$($PSItem.Exception.Message)'"
        Property = @{
            Status = "Failed"
        }
    }
    Write-ScriptLog @ScriptLogParameters
}

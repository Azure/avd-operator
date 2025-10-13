function Set-VirtualMachineRunCommand {
    param(
        [Parameter(Mandatory)]
        [String] $Name,

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $PSItem })]
        [String] $ScriptPath,

        [Parameter(Mandatory)]
        [String] $VirtualMachineName,

        [Parameter(Mandatory)]
        [String] $ResourceGroupName,

        [Parameter(Mandatory)]
        [String] $SubscriptionId,

        [Parameter(Mandatory)]
        [String] $Location,

        [Parameter()]
        [Object] $RunCommandLogsStorageAccount,

        [Parameter()]
        [string] $RunCommandLogsContainerName = "run-cmd-logs",

        [Parameter()]
        [Int] $TimeoutInSeconds = (New-TimeSpan -Minutes 15).TotalSeconds,

        [Parameter()]
        [Object[]] $Parameter,

        [Parameter()]
        [Object[]] $ProtectedParameter
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    # TODO: Ask if we want to set lifecycle policies on the run cmd logs container

    $VirtualMachineContext = Get-Context -SubscriptionId $SubscriptionId
    $AzVMRunCommandParameters = @{
        Confirm                         = $false
        Location                        = $Location
        ResourceGroupName               = $ResourceGroupName
        RunCommandName                  = $Name
        SourceScript                    = (Get-Content -Path $ScriptPath -Encoding "utf8" -Raw)
        SubscriptionId                  = $SubscriptionId
        TimeoutInSecond                 = $TimeoutInSeconds
        TreatFailureAsDeploymentFailure = $true
        VMName                          = $VirtualMachineName
    }

    if ($PSBoundParameters.ContainsKey("RunCommandLogsStorageAccount")) {
        $OutputBlobName = "${VirtualMachineName}-runcmd-${Name}-output.json"
        $ErrorBlobName = "${VirtualMachineName}-runcmd-${Name}-error.json"
        $StorageBlobSasUriParameters = @{
            ContainerName  = $RunCommandLogsContainerName
            PermissionSet  = "RunCommandLogs"
            StorageAccount = $RunCommandLogsStorageAccount
        }
        $StorageBlobSasUri = @($OutputBlobName, $ErrorBlobName) | Get-StorageBlobSasUri @StorageBlobSasUriParameters
        $AzVMRunCommandParameters["OutputBlobUri"] = $StorageBlobSasUri.where({ $PSItem.Name -eq $OutputBlobName }).Uri
        $AzVMRunCommandParameters["ErrorBlobUri"] = $StorageBlobSasUri.where({ $PSItem.Name -eq $ErrorBlobName }).Uri
    }

    if ($PSBoundParameters.ContainsKey("Parameter")) {
        $AzVMRunCommandParameters["Parameter"] = $Parameter
    }

    if ($PSBoundParameters.ContainsKey("ProtectedParameter")) {
        $AzVMRunCommandParameters["ProtectedParameter"] = $ProtectedParameter
    }

    $AzVMRunCommand = Set-AzVMRunCommand @AzVMRunCommandParameters

    try {
        $OutputLogFilePath = Join-Path -Path $env:TEMP -ChildPath $OutputBlobName
        Invoke-WebRequest -Uri $AzVMRunCommandParameters["OutputBlobUri"] -OutFile $OutputLogFilePath | Out-Null
        if (Test-Path $OutputLogFilePath) {
            $RunCommandOutputLogs = Get-Content -Path $OutputLogFilePath -Encoding "utf8"
        } else {
            Write-Log "Failed to find downloaded run command output logs at '${OutputLogFilePath}'" -LogLevel 'ERRORSTOP'
        }

        $ErrorLogFilePath = Join-Path -Path $env:TEMP -ChildPath $ErrorBlobName
        Invoke-WebRequest -Uri $AzVMRunCommandParameters["ErrorBlobUri"] -OutFile $ErrorLogFilePath | Out-Null
        if (Test-Path $ErrorLogFilePath) {
            $RunCommandErrorLogs = Get-Content -Path $ErrorLogFilePath -Encoding "utf8"
        } else {
            Write-Log "Failed to find downloaded run command error logs at '${ErrorLogFilePath}'" -LogLevel 'ERRORSTOP'
        }

        # TODO: Timeout too long or too short?
        $Timeout = New-TimeSpan -Minutes 5
        $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
        while (($AzVMRunCommand.ProvisioningState -ieq "Updating") -and ($StopWatch.Elapsed -lt $Timeout)) {
            Write-Log "Found run command '${Name}' for virtual machine '${VirtualMachineName}' to have a provisioning state of '$($AzVMRunCommand.ProvisioningState)', waiting 60 seconds for it to settle"
            Start-Sleep -Seconds 60
            $AzVMRunCommandParameters = @{
                DefaultProfile    = $VirtualMachineContext
                ResourceGroupName = $ResourceGroupName
                RunCommandName    = $Name
                VMName            = $VirtualMachineName
            }
            $AzVMRunCommand = Get-AzVMRunCommand @AzVMRunCommandParameters
        }
        $StopWatch.Stop()

        if ($AzVMRunCommand.ProvisioningState -ieq "Updating") {
            # TODO: Should we do anything else here?
            Write-Log "Run command '${Name}' for virtual machine '${VirtualMachineName}' still has a provisioning state of '$($AzVMRunCommand.ProvisioningState)' after waiting $($Timeout.Minutes) minutes" -LogLevel 'ERROR'
        }

        return @{
            Error             = $RunCommandErrorLogs
            Output            = $RunCommandOutputLogs
            ProvisioningState = $AzVMRunCommand.ProvisioningState
        }
    } catch {
        Write-Log "Failed to download logs for run commmand '${Name}' and virtual machine '${VirtualMachineName}' due to error '$($PSItem.Exception.Message)'" -LogLevel 'ERRORSTOP'
    } finally {
        Remove-Item -Path $OutputLogFilePath -Force -ErrorAction "SilentlyContinue"
        Remove-Item -Path $ErrorLogFilePath -Force -ErrorAction "SilentlyContinue"
    }
}
Export-ModuleMember -Function Set-VirtualMachineRunCommand

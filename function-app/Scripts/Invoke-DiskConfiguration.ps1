[Cmdletbinding()]
param()

# All errors are terminating errors
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$InformationPreference = [System.Management.Automation.ActionPreference]::Continue
$WarningPreference = [System.Management.Automation.ActionPreference]::Continue

# TODO: add timestamps to logging for local transcript
# function Get-TimeStamp { return "[{0:MM/dd/yy} {0:HH:mm:ss} UTC]" -f (Get-Date).ToUniversalTime() }
# Write-Output "$(Get-TimeStamp) - Starting Script - Cleanup Working Directories"

$ScriptName = "Disk Configuration"

try {
    $LogFileName = $ScriptName -replace "\s+", "-"
    $LogFilePath = Join-Path -Path $env:windir -ChildPath "Logs\run-cmd-${LogFileName}.log"
    Start-Transcript -Path $LogFilePath -Append -Force
    Write-Output "Starting $ScriptName Script - $(Get-Date -Format "yyyyMMdd-HH:mm")"
    Write-Output "PowerShell Language Mode: $($ExecutionContext.SessionState.LanguageMode)"

    ###

    #########################
    ## Expand Disks to Max ##
    #########################

    try {
        Write-Output "Attempting to expand size of disks to max"

        $DiskCPartition = Get-Partition -DriveLetter "C"
        $DiskCPartitionSupportedSize = Get-PartitionSupportedSize -DriveLetter "C"
        if ($DiskCPartition.Size -lt $DiskCPartitionSupportedSize.SizeMax) {
            Write-Output "Partition for 'C' drive partition is not maximum size, resizing partition"
            Resize-Partition -DriveLetter "C" -Size $DiskCPartitionSupportedSize.SizeMax
        } else {
            Write-Output "Partition for 'C' drive is already at maximum size"
        }

        Write-Output "Completed expanding size of disks to max"
    } catch {
        Write-Warning "Failed to resize partition for 'C' drive"
        Write-Error -Message $PSItem.Exception.Message -Exception $PSItem.Exception -ErrorAction Stop
    }

    ########################################
    ## Initialize and Partition Raw Disks ##
    ########################################

    try {
        Write-Output "Attempting to initialize and parition raw disks"

        $DiskConfigurations = @(
            @{
                Name        = "PageFile"
                DriveLetter = "P"
                LUN         = 20
            }
        )

        $RawDisks = Get-Disk | Where-Object { $PSItem.PartitionStyle -eq "RAW" }
        Write-Output "$($RawDisks.Count) raw disks to initialize and format"
        if (($null -ne $RawDisks) -or ($RawDisks.Count -gt 0)) {
            $RawDisks | Initialize-Disk
            $InitializedDisks = foreach ($RawDisk in $RawDisks) {
                Get-Disk -Number $RawDisk.Number
            }

            foreach ($InitializedDisk in $InitializedDisks) {
                [Int] $DiskLUN = $InitializedDisk.Location.Split(": LUN")[-1].Trim()
                Write-Output "Found new initialized disk with LUN $DiskLUN"

                if ($DiskConfigurations.LUN -contains $DiskLUN) {
                    $DiskConfiguration = $DiskConfigurations | Where-Object { $PSItem.LUN -eq $DiskLUN }
                    Write-Output "Creating new partition for disk configuration '$($DiskConfiguration.Name)' with LUN '$($DiskConfiguration.LUN)' and drive letter '$($DiskConfiguration.DriveLetter)'"
                    $NewPartition = New-Partition `
                        -DiskNumber $InitializedDisk.Number `
                        -UseMaximumSize `
                        -DriveLetter $DiskConfiguration.DriveLetter `
                        -ErrorAction Stop
                } else {
                    Write-Output "Creating new partition for unrecognized disk with LUN $DiskLUN and assign next available drive letter"
                    $NewPartition = New-Partition `
                        -DiskNumber $InitializedDisk.Number `
                        -UseMaximumSize `
                        -AssignDriveLetter `
                        -ErrorAction Stop
                }

                if ($NewPartition.OperationalStatus -ne "Online") {
                    throw "Failed to create new partition for disk '$($InitializedDisk.Number)' with LUN $DiskLUN, current operational status '$($NewPartition.OperationalStatus)'"
                }

                Start-Sleep -Seconds 10
                if ($DiskConfigurations.LUN -contains $DiskLUN) {
                    $DiskConfiguration = $DiskConfigurations | Where-Object { $PSItem.LUN -eq $DiskLUN }
                    Write-Output "Formatting new volume for disk configuration '$($DiskConfiguration.Name)' and assigned drive letter '$($NewPartition.DriveLetter)'"
                    $FormatedVolume = Format-Volume `
                        -DriveLetter $NewPartition.DriveLetter `
                        -FileSystem "NTFS" `
                        -NewFileSystemLabel $DiskConfiguration.Name `
                        -Force `
                        -Confirm:$False
                } else {
                    Write-Output "Formatting new volume for disk with LUN $DiskLUN and assigned drive letter '$($NewPartition.DriveLetter)'"
                    $FormatedVolume = Format-Volume `
                        -DriveLetter $NewPartition.DriveLetter `
                        -FileSystem "NTFS" `
                        -NewFileSystemLabel "Local Disk" `
                        -Force `
                        -Confirm:$False
                }

                if (($FormatedVolume.OperationalStatus -ne "OK") -or ($FormatedVolume.HealthStatus -ne "Healthy")) {
                    throw "Failed to create new volume for partition with drive letter '$($NewPartition.DriveLetter)', current operational status '$($FormatedVolume.OperationalStatus)' with health status of '$($FormatedVolume.HealthStatus)'"
                }
            }
        }

        Write-Output "Completed initialize and parition of raw disks"
    } catch {
        Write-Warning "Failed to initialize and parition raw disks"
        Write-Error -Message $PSItem.Exception.Message -Exception $PSItem.Exception -ErrorAction Stop
    }

    #########################
    ## Configure Page File ##
    #########################

    # Virtual machine needs to be restarted for page file changes to take affect.

    try {
        Write-Output "Attempting to configure page file"

        Set-CimInstance -Query "SELECT * FROM Win32_ComputerSystem" -Property @{ AutomaticManagedPageFile = $false }
        Remove-CimInstance -Query "SELECT * FROM Win32_PageFileSetting"
        $PageFileDiskConfiguration = $DiskConfigurations | Where-Object { $PSItem.Name -eq "PageFile" }
        $NewPageFilePath = "$($PageFileDiskConfiguration.DriveLetter):\\pagefile.sys"
        New-CimInstance -ClassName Win32_PageFileSetting -Property @{ Name = $NewPageFilePath }

        # Define specific page file size
        # $intialSize = #Optional
        # $maximumSize = #Optional
        # Set-CimInstance -Query "SELECT * FROM Win32_PageFileSetting" #-Property @{InitialSize=$intialSize;MaximumSize=$maximumSize} #Optional:defaults to System Managed Size

        Write-Output "Completed configuration of page file"
    } catch {
        Write-Warning "Failed to configure page file"
        Write-Error -Message $PSItem.Exception.Message -Exception $PSItem.Exception -ErrorAction Stop
    }

    ###

    Write-Output "Completed $ScriptName Script - $(Get-Date -Format "yyyyMMdd-HH:mm")"
} finally {
    Stop-Transcript -ErrorAction SilentlyContinue
}

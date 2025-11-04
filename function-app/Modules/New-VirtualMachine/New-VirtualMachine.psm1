function New-VirtualMachine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String] $Name,

        [Parameter(Mandatory)]
        [String] $Location,

        [Parameter(Mandatory)]
        [Object] $ResourceGroup,

        [Parameter(Mandatory)]
        [Object] $AuthKeyVault,

        [Parameter(Mandatory)]
        [String] $DiskEncryptionSetId,

        [Parameter(Mandatory)]
        [String] $FslogixStorageAccountName,

        [Parameter(Mandatory)]
        [String] $GalleryImageDefinitionId,

        [Parameter(Mandatory)]
        [String] $GalleryImageDefinitionVersionName,

        [Parameter(Mandatory)]
        [String] $SkuSize,

        [Parameter(Mandatory)]
        [Object] $Subnet,

        [Parameter(Mandatory)]
        [Object] $Tags,

        [Parameter(Mandatory)]
        [String] $Environment,

        [Parameter()]
        [String] $AdminUsername = "xadmin",

        [Parameter()]
        [String] $TimeZone = "Eastern Standard Time"
    )

    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $ComputeContext = Get-Context -SubscriptionId $ResourceGroup.SubscriptionId

    $VirtualMachineParameters = @{
        DefaultProfile    = $ComputeContext
        ErrorAction       = "SilentlyContinue"
        Name              = $Name
        ResourceGroupName = $ResourceGroup.Name
    }
    $ExistingVirtualMachine = Get-AzVM @VirtualMachineParameters
    if ($null -ne $ExistingVirtualMachine) {
        Write-Log "Found existing virtual machine '${Name}' in resource group '$($ResourceGroup.Name)' and network '$($Subnet.Name)'"
        $VirtualMachine = $ExistingVirtualMachine.Id | Get-ResourceInformation
    } else {
        Write-Log "Creating virtual machine '${Name}' in resource group '$($ResourceGroup.Name)' and network '$($Subnet.Name)'"

        $AzVMConfigParameters = @{
            DefaultProfile   = $ComputeContext
            EnableSecureBoot = $true
            EnableVtpm       = $true
            EncryptionAtHost = $true
            ErrorAction      = "Stop"
            IdentityType     = "SystemAssigned"
            LicenseType      = "Windows_Client"
            SecurityType     = "TrustedLaunch"
            Tags             = $Tags
            VMName           = $Name
            VMSize           = $SkuSize
        }
        $VirtualMachineConfig = New-AzVMConfig @AzVMConfigParameters
        if ($VirtualMachineConfig.StatusCode -ne 0) {
            Write-Log "Failed to create configuration for virtual machine '${Name}'" -LogLevel 'ERRORSTOP'
        }

        $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()'
        $bytes = New-Object byte[] 24
        [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bytes)
        $password = -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
        $SecureAdminPassword = ConvertTo-SecureString -String $password -AsPlainText -Force
        $AdminCredentials = New-Object System.Management.Automation.PSCredential ($AdminUsername, $SecureAdminPassword)
        $AzVMOperatingSystemParameters = @{
            DefaultProfile   = $ComputeContext
            AssessmentMode   = "ImageDefault"
            ComputerName     = $Name
            Credential       = $AdminCredentials
            EnableAutoUpdate = $true
            ErrorAction      = "Stop"
            PatchMode        = "AutomaticByOS"
            ProvisionVMAgent = $true
            TimeZone         = $TimeZone
            VM               = $VirtualMachineConfig
            Windows          = $true
            WinRMHttp        = $true
        }
        $AzVMOperatingSystem = Set-AzVMOperatingSystem @AzVMOperatingSystemParameters
        if ($AzVMOperatingSystem.StatusCode -ne 0) {
            Write-Log "Failed to set OS on configuration for virtual machine '${Name}'" -LogLevel 'ERRORSTOP'
        }

        $AzNetworkInterfaceParameters = @{
            DefaultProfile              = $ComputeContext
            Confirm                     = $false
            EnableAcceleratedNetworking = $true
            ErrorAction                 = "Stop"
            Force                       = $true
            IpConfigurationName         = "primary"
            Location                    = $Location
            Name                        = "${Name}-NIC"
            ResourceGroupName           = $ResourceGroup.Name
            SubnetId                    = $Subnet.Id
        }
        $NetworkInterface = New-AzNetworkInterface @AzNetworkInterfaceParameters
        if ($NetworkInterface.ProvisioningState -ine "Succeeded") {
            Write-Log "Failed to create network interface for virtual machine '${Name}'" -LogLevel 'ERRORSTOP'
        }

        $AzVMNetworkInterfaceParameters = @{
            DefaultProfile = $ComputeContext
            DeleteOption   = "Delete"
            ErrorAction    = "Stop"
            Id             = $NetworkInterface.Id
            Primary        = $true
            VM             = $VirtualMachineConfig
        }
        $AzVMNetworkInterface = Add-AzVMNetworkInterface @AzVMNetworkInterfaceParameters
        if ($AzVMNetworkInterface.StatusCode -ne 0) {
            Write-Log "Failed to add network interface to configuration for virtual machine '${Name}'" -LogLevel 'ERRORSTOP'
        }

        $AzVMOSDiskParameters = @{
            Caching             = "ReadWrite"
            CreateOption        = "FromImage"
            DefaultProfile      = $ComputeContext
            DeleteOption        = "Delete"
            DiskEncryptionSetId = $DiskEncryptionSetId
            DiskSizeInGB        = 256
            ErrorAction         = "Stop"
            Name                = "${Name}-OS-DISK"
            StorageAccountType  = "Premium_LRS"
            VM                  = $VirtualMachineConfig
            Windows             = $true
        }
        $AzVMOSDisk = Set-AzVMOSDisk @AzVMOSDiskParameters
        if ($AzVMOSDisk.StatusCode -ne 0) {
            Write-Log "Failed to set OS disk on configuration for virtual machine '${Name}'" -LogLevel 'ERRORSTOP'
        }

        $AzVMDataDiskParameters = @{
            Caching             = "ReadOnly"
            CreateOption        = "Empty"
            DefaultProfile      = $ComputeContext
            DeleteOption        = "Delete"
            DiskEncryptionSetId = $DiskEncryptionSetId
            DiskSizeInGB        = 64
            ErrorAction         = "Stop"
            Lun                 = 20
            Name                = "${Name}-PAGEFILE-DISK"
            StorageAccountType  = "Premium_LRS"
            VM                  = $VirtualMachineConfig
        }
        $AzVMDataDisk = Add-AzVMDataDisk @AzVMDataDiskParameters
        if ($AzVMDataDisk.StatusCode -ne 0) {
            Write-Log "Failed to add page file data disk to configuration for virtual machine '${Name}'" -LogLevel 'ERRORSTOP'
        }

        $AzVMBootDiagnosticParameters = @{
            DefaultProfile = $ComputeContext
            Disable        = $true
            ErrorAction    = "Stop"
            VM             = $VirtualMachineConfig
        }
        $AzVMBootDiagnostic = Set-AzVMBootDiagnostic @AzVMBootDiagnosticParameters
        if ($AzVMBootDiagnostic.StatusCode -ne 0) {
            Write-Log "Failed to disable boot diagnostic on configuration for virtual machine '${Name}'" -LogLevel 'ERRORSTOP'
        }

        $AzVMSourceImageParameters = @{
            DefaultProfile = $ComputeContext
            ErrorAction    = "Stop"
            Id             = "${GalleryImageDefinitionId}/versions/${GalleryImageDefinitionVersionName}"
            VM             = $VirtualMachineConfig
        }
        $AzVMSourceImage = Set-AzVMSourceImage @AzVMSourceImageParameters
        if ($AzVMSourceImage.StatusCode -ne 0) {
            Write-Log "Failed to set source image on configuration for virtual machine '${Name}'" -LogLevel 'ERRORSTOP'
        }

        $AzVMParameters = @{
            Confirm                = $false
            DefaultProfile         = $ComputeContext
            DisableBginfoExtension = $true
            ErrorAction            = "Stop"
            Location               = $Location
            ResourceGroupName      = $ResourceGroup.Name
            VM                     = $VirtualMachineConfig
        }
        $CreatedVirtualMachine = New-AzVM @AzVMParameters
        if ($CreatedVirtualMachine.IsSuccessStatusCode) {
            $VirtualMachineParameters["ErrorAction"] = "Stop"
            $VirtualMachine = (Get-AzVM @VirtualMachineParameters).Id | Get-ResourceInformation
            if ($Environment -ne "PROD") {
                $scheduledShutdownResourceId = "/subscriptions/$($VirtualMachine.SubscriptionId)/resourcegroups/$($VirtualMachine.ResourceGroupName)/providers/microsoft.devtestlab/schedules/shutdown-computevm-$($VirtualMachine.Name)"
                $properties = @{}
                $properties.add('status', 'Enabled')
                $properties.add('tasktype', 'ComputeVmShutdownTask')
                $properties.add('dailyRecurrence', @{'time'= "18:00"})
                $properties.add('timezoneid', 'Pacific Standard Time')
                $properties.add('targetresourceid', $VirtualMachine.Id)    
                try {
                    New-AzResource -Location $Location -ResourceId $scheduledShutdownResourceId -Properties $properties -Force | Out-Null
                    Write-Log "Auto shutdown schedule has been created for virtual machine '${Name}'"
                } catch {
                    Write-Log "Failed to create Auto shutdown schedule for virtual machine '${Name}'" -LogLevel 'ERROR'
                    Write-Log $PSItem.Exception.Message -Exception $PSItem.Exception -LogLevel 'ERRORSTOP'
                }
            }
        } else {
            Write-Log "Failed to create virtual machine '${Name}' due to error '$($CreatedVirtualMachine.ReasonPhrase)'" -LogLevel 'ERRORSTOP'
        }
    }

    return $VirtualMachine
}
Export-ModuleMember -Function New-VirtualMachine

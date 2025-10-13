function Get-StorageBlobSasUri {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [String] $BlobName,

        [Parameter(Mandatory)]
        [Object] $StorageAccount,

        [Parameter(Mandatory)]
        [String] $ContainerName,

        [Parameter()]
        [ValidateSet("RunCommandLogs", "Standard")]
        [String] $PermissionSet = "Standard"
    )

    begin {
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

        $StorageContext = Get-Context -SubscriptionId $StorageAccount.SubscriptionId

        $StorageBlobSasUri = [System.Collections.Generic.List[Object]]::new()
        $AzStorageAccountParameters = @{
            DefaultProfile    = $StorageContext
            ErrorAction       = "Stop"
            Name              = $StorageAccount.Name
            ResourceGroupName = $StorageAccount.ResourceGroupName
        }
        $StorageAccount = Get-AzStorageAccount @AzStorageAccountParameters

        $AzStorageAccountSASTokenParameters = @{
            Context        = $StorageAccount.Context
            DefaultProfile = $StorageContext
            ExpiryTime     = (Get-Date).AddHours(1)
            Protocol       = "HttpsOnly"
            ResourceType   = @("Container", "Object")
            Service        = "Blob"
        }

        switch ($PermissionSet) {
            "RunCommandLogs" {
                $AzStorageAccountSASTokenParameters["Permission"] = "rlacw"
            }

            "Standard" {
                $AzStorageAccountSASTokenParameters["Permission"] = "rl"
            }
        }
        $StorageSasToken = New-AzStorageAccountSASToken @AzStorageAccountSASTokenParameters
    }

    process {
        $StorageBlobSasUri.Add(@{
                Name = $BlobName
                Uri  = "$($StorageAccount.PrimaryEndpoints.Blob)${ContainerName}/${BlobName}?${StorageSasToken}"
            }
        )
    }

    end {
        return $StorageBlobSasUri
    }
}
Export-ModuleMember -Function Get-StorageBlobSasUri

param (
    [Parameter (Mandatory = $true)] [int] $threshold #Percentage of used fileshare space, triggers adding more space
)

filter timestamp { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $_" }

Connect-AzAccount -Environment AzureUSGovernment -Identity -WarningAction Ignore | Write-Debug
$Context = Set-AzContext -Subscription ''
Write-Output "Subscription Context: $($Context.Subscription.Name)" | timestamp

$StorageAccounts = Get-AzStorageAccount | Where-Object { ($_.ResourceGroupName -eq "P-ARMY-AVD-AZ-FSLOGIX") -or ($_.ResourceGroupName -eq "P-ARMY-AVD-VA-FSLOGIX") }
$StorageAccounts = $StorageAccounts | Where-Object { ($_.Kind -eq "FileStorage") }
foreach ($SA in $StorageAccounts) {
    $ring = $SA.Tags["ring"]

    switch -regex ($ring) {
        "^(INT)(0[1-9]|[1-9][0-9])$" { $additionalSpace = 1024 }
        "^(PLT)(0[1-9]|[1-9][0-9])$" { $additionalSpace = 10240 }
        "^(BRD)(0[1-9]|[1-9][0-9])$" { $additionalSpace = 10240 }
        default { $additionalSpace = 100 }
    }

    $shares = Get-AzStorageShare -Context $SA.Context -ErrorAction SilentlyContinue
    if ($shares) {
        foreach ($share in $shares) {
            Write-Output "$($SA.StorageAccountName) contains file share: $($share.Name)" | timestamp

            $stats = $share.ShareClient.GetStatistics()
            $usedGB = [math]::Round($stats.Value.ShareUsageInBytes / 1GB, 2)
            $quota = $share.ShareProperties.QuotaInGB
            $availableGB = ($quota - $usedGB)

            if ($SA.LargeFileSharesState -eq "Enabled") {
                $maxCapacity = 102400
            } elseif ($null -eq $SA.LargeFileSharesState) {
                $maxCapacity = 5120
            }

            $availableCapacity = ($maxCapacity - $quota)
            $percentUsed = [math]::Round(($usedGB / $quota) * 100, 2)

            if ($percentUsed -gt $threshold) {
                Write-Output "$($SA.StorageAccountName)\$($share.Name) -- Used: $($usedGB)GB Available: $($availableGB)GB QuotaSize: $($quota)GB PercentUsed: $($percentUsed)% MaxCapacity: $($maxCapacity)GB AvailableCapacity: $($availableCapacity)GB" | timestamp
                Write-Output "$($SA.StorageAccountName)\$($share.Name) has used more than $($threshold)% of it's storage. Proceeding to capacity validation." | timestamp
                if ($availableCapacity -gt $additionalSpace) {
                    Write-Output "$($SA.StorageAccountName)\$($share.Name) has adequate available capacity. Proceeding to increase the file share's quota." | timestamp
                    Set-AzStorageShareQuota -ShareName $share.Name -Quota ($quota + $additionalSpace) -Context $SA.Context | Write-Debug
                    $newSize = (Get-AzStorageShare -Name $share.Name -Context $SA.Context).ShareProperties.QuotaInGB
                    Write-Output "$($SA.StorageAccountName)\$($share.Name) has been increased by $($additionalSpace)GB. New Quota size is $($newSize)GB" | timestamp
                } elseif ($availableCapacity -gt 0) {
                    Write-Output "$($SA.StorageAccountName)\$($share.Name) has limited available capacity. Proceeding to increase the file share's quota to max capacity." | timestamp
                    Set-AzStorageShareQuota -ShareName $share.Name -Quota ($quota + $availableCapacity) -Context $SA.Context | Write-Debug
                    $newSize = (Get-AzStorageShare -Name $share.Name -Context $SA.Context).ShareProperties.QuotaInGB
                    Write-Output "$($SA.StorageAccountName)\$($share.Name) has been increased by $($availableCapacity)GB. New Quota size is $($newSize)GB" | timestamp
                } else {
                    Write-Output "$($SA.StorageAccountName)\$($share.Name) does not have adequate available capacity. The quota is already set to the Max Capacity." | timestamp
                }
            } else {
                Write-Output "$($SA.StorageAccountName)\$($share.Name) -- Used: $($usedGB)GB Available: $($availableGB)GB QuotaSize: $($quota)GB PercentUsed: $($percentUsed)% MaxCapacity: $($maxCapacity)GB AvailableCapacity: $($availableCapacity)GB" | timestamp
                Write-Output "$($SA.StorageAccountName)\$($share.Name) has not used more than $($threshold)% of it's storage. The quota will not be increased." | timestamp
            }
        }
    }
}

function AVDUserMigration {
    param (
        [Parameter (Mandatory = $true)] [string] $userPrincipalName,
        [Parameter (Mandatory = $true)] [string] $destinationAVDGroupName,
        [Parameter (Mandatory = $true)] [ValidateSet("A", "B")] [string] $currentSlice
    )

    Connect-MgGraph -Environment USGov #-Identity -NoWelcome
    Connect-AzAccount -Environment AzureUSGovernment -Tenant "<REMOVED>.onmicrosoft.us" -Subscription "CAZ-W0FUAA-AVD-P-IL5" #-Identity -WarningAction Ignore | Write-Debug

    #GET THE USER'S CURRENT AVD GROUP
    $user = Get-MgUser -Filter "userPrincipalName eq '$userPrincipalName'" -Select id, displayName, OnPremisesSamAccountName
    if (!$user) {
        Write-Output "User not found"
        exit
    }
    Write-Output "User found: $($user.displayName)"
    $SAM = $user.OnPremisesSamAccountName
    $AVDGroupIds = @(
        "f73a3aec-37f1-47cd-8236-a254b0a2dc03", #ARMY-AVD-USER-BROAD-GENERAL-01-01
        "4b61cfc3-47a4-484b-8593-1332fb3e6504", #ARMY-AVD-USER-BROAD-GENERAL-01-02
        "c535433c-43db-4eaa-b3fc-615aabc2e3f4", #ARMY-AVD-USER-BROAD-GENERAL-01-03
        "25470a17-c256-441e-b6cc-79d8162deddd", #ARMY-AVD-USER-BROAD-GENERAL-01-04
        "1137d1c2-37c4-4fc0-9f13-e3d89ba4eb81", #ARMY-AVD-USER-BROAD-GENERAL-02-01
        "259beb51-c451-496f-89e0-bd72d8156e54", #ARMY-AVD-USER-BROAD-GENERAL-02-02
        "bc8ba8dc-dc69-4d0f-944d-25adf52f8c4e", #ARMY-AVD-USER-BROAD-GENERAL-02-03
        "8f323d77-d72c-434b-b4f9-15fe2d2f602d"  #ARMY-AVD-USER-BROAD-GENERAL-02-04
    )
    $userGroup = Get-MgUserMemberOf -UserId $user.id | Where-Object { $AVDGroupIds -contains $_.Id }
    $group = Get-MgGroup -GroupId $Usergroup.Id
    $sourceAVDGroupName = $group.DisplayName
    $sourceAVDGroupId = $group.Id
    Write-Output "User AVD Group found: $($user.displayName) : $($sourceAVDGroupName)"

    switch ($sourceAVDGroupName) {
        "ARMY-AVD-USER-BROAD-GENERAL-01-01" { $hostpools = @{"P-ARMY-AVD-VA-BRD01$($currentSlice)-1" = "p-army-avd-va-core" }, @{"P-ARMY-AVD-AZ-BRD01$($currentSlice)-1" = "p-army-avd-az-core" } }
        "ARMY-AVD-USER-BROAD-GENERAL-01-02" { $hostpools = @{"P-ARMY-AVD-VA-BRD01$($currentSlice)-2" = "p-army-avd-va-core" }, @{"P-ARMY-AVD-AZ-BRD01$($currentSlice)-2" = "p-army-avd-az-core" } }
        "ARMY-AVD-USER-BROAD-GENERAL-01-03" { $hostpools = @{"P-ARMY-AVD-VA-BRD01$($currentSlice)-3" = "p-army-avd-va-core" }, @{"P-ARMY-AVD-AZ-BRD01$($currentSlice)-3" = "p-army-avd-az-core" } }
        "ARMY-AVD-USER-BROAD-GENERAL-01-04" { $hostpools = @{"P-ARMY-AVD-VA-BRD01$($currentSlice)-4" = "p-army-avd-va-core" }, @{"P-ARMY-AVD-AZ-BRD01$($currentSlice)-4" = "p-army-avd-az-core" } }
        "ARMY-AVD-USER-BROAD-GENERAL-02-01" { $hostpools = @{"P-ARMY-AVD-VA-BRD02$($currentSlice)-1" = "p-army-avd-va-core" }, @{"P-ARMY-AVD-AZ-BRD02$($currentSlice)-1" = "p-army-avd-az-core" } }
        "ARMY-AVD-USER-BROAD-GENERAL-02-02" { $hostpools = @{"P-ARMY-AVD-VA-BRD02$($currentSlice)-2" = "p-army-avd-va-core" }, @{"P-ARMY-AVD-AZ-BRD02$($currentSlice)-2" = "p-army-avd-az-core" } }
        "ARMY-AVD-USER-BROAD-GENERAL-02-03" { $hostpools = @{"P-ARMY-AVD-VA-BRD02$($currentSlice)-3" = "p-army-avd-va-core" }, @{"P-ARMY-AVD-AZ-BRD02$($currentSlice)-3" = "p-army-avd-az-core" } }
        "ARMY-AVD-USER-BROAD-GENERAL-02-04" { $hostpools = @{"P-ARMY-AVD-VA-BRD02$($currentSlice)-4" = "p-army-avd-va-core" }, @{"P-ARMY-AVD-AZ-BRD02$($currentSlice)-4" = "p-army-avd-az-core" } }
    }

    #CHECK AVD SESSIONS FOR THE USER
    foreach ($pool in $hostpools) {
        $hostpool = $pool.Keys
        $hostpoolRG = $pool.Values
        $userSession = Get-AzWvdUserSession -HostPoolName $hostpool -ResourceGroupName $hostpoolRG | Select-Object Name, UserPrincipalName, SessionState | Where-Object { $_.UserPrincipalName -eq $userPrincipalName }
        if ($userSession) {
            Write-Output "$($userPrincipalName)'s session is $($userSession.sessionstate) for Host Pool $($hostpool)."
            continue
        }
        Write-Output "$($userPrincipalName) does not have an AVD session on Host Pool $($hostpool)."

        $groupmembership = Get-AzADGroupMember -GroupObjectId $sourceAVDGroupId | Where-Object { $_.Id -eq '240b2cc5-d9e0-4e02-b8d3-6ccf2948db4e' } #$user.id}
        if ($groupmembership) {
            try {
                # Remove-AzADGroupMember -GroupObjectId $sourceAVDGroupId -MemberObjectId $user.Id
                Write-Output "$($userPrincipalName) has been removed from $($sourceAVDGroupName)."
            } catch {
                Write-Warning "Failed to remove user from the AVD Group"
                Throw $_
            }
        }

        #MIGRATE THE PROFILE VHDs TO THE NEW SHARES
        #REGEX description: (?<x>\d) assigned the digit in the group the value of 'x', then the value is used as a variable. repeats for 'y'
        if ($sourceAVDGroupName -match "GENERAL-0(?<x>\d)-0(?<y>\d)") {
            $xValue = $Matches['x']
            $yValue = $Matches['y']
            $sourceAZSAName = "parmyavdazbrd0${xValue}fslogix${yValue}"
            $sourceVASAName = "parmyavdvabrd0${xValue}fslogix${yValue}"
        }
        #REGEX description: (?<x>\d) assigned the digit in the group the value of 'x', then the value is used as a variable. repeats for 'y'
        if ($destinationAVDGroupName -match "GENERAL-0(?<x>\d)-0(?<y>\d)") {
            $xValue = $Matches['x']
            $yValue = $Matches['y']
            $destinationAZSAName = "parmyavdazbrd0${xValue}fslogix${yValue}"
            $destinationVASAName = "parmyavdvabrd0${xValue}fslogix${yValue}"
        }

        $shareName = "profiles"
        $VHDPath = "$($SAM)_*/profile_$($SAM).vhdx"
        if ($hostpool -like "*-AZ-*") {
            $StorageAccountRG = "P-ARMY-AVD-AZ-FSLOGIX"
            $SourceStorageAccountName = $destinationAZSAName
            $DestinationStorageAccountName = $destinationAZSAName
            $tableSARG = "P-ARMY-AVD-AZ-CORE"
            $tableSAName = "parmyavdazassets"
            $region = "AZ"
        } elseif ($hostpool -like "*-VA-*") {
            $StorageAccountRG = "P-ARMY-AVD-VA-FSLOGIX"
            $SourceStorageAccountName = $destinationVASAName
            $DestinationStorageAccountName = $destinationVASAName
            $tableSARG = "P-ARMY-AVD-VA-CORE"
            $tableSAName = "parmyavdvaassets"
            $region = "VA"
        }

        $sourceStorageAccount = Get-AzStorageAccount -ResourceGroupName $StorageAccountRG -Name $SourceStorageAccountName
        $sourceFileShare = Get-AzStorageShare -Context $sourceStorageAccount.Context -Name $shareName
        $destinationStorageAccount = Get-AzStorageAccount -ResourceGroupName $StorageAccountRG -Name $DestinationStorageAccountName
        $destinationFileShare = Get-AzStorageShare -Context $destinationStorageAccount.Context -Name $shareName
        try {
            # Start-AzStorageFileCopy -SrcShareName $sourceFileShare.Name -SrcFilePath $VHDPath -DestShareName $destinationFileShare.Name -DestFilePath $VHDPath
        } catch {
            Write-Warning "Failed to copy $($VHDPath) from $($SourceStorageAccountName) to $($DestinationStorageAccountName)"
            try {
                # Add-AzADGroupMember -TargetGroupObjectId $sourceAVDGroupId -MemberObjectId $user.Id
                Write-Output "$($userPrincipalName) has been re-added back to $($sourceAVDGroupName) after VHD copy failure."
            } catch {
                Write-Warning "Failed to re-add $($userPrincipalName) to $($sourceAVDGroupName) after VHD copy failure."
            }
            Throw $_
        }
    }

    #MIGRATE USER TO THE NEW AVD GROUP
    $destinationAVDGroup = Get-AzADGroup -Filter "DisplayName eq '$destinationAVDGroupName'"
    try {
        # Add-AzADGroupMember -TargetGroupObjectId $destinationAVDGroup.id -MemberObjectId $user.Id
        Write-Output "$($userPrincipalName) has been added to $($destinationAVDGroup.DisplayName)."
    } catch {
        Write-Warning "Failed to add user to the new AVD Group"
        Throw $_
    }

    #Edit the Storage Account table to track migrated profile.vhdx for deleting in the future
    # $tableName = "Migrated User Profiles"
    #$tableStorageAccount = Get-AzStorageAccount -ResourceGroupName $tableSARG -Name $tableSAName
    #$Table = (Get-AzStorageTable -Context $tableStorageAccount.Context -Table $tableName).CloudTable
    #$data = @{
    #UserDisplayName = $user.displayName
    #RowKey = $userPrincipalName
    #PartitionKey = $region
    #Timestamp = (get-date)
    #MigratedFrom = $sourceFileShare.Name
    #MigratedTo = $destinationFileShare.Name
    #OriginalProfileRemoved = $null
    #}
    # $tableEntity = New-Object -TypeName PSObject -Property $data
    # Add-AzTableRow -Context $storageContext -Table $tableName -Property $tableEntity
    # Write-Output "Data inserted into table $($tableName)."
}

AVDUserMigration -userPrincipalName "scott.w.defillippo.ctr@army.mil" -destinationAVDGroupName "ARMY-AVD-USER-BROAD-GENERAL-02-04" -currentSlice "B"

###file permissions
##delete old profile (separate task) need to track somehow (send to a table in azure storage)
$userPrincipalName = "scott.w.defillippo.ctr@army.mil"
$destinationAVDGroupName = "ARMY-AVD-USER-BROAD-GENERAL-02-04"
$currentSlice = "B"
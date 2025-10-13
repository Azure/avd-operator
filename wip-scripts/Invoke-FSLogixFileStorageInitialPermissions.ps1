$StorageAccountNames = @(
    "parmyavdazbrd01fslogix2"
)

$Identities = @{
    Administrators = New-Object System.Security.Principal.NTAccount("Administrators")
    CreatorOwner   = New-Object System.Security.Principal.NTAccount("CREATOR OWNER")
    System         = New-Object System.Security.Principal.NTAccount("NT AUTHORITY\SYSTEM")
    Users          = New-Object System.Security.Principal.NTAccount("Users")
}

$AdminsFullControlRootSubFoldersFilesAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($Identities.Administrators, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$SystemFullControlRootSubFoldersFilesAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($Identities.System, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$UsersModifyRootFolderOnlyAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($Identities.Users, "AppendData,WriteExtendedAttributes,WriteAttributes,ReadAndExecute", "None", "None", "Allow")
$CreatorOwnerModifySubFoldersFilesAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($Identities.CreatorOwner, "Modify", "ContainerInherit,ObjectInherit", "InheritOnly", "Allow")

Connect-AzAccount -Environment "AzureUSGovernment" -Identity

$StorageAccounts = (Get-AzStorageAccount).where({ $StorageAccountNames -icontains $PSItem.StorageAccountName })
$StorageAccountProfileShares = foreach ($StorageAccount in $StorageAccounts) {
    $StorageAccountKey = (Get-AzStorageAccountKey `
            -Name $StorageAccount.StorageAccountName `
            -ResourceGroupName $StorageAccount.ResourceGroupName).where({ $PSItem.keyname -eq "key1" }).value

    $StorageAccountContext = New-AzStorageContext `
        -StorageAccountName $StorageAccount.StorageAccountName `
        -StorageAccountKey $StorageAccountKey

    $StorageAccountShares = Get-AzStorageShare `
        -Context $StorageAccountContext

    if ($StorageAccountShares.Name -inotcontains "profiles") {
        New-AzStorageShare -Name "profiles" -Context $StorageAccountContext | Out-Null
    }

    @{
        UNCPath     = "\\$($StorageAccount.StorageAccountName).file.core.usgovcloudapi.net\profiles"
        Credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "/user:localhost\$($StorageAccount.StorageAccountName)", (ConvertTo-SecureString -AsPlainText $StorageAccountKey -Force)
    }
}

foreach ($Share in $StorageAccountProfileShares) {
    $UsedDriveLetters = (Get-PSDrive | Where-Object { $PSItem.Name.Length -eq 1 }).Name
    $NextAvailableLetter = (Get-ChildItem function:[d-z]: -n | Where-Object { -not (Test-Path $PSItem) } | Where-Object { $UsedDriveLetters -notcontains $PSItem.Trim(":") } | Get-Random).Trim(":")
    Write-Output "Connecting to share '$($Share.UNCPath)' using drive letter '$NextAvailableLetter'"
    $PSDrive = New-PSDrive `
        -Name $NextAvailableLetter `
        -PSProvider "FileSystem" `
        -Root $Share.UNCPath `
        -Persist `
        -Credential $Share.Credentials

    Write-Output "Getting NTFS ACL for share '$($Share.UNCPath)'"
    $ShareACL = Get-Acl -Path $PSDrive.Root
    $ShareACL.Access

    Write-Output "Removing NTFS inheritance from share '$($Share.UNCPath)'"
    $ShareACL.SetAccessRuleProtection($true, $false)

    foreach ($IdentityReference in $ShareACL.Access.IdentityReference) {
        Write-Output "Purging access rules for identity '$IdentityReference' from NTFS ACL for share '$($Share.UNCPath)'"
        $ShareACL.PurgeAccessRules($IdentityReference)
    }

    Write-Output "Setting full control access rule for identity '$($Identities.System)' on share '$($Share.UNCPath)'"
    $ShareACL.SetAccessRule($SystemFullControlRootSubFoldersFilesAccessRule)

    Write-Output "Setting full control access rule for identity '$($Identities.Administrators)' on share '$($Share.UNCPath)'"
    $ShareACL.SetAccessRule($AdminsFullControlRootSubFoldersFilesAccessRule)

    Write-Output "Setting modify creator owner access rule for identity '$($Identities.CreatorOwner)' on share '$($Share.UNCPath)'"
    $ShareACL.SetAccessRule($CreatorOwnerModifySubFoldersFilesAccessRule)

    Write-Output "Setting special user access rule for identity '$($Identities.Users)' on share '$($Share.UNCPath)'"
    $ShareACL.SetAccessRule($UsersModifyRootFolderOnlyAccessRule)

    Write-Output "Applying access rules on share '$($Share.UNCPath)'"
    Set-Acl -Path $PSDrive.Root -AclObject $ShareACL | Out-Null

    $TempPSDriveDirectories = Get-ChildItem $PSDrive.Root -Recurse -Directory
    foreach ($Directory in $TempPSDriveDirectories) {
        $ShareACL = Get-Acl $PSDrive.Root
        $ShareACL.Access | Where-Object { @("BUILTIN\Users", "Everyone") -contains $PSItem.IdentityReference } | ForEach-Object { $ShareACL.RemoveAccessRule($PSItem) | Out-Null }
        Set-Acl -Path $Directory.FullName -AclObject $ShareACL | Out-Null
    }

    Write-Output "Getting NTFS ACL for share '$($Share.UNCPath)'"
    $ShareACL = Get-Acl -Path $PSDrive.Root
    $ShareACL.Access

    Write-Output "Disconnecting share '$($Share.UNCPath)' from drive letter '$NextAvailableLetter'"
    Remove-PSDrive -Name $PSDrive.Name -Force
}

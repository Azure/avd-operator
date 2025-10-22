$StorageContainerName = "rdagent-installers"
$DownloadDirectory    = ".\$StorageContainerName\"
$RDAgentUrl           = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"
$RDBootLoaderUrl      = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH"

New-Item -Path ".\$StorageContainerName" -ItemType Directory -Force | Out-Null

$AssetStorageAccount = $parameters.parameters.pAssetStorageAccount.value
$StorageContext =  @{
    Container = $StorageContainerName
    Context   = (Get-AzStorageAccount -ResourceGroupName $AssetStorageAccount.resourceGroupName -Name $AssetStorageAccount.name).Context
    Force     = $true
}

# Regex to match version info: -[0-9\.]+\.msi$
# Explanation:
# - Matches a dash '-'
# - Followed by one or more digits or dots '[0-9\.]+'
# - Followed by '.msi' at the end of the string '\.msi$'
# Example match: '-1.0.12183.900.msi'

# RD Agent Installer
Write-Output "Downloading remote desktop agent binary '$RDAgentUrl' to '$DownloadDirectory'"
$RDAgent = Invoke-WebRequest -Uri $RDAgentUrl -UseBasicParsing -OutFile $DownloadDirectory -PassThru
$RDAgentVer = $RDAgent.OutFile.Split('-')[-1].TrimEnd('.msi')
$Metadata = @{ "Version" = $RDAgentVer }

Write-Output "Uploading remote desktop agent binary 'RDAgent.Installer' to storage account '$($AssetStorageAccount.Name)' as blob '$($RDAgent.OutFile)'"
Set-AzStorageBlobContent @StorageContext `
    -Blob $($RDAgent.OutFile.Split('\')[-1] -replace '-[0-9\.]+\.msi$', '.msi') `
    -File $RDAgent.OutFile `
    -Metadata $Metadata | Out-Null

# RD Agent Bootloader
Write-Output "Downloading remote desktop agent bootloader binary '$RDBootLoaderUrl' to '$DownloadDirectory'"
$RDBootLoader = Invoke-WebRequest -Uri $RDBootLoaderUrl -UseBasicParsing -OutFile $DownloadDirectory -PassThru
$RDBootLoaderVer = $RDBootLoader.OutFile.Split('-')[-1].TrimEnd('.msi')
$Metadata = @{ "Version" = $RDBootLoaderVer }

Write-Output "Uploading remote desktop agent bootloader binary 'RDBootLoader.Installer' to storage account '$($AssetStorageAccount.Name)' as blob '$($RDBootLoader.OutFile)'"
Set-AzStorageBlobContent @StorageContext `
    -Blob $($RDBootLoader.OutFile.Split('\')[-1] -replace '-[0-9\.]+\.msi$', '.msi') `
    -File $RDBootLoader.OutFile `
    -Metadata $Metadata | Out-Null
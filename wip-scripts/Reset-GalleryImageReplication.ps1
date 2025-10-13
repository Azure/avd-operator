param (
    [Parameter (Mandatory = $true)] [int] $replicaCount = 1
)

filter timestamp { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $_" }

#Connect to Azure
Connect-AzAccount -WarningAction Ignore | Write-Debug
$Context = Set-AzContext -Subscription '59718a1b-e6f3-4842-8dae-b93303be089f'

#List of Azure Compute Galleries
$imageGalleries = @(
    @{
        Name = "replicatest"
        ResourceGroup = "test"
        ImageDefinitions = @("imagedef1";"imagedef2")
    }
    @{
        Name = "replicatest2"
        ResourceGroup = "test"
    }
)

foreach ($gallery in $imageGalleries) {
    $imageGallery = Get-AzGallery -ResourceGroupName $gallery["ResourceGroup"] -Name $gallery["Name"] 
    if ($gallery.ImageDefinitions) {
        $imageDefinitions = Get-AzGalleryImageDefinition -ResourceGroupName $imageGallery.ResourceGroupName -GalleryName $imageGallery.Name | Where-Object {$_.Name -in $imageGalleries.ImageDefinitions}
    } else {
        $imageDefinitions = Get-AzGalleryImageDefinition -ResourceGroupName $imageGallery.ResourceGroupName -GalleryName $imageGallery.Name
    }
    $imageDefinitions = Get-AzGalleryImageDefinition -ResourceGroupName $imageGallery.ResourceGroupName -GalleryName $imageGallery.Name
    Write-Output "Gallery: $($gallery.Name) Definition(s): $($imageDefinitions.Name -join ', ')" | timestamp
    foreach ($definition in $imageDefinitions) {
        $definitionVersions = Get-AzGalleryImageVersion -ResourceGroupName $imageGallery.ResourceGroupName -GalleryName $imageGallery.Name -GalleryImageDefinitionName $definition.Name
        $latestVersion = $definitionVersions | Sort-Object -Property PublishedDate -Descending | Select-Object -First 1
        Write-Output "Gallery: $($gallery.Name) Definition: $($definition.Name) Version(s): $($definitionversions.Name -join ', ') Latest Version: $($latestVersion.Name)" | timestamp
        foreach ($version in $definitionVersions) {
            if ($version.Name -ne $latestVersion.Name) {
                if ($version.PublishingProfile.ReplicaCount -gt $replicaCount) {
                    #Update Global Replica Setting
                    Update-AzGalleryImageVersion -ResourceGroupName $imageGallery.ResourceGroupName -GalleryName $imageGallery.Name -GalleryImageDefinitionName $definition.Name -Name $version.Name -ReplicaCount $replicaCount | Write-Debug
                    Write-Output "Gallery: $($gallery.Name) Definition: $($definition.Name) Version: $($version.Name) --Global replica count updated to $replicaCount" | timestamp
                } else {
                    Write-Output "Gallery: $($gallery.Name) Definition: $($definition.Name) Version: $($version.Name) --Global replica count is already set to $replicaCount" | timestamp
                }
                $regions = $version.PublishingProfile.TargetRegions
                Write-Output "Gallery: $($gallery.Name) Definition: $($definition.Name) Version: $($version.Name) Region(s): $($regions.Name -join ', ')" | timestamp
                $targetRegions = @()
                $desiredTargetRegions = @()
                foreach ($region in $regions) {
                    $targetRegion = @{Name=$region.Name;RegionalReplicaCount = $region.RegionalReplicaCount;StorageAccountType = $region.StorageAccountType;Encryption = $region.Encryption;ExcludeFromLatest = $region.ExcludeFromLatest}
                    $targetRegions += $targetRegion
                    $desiredTargetRegion = @{Name=$region.Name;RegionalReplicaCount = $replicaCount;StorageAccountType = $region.StorageAccountType;Encryption = $region.Encryption;ExcludeFromLatest = $region.ExcludeFromLatest}
                    $desiredTargetRegions += $desiredTargetRegion
                    $jsonTargetRegions = $targetRegions | ConvertTo-Json -Compress
                    $jsonDesiredTargetRegions = $desiredTargetRegions | ConvertTo-Json -Compress
                }
                $differences = Compare-Object -ReferenceObject $jsonDesiredTargetRegions -DifferenceObject $jsonTargetRegions -PassThru
                if ($differences) {
                    #Update Regional Replica Setting
                    Update-AzGalleryImageVersion -ResourceGroupName $imageGallery.ResourceGroupName -GalleryName $imageGallery.Name -GalleryImageDefinitionName $definition.Name -Name $version.Name -TargetRegion $targetRegions -ReplicaCount $replicaCount | Write-Debug
                    Write-Output "Gallery: $($gallery.Name) Definition: $($definition.Name) Version: $($version.Name) Region(s): $($targetRegions.Name -join ', ') --Regional replica count updated to $replicaCount" | timestamp
                } else {
                    Write-Output "Gallery: $($gallery.Name) Definition: $($definition.Name) Version: $($version.Name) Region(s): $($targetRegions.Name -join ', ') --Regional replica count is already set to $replicaCount" | timestamp
                }
            }
        }
    }
}

#Disconnect from Azure
Disconnect-AzAccount | Write-Debug

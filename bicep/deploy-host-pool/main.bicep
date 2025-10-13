targetScope = 'resourceGroup'

////////////////
// Data Types //
////////////////

type tDeploymentLocation = {
  computeResourceGroup: tResourceGroup
  diskEncryptionSet: tResource
  fslogixStorageAccountName: string
  location: string
  sessionHostNamePrefix: tSessionHostNamePrefix
  virtualNetworkSubnet: tVirtualNetworkSubnet
}

type tGalleryImageDefinition = {
  name: string
  version: string
  galleryName: string
  resourceGroupName: string
  subscriptionId: string
}

type tResource = {
  name: string
  resourceGroupName: string
  subscriptionId: string
}

type tResourceGroup = {
  name: string
  subscriptionId: string
}

@maxLength(12)
type tSessionHostNamePrefix = string

type tTags = {
  deployment_source: string
  deployment_tool: string
  environment: string
  owner: string
  project: string
}

type tVirtualNetworkSubnet = {
  name: string
  virtualNetworkName: string
  resourceGroupName: string
  subscriptionId: string
}

type tLogAnalyticsWorkspace = {
  name: string
  resourceGroupName: string
  subscriptionId: string
  workspaceId: string
}

///////////////////////////
// Parameters - Required //
///////////////////////////

param pAssetStorageAccount tResource
param pAuthKeyVault tResource
param pDeploymentLocations tDeploymentLocation[]
param pEntraIdSecurityDeviceGroupName string
param pLogAnalyticsWorkspace tLogAnalyticsWorkspace
param pGalleryImageDefinition tGalleryImageDefinition
param pTags tTags
param pVirtualMachineSKUSize string

///////////////////////////
// Parameters - Optional //
///////////////////////////

param pAppConfigurationStoreName string = toUpper(resourceGroup().name)
param pApplicationGroupName string = toUpper(resourceGroup().name)
param pMainLocation string = resourceGroup().location
param pWorkspaceName string = toUpper(resourceGroup().name)

param pHostPool object = {
  CustomRdpProperties: [
    'audiocapturemode:i:1'
    'audiomode:i:0'
    'authentication level:i:0'
    'autoreconnection enabled:i:1'
    'bandwidthautodetect:i:1'
    'camerastoredirect:s:*'
    'compression:i:1'
    'devicestoredirect:s:'
    'drivestoredirect:s:'
    'dynamic resolution:i:1'
    'enablecredsspsupport:i:1'
    'enablerdsaadauth:i:1'
    'encode redirected video capture:i:1'
    'keyboardhook:i:1'
    'maximizetocurrentdisplays:i:1'
    'networkautodetect:i:1'
    'redirectclipboard:i:0'
    'redirectcomports:i:0'
    'redirectlocation:i:1'
    'redirectprinters:i:0'
    'redirectsmartcards:i:1'
    'redirectwebauthn:i:1'
    'screen mode id:i:1'
    'singlemoninwindowedmode:i:1'
    'smart sizing:i:1'
    'targetisaadjoined:i:1'
    'usbdevicestoredirect:s:'
    'videoplaybackmode:i:1'
  ]
  Name: toUpper(resourceGroup().name)
  Type: 'Pooled'
  LoadBalancerType: 'BreadthFirst'
  MaxSessionLimit: 16
  PreferredAppGroupType: 'Desktop'
  PublicNetworkAccess: 'Enabled'
  StartVMOnConnect: true
  ValidationEnvironment: false
}

@maxValue(16)
param pMaxAllowedSessionsPerHost int = 16

@maxValue(625)
param pTargetSessionHostCount int = 5

param pScalingPlanMode string = 'Bake'
param pScalingPlans tResource[]

param pSessionHostBuffer string = '0.3'

param pFunctionAppName string = replace('${pHostPool.Name}', 'HP', 'FC')
param pFunctionAppResourceGroupName string = replace('${pHostPool.Name}', 'HP', 'FC')

//////////////////////////
// Resources - Existing //
//////////////////////////

resource rDiskEncryptionSet 'Microsoft.Compute/diskEncryptionSets@2024-03-02' existing = [
  for vDeploymentLocation in pDeploymentLocations: {
    name: vDeploymentLocation.diskEncryptionSet.name
    scope: resourceGroup(
      vDeploymentLocation.diskEncryptionSet.subscriptionId,
      vDeploymentLocation.diskEncryptionSet.resourceGroupName
    )
  }
]

resource rGallery 'Microsoft.Compute/galleries@2023-07-03' existing = {
  name: pGalleryImageDefinition.galleryName
  scope: resourceGroup(pGalleryImageDefinition.subscriptionId, pGalleryImageDefinition.resourceGroupName)

  resource rImage 'images@2023-07-03' existing = {
    name: pGalleryImageDefinition.name

    resource rVersion 'versions@2023-07-03' existing = {
      name: pGalleryImageDefinition.version
    }
  }
}

resource rKeyVaultAuth 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: pAuthKeyVault.name
  scope: resourceGroup(pAuthKeyVault.subscriptionId, pAuthKeyVault.resourceGroupName)

  resource rSecretServicePrincipalClientId 'secrets@2023-07-01' existing = {
    name: 'service-principal-client-id'
  }

  resource rSecretServicePrincipalClientSecret 'secrets@2023-07-01' existing = {
    name: 'service-principal-client-secret'
  }
}

resource rResourceGroupCompute 'Microsoft.Resources/resourceGroups@2024-03-01' existing = [
  for vDeploymentLocation in pDeploymentLocations: {
    name: vDeploymentLocation.computeResourceGroup.name
    scope: subscription(vDeploymentLocation.computeResourceGroup.subscriptionId)
  }
]

resource rStorageAccountAsset 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: pAssetStorageAccount.name
  scope: resourceGroup(pAssetStorageAccount.subscriptionId, pAssetStorageAccount.resourceGroupName)

  resource rBlobService 'blobServices@2023-05-01' existing = {
    name: 'default'

    resource rContainerrdagents 'containers@2023-05-01' existing = {
      name: 'rdagent-installers'
    }
  }
}

resource rVirtualNetwork 'Microsoft.Network/virtualNetworks@2023-11-01' existing = [
  for vDeploymentLocation in pDeploymentLocations: {
    name: vDeploymentLocation.virtualNetworkSubnet.virtualNetworkName
    scope: resourceGroup(
      vDeploymentLocation.virtualNetworkSubnet.subscriptionId,
      vDeploymentLocation.virtualNetworkSubnet.resourceGroupName
    )
  }
]

resource rVirtualNetworkSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = [
  for vDeploymentLocation in pDeploymentLocations: {
    name: vDeploymentLocation.virtualNetworkSubnet.name
    parent: rVirtualNetwork[indexOf(pDeploymentLocations, vDeploymentLocation)]
  }
]

resource rScalingPlan 'Microsoft.DesktopVirtualization/scalingPlans@2024-01-16-preview' existing = [
  for vScalingPlan in pScalingPlans: {
    name: vScalingPlan.name
    scope: resourceGroup(vScalingPlan.subscriptionId, vScalingPlan.resourceGroupName)
  }
]

resource rLogAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: pLogAnalyticsWorkspace.name
  scope: resourceGroup(pLogAnalyticsWorkspace.subscriptionId, pLogAnalyticsWorkspace.resourceGroupName)
}

/////////////////////
// Resources - New //
/////////////////////

resource rAppConfigurationStore 'Microsoft.AppConfiguration/configurationStores@2024-05-01' = {
  name: pAppConfigurationStoreName
  location: pMainLocation
  tags: pTags
  sku: {
    name: 'standard'
  }
}

resource rHostPool 'Microsoft.DesktopVirtualization/hostPools@2023-09-05' = {
  name: pHostPool.Name
  location: pMainLocation
  properties: {
    customRdpProperty: '${join(pHostPool.CustomRdpProperties, ';')};'
    hostPoolType: pHostPool.Type
    loadBalancerType: pHostPool.LoadBalancerType
    maxSessionLimit: pHostPool.MaxSessionLimit
    preferredAppGroupType: pHostPool.PreferredAppGroupType
    publicNetworkAccess: pHostPool.PublicNetworkAccess
    startVMOnConnect: pHostPool.StartVMOnConnect
    validationEnvironment: pHostPool.ValidationEnvironment
  }
  tags: pTags
}

resource rApplicationGroup 'Microsoft.DesktopVirtualization/applicationGroups@2023-09-05' = {
  name: pApplicationGroupName
  location: pMainLocation
  kind: pHostPool.PreferredAppGroupType
  properties: {
    applicationGroupType: pHostPool.PreferredAppGroupType
    hostPoolArmPath: rHostPool.id
  }
  tags: pTags
}

resource rWorkspace 'Microsoft.DesktopVirtualization/workspaces@2023-09-05' = {
  name: pWorkspaceName
  location: pMainLocation
  properties: {
    applicationGroupReferences: [rApplicationGroup.id]
    publicNetworkAccess: pHostPool.PublicNetworkAccess
  }
  tags: pTags
}

// Region specific app config keys
resource rAppConfigurationStoreKeyValueComputeResourceGroupId 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-05-01' = [
  for vDeploymentLocation in pDeploymentLocations: {
    parent: rAppConfigurationStore
    name: 'ComputeResourceGroupId$${vDeploymentLocation.location}'
    properties: {
      value: rResourceGroupCompute[indexOf(pDeploymentLocations, vDeploymentLocation)].id
      tags: pTags
    }
  }
]

resource rAppConfigurationStoreKeyValueDiskEncryptionSetId 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-05-01' = [
  for vDeploymentLocation in pDeploymentLocations: {
    parent: rAppConfigurationStore
    name: 'DiskEncryptionSetId$${vDeploymentLocation.location}'
    properties: {
      value: rDiskEncryptionSet[indexOf(pDeploymentLocations, vDeploymentLocation)].id
      tags: pTags
    }
  }
]

resource rAppConfigurationStoreKeyValueFSLogixStorageAccountName 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-05-01' = [
  for vDeploymentLocation in pDeploymentLocations: {
    parent: rAppConfigurationStore
    name: 'FSLogixStorageAccountName$${vDeploymentLocation.location}'
    properties: {
      value: vDeploymentLocation.fslogixStorageAccountName
      tags: pTags
    }
  }
]

resource rAppConfigurationStoreKeyValueSessionHostNamePrefix 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-05-01' = [
  for vDeploymentLocation in pDeploymentLocations: {
    parent: rAppConfigurationStore
    name: 'SessionHostNamePrefix$${vDeploymentLocation.location}'
    properties: {
      value: vDeploymentLocation.sessionHostNamePrefix
      tags: pTags
    }
  }
]

resource rAppConfigurationStoreKeyValueSubnetId 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-05-01' = [
  for vDeploymentLocation in pDeploymentLocations: {
    parent: rAppConfigurationStore
    name: 'SubnetId$${vDeploymentLocation.location}'
    properties: {
      value: rVirtualNetworkSubnet[indexOf(pDeploymentLocations, vDeploymentLocation)].id
      tags: pTags
    }
  }
]

// Non-region specific app config keys
// changes to these values need to be copied to automation repo
var vAppConfigurationStoreKeyValues = {
  AssetStorageAccountId: rStorageAccountAsset.id
  AuthKeyVaultId: rKeyVaultAuth.id
  BakeScalingPlanId: rScalingPlan[0].id // To Do: Don't rely on index order to get correct scaling plan
  ChangesAllowed: string(true)
  CleanupScalingPlanId: rScalingPlan[2].id // To Do: Don't rely on index order to get correct scaling plan
  CompliantScalingPlanId: rScalingPlan[1].id // To Do: Don't rely on index order to get correct scaling plan
  DeploymentLocationModel: 'Centralize'
  DisconnectUsersOnlyOnDrainedSessionHosts: string(true)
  EntraIdSecurityDeviceGroupJoinEnabled: string(false)
  EntraIdSecurityDeviceGroupName: pEntraIdSecurityDeviceGroupName
  Environment: pTags.environment
  FunctionAppName: pFunctionAppName
  FunctionAppResourceGroupName: pFunctionAppResourceGroupName
  GalleryImageDefinitionId: rGallery::rImage.id
  GalleryImageDefinitionVersionName: rGallery::rImage::rVersion.name
  HostPoolId: rHostPool.id
  MaxAllowedSessionsPerHost: string(pMaxAllowedSessionsPerHost)
  ReplacementMethod: 'Tags'
  ScalingPlanMode: pScalingPlanMode
  SessionHostBuffer: json(pSessionHostBuffer)
  TargetSessionHostCount: string(pTargetSessionHostCount)
  VirtualMachineSKUSize: pVirtualMachineSKUSize
  WorkspaceId : rLogAnalyticsWorkspace.id
  WorkspaceIdentifier : pLogAnalyticsWorkspace.workspaceId
}

resource rAppConfigStoreKeyValue 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-05-01' = [
  for vAppConfigurationStoreKey in objectKeys(vAppConfigurationStoreKeyValues): {
    parent: rAppConfigurationStore
    name: vAppConfigurationStoreKey
    properties: {
      value: vAppConfigurationStoreKeyValues[vAppConfigurationStoreKey]
      tags: pTags
    }
  }
]
